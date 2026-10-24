import Foundation
import NotchKit
import Observation

/// The latest download of each subscribed feed (`CalendarSettings.subscriptions`)
/// and how it went. Downloads only when asked (`refreshIfNeeded`, `refreshNow`):
/// by the calendar module while it is on screen, by the settings window, and,
/// while event reminders are on, by `CalendarFeature`'s reminder loop, also
/// while the panel is closed: when a feed is 30 minutes old, has never
/// downloaded, or last failed (then again after `CalendarRefreshPolicy.retryDelay`).
@MainActor
@Observable
public final class SubscriptionFeeds {
    public static let shared = SubscriptionFeeds(settings: .shared)

    /// How one subscription's downloads went, for the settings window.
    public struct Status: Equatable, Sendable {
        /// When the last download succeeded.
        public internal(set) var lastUpdated: Date?
        public internal(set) var isUpdating = false
        /// The feed's own name (X-WR-CALNAME) from the last good download.
        public internal(set) var feedName: String?
        /// Why the last download failed, when it failed after the last success.
        var failure: FeedFailure?
        var lastFailure: Date?

        /// A short reason in the interface language; never the address.
        @MainActor
        public var errorText: String? { failure?.text }
    }

    /// Statuses by subscription id.
    public private(set) var statuses: [UUID: Status] = [:]
    /// The last good download's occurrences by subscription id, around today
    /// (see `coverage(now:)`); kept when a later download fails.
    private var occurrences: [UUID: [ICalendarOccurrence]] = [:]

    @ObservationIgnored private let settings: CalendarSettings
    @ObservationIgnored private var tasks: [UUID: Task<Void, Never>] = [:]

    /// In memory only, so a secret calendar never reaches the disk cache.
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = CalendarRefreshPolicy.timeout
        return URLSession(configuration: configuration)
    }()

    init(settings: CalendarSettings) {
        self.settings = settings
    }

    public func status(of id: UUID) -> Status {
        statuses[id] ?? Status()
    }

    /// Downloads each enabled feed that `CalendarRefreshPolicy` says is due.
    public func refreshIfNeeded() {
        refresh(force: false, now: Date())
    }

    /// Downloads every enabled feed that is not downloading already.
    public func refreshNow() {
        refresh(force: true, now: Date())
    }

    /// Cancels every download.
    func stop() {
        for task in tasks.values {
            task.cancel()
        }
        tasks = [:]
        for id in statuses.keys where statuses[id]?.isUpdating == true {
            statuses[id]?.isUpdating = false
        }
    }

    /// Events of the enabled subscriptions from their last good downloads.
    func events() -> [AgendaEvent] {
        settings.subscriptions.filter(\.isEnabled).flatMap { subscription in
            subscription.agendaEvents(
                from: occurrences[subscription.id] ?? [],
                feedName: statuses[subscription.id]?.feedName
            )
        }
    }

    /// Whether an enabled subscription has never downloaded, last downloaded
    /// `maximumAge` or more before `now`, or failed its latest download; for
    /// refreshing while nothing on screen asks for the feeds.
    func needsBackgroundRefresh(maximumAge: TimeInterval, now: Date) -> Bool {
        settings.subscriptions.contains { subscription in
            guard subscription.isEnabled else { return false }
            let status = statuses[subscription.id] ?? Status()
            return CalendarRefreshPolicy.isStale(
                lastSuccess: status.lastUpdated,
                hasFailed: status.failure != nil,
                maximumAge: maximumAge,
                now: now
            )
        }
    }

    /// Whether an enabled subscription is on its first download, so there is
    /// nothing of it to show yet.
    func isFetchingFirstTime() -> Bool {
        settings.subscriptions.contains { subscription in
            guard subscription.isEnabled, let status = statuses[subscription.id] else { return false }
            return status.isUpdating && status.lastUpdated == nil
        }
    }

    /// Whether an enabled subscription failed to download and has nothing from
    /// an earlier download to fall back on, so an empty agenda may only mean
    /// the feed could not be read.
    func hasFailedWithoutData() -> Bool {
        settings.subscriptions.contains { subscription in
            guard subscription.isEnabled, let status = statuses[subscription.id] else { return false }
            return status.failure != nil && status.lastUpdated == nil
        }
    }

    private func refresh(force: Bool, now: Date) {
        let subscriptions = settings.subscriptions
        reconcile(with: subscriptions)
        for subscription in subscriptions where subscription.isEnabled {
            guard let url = URL(string: subscription.address) else { continue }
            let status = statuses[subscription.id] ?? Status()
            let isInFlight = tasks[subscription.id] != nil
            let isDue = force
                ? !isInFlight
                : CalendarRefreshPolicy.shouldRefresh(
                    now: now,
                    lastSuccess: status.lastUpdated,
                    lastFailure: status.lastFailure,
                    isInFlight: isInFlight
                )
            if isDue {
                download(subscription.id, from: url, now: now)
            }
        }
    }

    /// Drops what belongs to removed subscriptions and stops downloads of
    /// disabled ones.
    private func reconcile(with subscriptions: [CalendarSubscription]) {
        let current = Set(subscriptions.map(\.id))
        let enabled = Set(subscriptions.filter(\.isEnabled).map(\.id))
        for (id, task) in tasks where !enabled.contains(id) {
            task.cancel()
            tasks[id] = nil
            statuses[id]?.isUpdating = false
        }
        for id in statuses.keys where !current.contains(id) {
            statuses[id] = nil
        }
        for id in occurrences.keys where !current.contains(id) {
            occurrences[id] = nil
        }
    }

    private func download(_ id: UUID, from url: URL, now: Date) {
        statuses[id, default: Status()].isUpdating = true
        let coverage = CalendarRefreshPolicy.coverage(now: now, calendar: .current)
        let session = Self.session
        tasks[id] = Task(priority: .utility) { [weak self] in
            let result = await Self.fetch(url, covering: coverage, session: session)
            // `stop()` or a removal cancels the task; its state is gone by then.
            guard !Task.isCancelled else { return }
            self?.finish(id, with: result)
        }
    }

    private func finish(_ id: UUID, with result: Result<FeedSnapshot, FeedFailure>) {
        tasks[id] = nil
        var status = statuses[id] ?? Status()
        status.isUpdating = false
        switch result {
        case .success(let snapshot):
            status.lastUpdated = Date()
            status.failure = nil
            status.lastFailure = nil
            status.feedName = snapshot.name
            occurrences[id] = snapshot.occurrences
        case .failure(let failure):
            // The last good occurrences stay on screen.
            status.failure = failure
            status.lastFailure = Date()
        }
        statuses[id] = status
    }

    /// Downloads and parses a feed off the main actor, in the calling task so
    /// that cancelling it stops the work at the next check. Nothing here may
    /// log or report the address: its path is the calendar's password.
    @concurrent private static func fetch(
        _ url: URL,
        covering coverage: DateInterval,
        session: URLSession
    ) async -> Result<FeedSnapshot, FeedFailure> {
        let data: Data
        do {
            let request = URLRequest(
                url: url,
                cachePolicy: .reloadIgnoringLocalCacheData,
                timeoutInterval: CalendarRefreshPolicy.timeout
            )
            let (body, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                return .failure(.httpStatus(http.statusCode))
            }
            data = body
        } catch let error as URLError {
            return .failure(FeedFailure(error))
        } catch {
            return .failure(.other)
        }
        // Google answers a bad link with an HTML page.
        guard data.range(of: Data("BEGIN:VCALENDAR".utf8)) != nil else {
            return .failure(.notACalendar)
        }
        // Parsing cannot be interrupted, so cancellation is checked around it;
        // the caller drops the result of a cancelled task.
        guard !Task.isCancelled else { return .failure(.other) }
        let feed = ICalendar.parse(data)
        guard !Task.isCancelled else { return .failure(.other) }
        return .success(FeedSnapshot(name: feed.name, occurrences: feed.occurrences(overlapping: coverage)))
    }
}

/// What a good download yields.
struct FeedSnapshot: Sendable {
    var name: String?
    var occurrences: [ICalendarOccurrence]
}

/// Why a download failed.
enum FeedFailure: Error, Equatable, Sendable {
    case httpStatus(Int)
    case offline
    case timedOut
    case hostNotFound
    case notACalendar
    case other

    init(_ error: URLError) {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff:
            self = .offline
        case .timedOut:
            self = .timedOut
        case .cannotFindHost, .dnsLookupFailed:
            self = .hostNotFound
        default:
            self = .other
        }
    }

    @MainActor
    var text: String {
        switch self {
        case .httpStatus(let code):
            localized(en: "server answered \(code)", zh: "服务器返回 \(code)")
        case .offline:
            localized(en: "offline", zh: "未联网")
        case .timedOut:
            localized(en: "timed out", zh: "连接超时")
        case .hostNotFound:
            localized(en: "server not found", zh: "找不到服务器")
        case .notACalendar:
            localized(en: "not a calendar file", zh: "不是日历文件")
        case .other:
            localized(en: "download failed", zh: "下载失败")
        }
    }
}

/// When a subscribed feed is downloaded again, and over which days.
enum CalendarRefreshPolicy {
    /// How long a download stays fresh.
    static let maximumAge: TimeInterval = 15 * 60
    /// How long to wait after a failed download before the next one.
    static let retryDelay: TimeInterval = 2 * 60
    /// How long a download may take.
    static let timeout: TimeInterval = 30

    /// Whether to download at `now`: never while a download is in flight, not
    /// within `retryDelay` of a failure newer than the last success, and
    /// otherwise when there is no download or it is `maximumAge` old.
    static func shouldRefresh(now: Date, lastSuccess: Date?, lastFailure: Date?, isInFlight: Bool) -> Bool {
        if isInFlight { return false }
        if let lastFailure, lastSuccess.map({ lastFailure > $0 }) ?? true,
           now.timeIntervalSince(lastFailure) < retryDelay {
            return false
        }
        guard let lastSuccess else { return true }
        return now.timeIntervalSince(lastSuccess) >= maximumAge
    }

    /// Whether a feed should be downloaded again in the background: it never
    /// downloaded, its last success is `maximumAge` or more old, or its latest
    /// download failed. `shouldRefresh` still decides whether that happens now.
    static func isStale(lastSuccess: Date?, hasFailed: Bool, maximumAge: TimeInterval, now: Date) -> Bool {
        if hasFailed { return true }
        guard let lastSuccess else { return true }
        return now.timeIntervalSince(lastSuccess) >= maximumAge
    }

    /// The occurrences a download keeps: from the start of yesterday to 15 days
    /// after the start of today, enough for the longest agenda.
    static func coverage(now: Date, calendar: Foundation.Calendar) -> DateInterval {
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -1, to: today) ?? today.addingTimeInterval(-86_400)
        let end = calendar.date(byAdding: .day, value: 15, to: today) ?? today.addingTimeInterval(15 * 86_400)
        return DateInterval(start: start, end: end)
    }
}

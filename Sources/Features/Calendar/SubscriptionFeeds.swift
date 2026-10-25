import Foundation
import NotchKit
import Observation
import Synchronization

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
        tasks[id] = Task(priority: .utility) { [weak self] in
            let result = await Self.fetch(url, covering: coverage)
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
        covering coverage: DateInterval
    ) async -> Result<FeedSnapshot, FeedFailure> {
        let request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: CalendarRefreshPolicy.timeout
        )
        let data: Data
        switch await FeedDownload.run(request) {
        case .success(let body):
            data = body
        case .failure(let failure):
            return .failure(failure)
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

/// How much of a feed's body a download may take in: it fails at once for an
/// announced length over the maximum and as soon as the bytes read exceed it.
struct FeedBodyLimit: Equatable, Sendable {
    let maximum: Int
    private(set) var received = 0

    init(maximum: Int = CalendarRefreshPolicy.maximumBodySize) {
        self.maximum = maximum
    }

    /// Whether a body announced as `expectedLength` bytes may be read; a
    /// negative length (unknown) always may, `accept` then counts the bytes.
    func allows(expectedLength: Int64) -> Bool {
        expectedLength <= Int64(maximum)
    }

    /// Counts `count` more bytes; false once the body exceeds the maximum.
    mutating func accept(_ count: Int) -> Bool {
        received += count
        return received <= maximum
    }
}

/// One feed download that takes the body in as the server sends it and stops
/// at `FeedBodyLimit`. A delegate rather than `URLSession.bytes(for:)`, whose
/// per-byte iteration takes minutes on a body of the maximum size. It owns
/// its session, in memory only, so a secret calendar never reaches the disk
/// cache. Nothing here may log or report the address.
private final class FeedDownload: NSObject, URLSessionDataDelegate, Sendable {
    private struct State {
        var limit = FeedBodyLimit()
        var body = Data()
        /// Why the download was cancelled, when this class cancelled it.
        var failure: FeedFailure?
        /// Whichever of the completion and the caller's continuation arrives
        /// first waits here for the other.
        var continuation: CheckedContinuation<Result<Data, FeedFailure>, Never>?
        var result: Result<Data, FeedFailure>?
    }

    private let state = Mutex(State())

    /// The body of a good (2xx) response, or why there is none. Cancelling the
    /// calling task cancels the transfer.
    static func run(_ request: URLRequest) async -> Result<Data, FeedFailure> {
        guard !Task.isCancelled else { return .failure(.other) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = CalendarRefreshPolicy.timeout
        configuration.timeoutIntervalForResource = CalendarRefreshPolicy.totalTimeout
        let download = FeedDownload()
        let session = URLSession(configuration: configuration, delegate: download, delegateQueue: nil)
        // The session holds its delegate until it is invalidated.
        defer { session.finishTasksAndInvalidate() }
        let task = session.dataTask(with: request)
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                // A task cancelled before this point cancels the suspended data
                // task first, and its completion can arrive before the
                // continuation exists; the handoff therefore goes both ways.
                let stored = download.state.withLock { state -> Result<Data, FeedFailure>? in
                    if let result = state.result { return result }
                    state.continuation = continuation
                    return nil
                }
                if let stored {
                    continuation.resume(returning: stored)
                } else {
                    task.resume()
                }
            }
        } onCancel: {
            // The delegate still gets `didCompleteWithError`, which resumes the continuation.
            task.cancel()
        }
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse
    ) async -> URLSession.ResponseDisposition {
        let failure: FeedFailure?
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            failure = .httpStatus(http.statusCode)
        } else {
            failure = state.withLock { state in
                guard state.limit.allows(expectedLength: response.expectedContentLength) else { return .tooLarge }
                // An unknown length reserves nothing; the maximum bounds a false one.
                if response.expectedContentLength > 0 {
                    state.body.reserveCapacity(Int(response.expectedContentLength))
                }
                return nil
            }
        }
        guard let failure else { return .allow }
        state.withLock { $0.failure = failure }
        return .cancel
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let isWithinLimit = state.withLock { state in
            // Bytes that arrive after the cancellation are dropped.
            guard state.failure == nil else { return false }
            guard state.limit.accept(data.count) else {
                state.failure = .tooLarge
                state.body = Data()
                return false
            }
            state.body.append(data)
            return true
        }
        if !isWithinLimit {
            dataTask.cancel()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let (continuation, result) = state.withLock { state -> (CheckedContinuation<Result<Data, FeedFailure>, Never>?, Result<Data, FeedFailure>) in
            let result: Result<Data, FeedFailure>
            if let failure = state.failure {
                result = .failure(failure)
            } else if let error {
                result = .failure((error as? URLError).map { FeedFailure($0) } ?? .other)
            } else {
                result = .success(state.body)
            }
            state.body = Data()
            guard let continuation = state.continuation else {
                state.result = result
                return (nil, result)
            }
            state.continuation = nil
            return (continuation, result)
        }
        continuation?.resume(returning: result)
    }
}

/// Why a download failed.
enum FeedFailure: Error, Equatable, Sendable {
    case httpStatus(Int)
    case offline
    case timedOut
    case hostNotFound
    case notACalendar
    case tooLarge
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
        case .tooLarge:
            localized(en: "calendar file too large", zh: "日历文件过大")
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
    /// How long a download may wait for the server's next bytes.
    static let timeout: TimeInterval = 30
    /// How long a whole download may take, however steadily the bytes arrive.
    static let totalTimeout: TimeInterval = 120
    /// The most bytes a download may hold, as decoded; large real feeds are a
    /// few megabytes.
    static let maximumBodySize = 20 * 1024 * 1024

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

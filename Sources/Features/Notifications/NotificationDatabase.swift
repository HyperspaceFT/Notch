import AppKit
import os
import SQLite3

/// One notification as usernoted keeps it in its database.
struct DatabaseNotification: Equatable, Sendable {
    var recordID: Int64
    /// As the database has it, which is lowercased for most apps.
    var bundleIdentifier: String
    var title: String?
    var subtitle: String?
    var body: String?
    /// When the app posted it, a moment before its banner (if any) showed.
    var delivered: Date
    /// A Focus held it back ("itsp" other than 0): no banner showed for it, and
    /// the island does not show it either.
    var isHeldBack: Bool
    /// The app's alert style when it arrived ("styl", as `UNAlertStyle`: 0 none,
    /// 1 banners, 2 alerts). With none the user chose no banner for the app, so
    /// the island shows nothing either.
    var showsBanner: Bool = true

    var hasContent: Bool {
        title != nil || subtitle != nil || body != nil
    }
}

/// usernoted's database, where macOS keeps every notification delivered, also
/// those that NotificationCenter never showed as a banner: when several arrive
/// within a second or so, it shows some and only lists the rest. Reading it
/// needs Full Disk Access, and its layout is private (macOS 26: a `record`
/// table whose `data` is a property list), so a macOS update may break it.
enum NotificationDatabase {
    enum ReadError: Error, Equatable {
        /// Most often no Full Disk Access.
        case cannotOpen(Int32)
        case query(Int32)
    }

    static var url: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Group Containers/group.com.apple.usernoted/db2/db")
    }

    /// Whether Notch may open the database. Without Full Disk Access macOS
    /// refuses to open a file in another app's group container; `access()` would
    /// not tell, it ignores that.
    nonisolated static func isReadable(at url: URL = url) -> Bool {
        let descriptor = open(url.path, O_RDONLY)
        guard descriptor >= 0 else { return false }
        close(descriptor)
        return true
    }

    /// The records delivered after `cutoff`, oldest first. The database is
    /// opened read-only and closed again each time, so usernoted's writes are
    /// never held up for long.
    nonisolated static func records(at url: URL, after cutoff: Date) throws(ReadError) -> [DatabaseNotification] {
        var database: OpaquePointer?
        let openStatus = sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil)
        defer { sqlite3_close_v2(database) }
        guard openStatus == SQLITE_OK, let database else { throw .cannotOpen(openStatus) }
        // usernoted may hold a write lock for a moment.
        sqlite3_busy_timeout(database, 200)

        let query = """
            SELECT r.rec_id, a.identifier, r.data, r.delivered_date
            FROM record r JOIN app a ON a.app_id = r.app_id
            WHERE r.delivered_date > ?1
            ORDER BY r.delivered_date
            """
        var statement: OpaquePointer?
        let prepareStatus = sqlite3_prepare_v2(database, query, -1, &statement, nil)
        defer { sqlite3_finalize(statement) }
        guard prepareStatus == SQLITE_OK, let statement else { throw .query(prepareStatus) }
        sqlite3_bind_double(statement, 1, cutoff.timeIntervalSinceReferenceDate)

        var records: [DatabaseNotification] = []
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { break }
            guard status == SQLITE_ROW else { throw .query(status) }
            guard
                let identifier = sqlite3_column_text(statement, 1),
                let bytes = sqlite3_column_blob(statement, 2)
            else { continue }
            let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 2)))
            let record = parse(
                recordID: sqlite3_column_int64(statement, 0),
                bundleIdentifier: String(cString: identifier),
                delivered: Date(timeIntervalSinceReferenceDate: sqlite3_column_double(statement, 3)),
                data: data
            )
            if let record {
                records.append(record)
            }
        }
        return records
    }

    /// A record from its `data` property list: "req" holds the text as "titl",
    /// "subt" and "body", "itsp" says whether a Focus held it back, and "styl"
    /// is the app's alert style.
    nonisolated static func parse(
        recordID: Int64,
        bundleIdentifier: String,
        delivered: Date,
        data: Data
    ) -> DatabaseNotification? {
        guard
            let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
            let request = plist["req"] as? [String: Any]
        else { return nil }
        return DatabaseNotification(
            recordID: recordID,
            bundleIdentifier: bundleIdentifier,
            title: text(request["titl"]),
            subtitle: text(request["subt"]),
            body: text(request["body"]),
            delivered: delivered,
            isHeldBack: (plist["itsp"] as? Int ?? 0) != 0,
            showsBanner: (plist["styl"] as? Int ?? 1) != 0
        )
    }

    private nonisolated static func text(_ value: Any?) -> String? {
        guard let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }
        return text
    }
}

/// Follows usernoted's database and reports each record delivered since `start`
/// once. usernoted writes in batches, about every five seconds, so a record
/// lands that long after its notification; the files are checked every second
/// and read only when they changed.
@MainActor
final class NotificationDatabaseWatcher {
    static let pollInterval: Duration = .seconds(1)
    /// How far back each read goes, which also bounds the IDs kept as seen.
    static let window: TimeInterval = 600

    /// The database files' modification dates and sizes: unchanged files need no read.
    private struct FileState: Equatable, Sendable {
        var database: [Double]
        var log: [Double]

        init?(url: URL) {
            guard let database = Self.stat(url.path) else { return nil }
            self.database = database
            log = Self.stat(url.path + "-wal") ?? []
        }

        private static func stat(_ path: String) -> [Double]? {
            guard
                let attributes = try? FileManager.default.attributesOfItem(atPath: path),
                let date = attributes[.modificationDate] as? Date,
                let size = attributes[.size] as? NSNumber
            else { return nil }
            return [date.timeIntervalSinceReferenceDate, size.doubleValue]
        }
    }

    private enum Outcome: Sendable {
        case unchanged
        case records(FileState?, [DatabaseNotification])
        case failed(NotificationDatabase.ReadError)
    }

    private let url: URL
    private let onRecords: @MainActor ([DatabaseNotification]) -> Void
    private var poll: Task<Void, Never>?
    private var started = Date()
    /// Only ever moves forward, so a clock set back cannot bring seen records
    /// into the window again.
    private var cutoff = Date()
    private var seen: Set<Int64> = []
    private var fileState: FileState?
    /// The last failure logged, so a lasting one is logged once.
    private var lastFailure: NotificationDatabase.ReadError?

    init(url: URL = NotificationDatabase.url, onRecords: @escaping @MainActor ([DatabaseNotification]) -> Void) {
        self.url = url
        self.onRecords = onRecords
    }

    isolated deinit {
        stop()
    }

    func start() {
        guard poll == nil else { return }
        started = Date()
        cutoff = started
        seen = []
        fileState = nil
        lastFailure = nil
        Logger.notifications.notice("Database reading started")
        poll = Task { [weak self] in
            while !Task.isCancelled {
                await self?.check()
                try? await Task.sleep(for: Self.pollInterval)
            }
        }
    }

    func stop() {
        guard let poll else { return }
        poll.cancel()
        self.poll = nil
        Logger.notifications.notice("Database reading stopped")
    }

    private func check() async {
        let url = url
        let previous = fileState
        cutoff = max(cutoff, Date().addingTimeInterval(-Self.window))
        let readCutoff = cutoff
        let outcome = await Task.detached(priority: .utility) { () -> Outcome in
            let state = FileState(url: url)
            // Files that cannot even be looked at are read anyway, so the error says why.
            if let state, state == previous { return .unchanged }
            do throws(NotificationDatabase.ReadError) {
                return .records(state, try NotificationDatabase.records(at: url, after: readCutoff))
            } catch {
                return .failed(error)
            }
        }.value
        guard poll != nil else { return }
        switch outcome {
        case .unchanged:
            break
        case .failed(let error):
            if error != lastFailure {
                Logger.notifications.error("Could not read the notification database: \(String(describing: error), privacy: .public)")
                lastFailure = error
            }
        case .records(let state, let records):
            if lastFailure != nil {
                Logger.notifications.notice("Notification database readable again")
                lastFailure = nil
            }
            fileState = state
            let new = records.filter { !seen.contains($0.recordID) }
            // Everything still in the window is seen now; older IDs never come back.
            seen = Set(records.map(\.recordID))
            if !new.isEmpty {
                onRecords(new)
            }
        }
    }
}

/// The notifications of the last minutes from each source, matched against
/// the other's, so that one notification shows once: a record from the
/// database that a banner already showed is dropped, and so is a banner that
/// NotificationCenter held back until after its record was shown. One claims
/// at most one of the other.
struct RecentBanners {
    /// How long a notification waits for its counterpart.
    static let window: TimeInterval = 120
    /// How far a banner's arrival may be from its record's delivery: NotificationCenter
    /// may hold a banner back while another shows.
    static let earliest: TimeInterval = -5
    static let latest: TimeInterval = 30

    struct Entry: Equatable {
        var bundleIdentifier: String?
        var appKey: String?
        var title: String?
        var body: String?
        /// A banner's arrival, or a record's delivery.
        var date: Date
    }

    /// Banners shown, not yet claimed by a record.
    private(set) var entries: [Entry] = []
    /// Records shown, not yet claimed by a banner.
    private(set) var shownRecords: [Entry] = []

    mutating func add(_ item: NotificationItem, now: Date = Date()) {
        prune(now: now)
        entries.append(Self.entry(item))
    }

    /// Takes the banner `record` stands for, if there is one; `appName` is the
    /// app's displayed name, which a banner may know its app by alone.
    mutating func claim(_ record: DatabaseNotification, appName: String?, now: Date = Date()) -> Bool {
        prune(now: now)
        let recordEntry = Self.entry(record, appName: appName)
        guard let match = entries.firstIndex(where: { Self.matches(banner: $0, record: recordEntry) }) else {
            return false
        }
        entries.remove(at: match)
        return true
    }

    /// Keeps a record shown without a banner, for a banner that comes later.
    mutating func addShown(_ record: DatabaseNotification, appName: String?, now: Date = Date()) {
        prune(now: now)
        shownRecords.append(Self.entry(record, appName: appName))
    }

    /// Takes the shown record the banner `item` stands for, if there is one.
    mutating func claimShown(_ item: NotificationItem, now: Date = Date()) -> Bool {
        prune(now: now)
        let banner = Self.entry(item)
        guard let match = shownRecords.firstIndex(where: { Self.matches(banner: banner, record: $0) }) else {
            return false
        }
        shownRecords.remove(at: match)
        return true
    }

    private static func entry(_ item: NotificationItem) -> Entry {
        Entry(
            bundleIdentifier: item.bundleIdentifier?.lowercased(),
            appKey: item.appName.map(NotificationAppResolver.key(for:)),
            title: item.title,
            body: item.body,
            date: item.received
        )
    }

    private static func entry(_ record: DatabaseNotification, appName: String?) -> Entry {
        Entry(
            bundleIdentifier: record.bundleIdentifier.lowercased(),
            appKey: appName.map(NotificationAppResolver.key(for:)),
            title: record.title,
            body: record.body,
            date: record.delivered
        )
    }

    private static func matches(banner: Entry, record: Entry) -> Bool {
        let offset = banner.date.timeIntervalSince(record.date)
        guard offset >= earliest, offset <= latest else { return false }
        let sameApp = (banner.bundleIdentifier != nil && banner.bundleIdentifier == record.bundleIdentifier)
            || (record.appKey != nil && banner.appKey == record.appKey)
        return sameApp && sameText(banner, record)
    }

    /// No title or body that differs, and at least one that agrees. Titles alone
    /// would not do: a chat's messages share the sender's name. A banner may cut
    /// a long body short, so one body may begin the other.
    private static func sameText(_ banner: Entry, _ record: Entry) -> Bool {
        var agrees = false
        if let title = record.title, let bannerTitle = banner.title {
            guard title == bannerTitle else { return false }
            agrees = true
        }
        if let body = record.body, let bannerBody = banner.body {
            guard body.hasPrefix(bannerBody) || bannerBody.hasPrefix(body) else { return false }
            agrees = true
        }
        return agrees
    }

    private mutating func prune(now: Date) {
        entries.removeAll { now.timeIntervalSince($0.date) > Self.window }
        shownRecords.removeAll { now.timeIntervalSince($0.date) > Self.window }
    }
}

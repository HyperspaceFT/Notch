import Foundation
import SQLite3
import Testing
@testable import NotificationsFeature

struct NotificationDatabaseTests {
    let delivered = Date(timeIntervalSinceReferenceDate: 814_721_212)

    /// A record's `data` as usernoted writes it: a binary property list.
    static func recordData(title: String?, subtitle: String? = nil, body: String?, itsp: Int = 0) -> Data {
        var request: [String: Any] = ["dest": 15, "iden": UUID().uuidString]
        request["titl"] = title
        request["subt"] = subtitle
        request["body"] = body
        let plist: [String: Any] = ["app": "com.example.chat", "itsp": itsp, "req": request, "styl": 1]
        // A dictionary of property-list values always serializes.
        return try! PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
    }

    @Test func parseReadsTheTextAndTheFocusMark() {
        let data = Self.recordData(title: "Design Sync", subtitle: "Room 4", body: "In 10 minutes", itsp: 0)
        let record = NotificationDatabase.parse(recordID: 7, bundleIdentifier: "com.example.chat", delivered: delivered, data: data)
        #expect(record == DatabaseNotification(
            recordID: 7,
            bundleIdentifier: "com.example.chat",
            title: "Design Sync",
            subtitle: "Room 4",
            body: "In 10 minutes",
            delivered: delivered,
            isHeldBack: false
        ))
        let held = NotificationDatabase.parse(
            recordID: 8,
            bundleIdentifier: "com.example.chat",
            delivered: delivered,
            data: Self.recordData(title: "Alex", body: "Hi", itsp: 2)
        )
        #expect(held?.isHeldBack == true)
        #expect(held?.showsBanner == true)
    }

    @Test func anAppWithoutBannersIsMarked() {
        var request: [String: Any] = ["titl": "Update", "body": "Ready"]
        request["dest"] = 15
        let plist: [String: Any] = ["req": request, "itsp": 0, "styl": 0]
        let data = try! PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
        let record = NotificationDatabase.parse(recordID: 3, bundleIdentifier: "com.apple.appstore", delivered: delivered, data: data)
        #expect(record?.showsBanner == false)
    }

    @Test func parseDropsBlankTextAndRejectsOtherData() {
        let record = NotificationDatabase.parse(
            recordID: 1,
            bundleIdentifier: "com.example.chat",
            delivered: delivered,
            data: Self.recordData(title: "  ", body: "\n")
        )
        #expect(record?.title == nil)
        #expect(record?.body == nil)
        #expect(record?.hasContent == false)
        #expect(NotificationDatabase.parse(recordID: 2, bundleIdentifier: "x", delivered: delivered, data: Data("nope".utf8)) == nil)
    }

    @Test func recordsAreReadAfterTheCutoffOldestFirst() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "NotchDatabaseTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "db")

        var database: OpaquePointer?
        #expect(sqlite3_open(url.path, &database) == SQLITE_OK)
        sqlite3_exec(database, """
            CREATE TABLE app (app_id INTEGER PRIMARY KEY, identifier VARCHAR, badge INTEGER NULL);
            CREATE TABLE record (rec_id INTEGER PRIMARY KEY, app_id INTEGER, uuid BLOB, data BLOB, request_date REAL,
                request_last_date REAL, delivered_date REAL, presented Bool, style INTEGER, snooze_fire_date REAL);
            INSERT INTO app VALUES (1, 'com.example.chat', NULL);
            """, nil, nil, nil)
        let rows: [(id: Int64, offset: Double, title: String)] = [(12, 3, "Third"), (10, -5, "Old"), (11, 1, "First")]
        for row in rows {
            var statement: OpaquePointer?
            sqlite3_prepare_v2(database, "INSERT INTO record (rec_id, app_id, data, delivered_date) VALUES (?, 1, ?, ?)", -1, &statement, nil)
            let data = Self.recordData(title: row.title, body: "Body")
            sqlite3_bind_int64(statement, 1, row.id)
            _ = data.withUnsafeBytes { bytes in
                // SQLITE_TRANSIENT: SQLite copies the bytes before this returns.
                sqlite3_bind_blob(statement, 2, bytes.baseAddress, Int32(bytes.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            }
            sqlite3_bind_double(statement, 3, delivered.timeIntervalSinceReferenceDate + row.offset)
            #expect(sqlite3_step(statement) == SQLITE_DONE)
            sqlite3_finalize(statement)
        }
        sqlite3_close(database)

        let records = try NotificationDatabase.records(at: url, after: delivered)
        #expect(records.map(\.recordID) == [11, 12])
        #expect(records.map(\.title) == ["First", "Third"])
        #expect(records.allSatisfy { $0.bundleIdentifier == "com.example.chat" && $0.body == "Body" })
    }

    @Test func aMissingDatabaseCannotBeOpened() {
        let url = FileManager.default.temporaryDirectory.appending(path: "NotchMissing-\(UUID().uuidString)/db")
        #expect(throws: NotificationDatabase.ReadError.self) {
            try NotificationDatabase.records(at: url, after: delivered)
        }
        #expect(!NotificationDatabase.isReadable(at: url))
    }
}

struct RecentBannersTests {
    let now = Date(timeIntervalSinceReferenceDate: 1_000)

    func banner(
        app: String? = "Chat",
        bundleIdentifier: String? = "com.Example.Chat",
        title: String?,
        body: String?,
        at offset: TimeInterval = 0
    ) -> NotificationItem {
        NotificationItem(
            token: "t",
            appName: app,
            bundleIdentifier: bundleIdentifier,
            title: title,
            body: body,
            received: now.addingTimeInterval(offset)
        )
    }

    func record(_ title: String?, _ body: String?, bundleIdentifier: String = "com.example.chat", at offset: TimeInterval = -0.3) -> DatabaseNotification {
        DatabaseNotification(
            recordID: 1,
            bundleIdentifier: bundleIdentifier,
            title: title,
            body: body,
            delivered: now.addingTimeInterval(offset),
            isHeldBack: false
        )
    }

    @Test func aRecordClaimsItsBannerOnce() {
        var recent = RecentBanners()
        recent.add(banner(title: "Alex", body: "Lunch?"), now: now)
        let claimed1 = recent.claim(record("Alex", "Lunch?"), appName: "Chat", now: now.addingTimeInterval(5))
        #expect(claimed1)
        // The same text again is a second notification: no banner left for it.
        let claimed2 = recent.claim(record("Alex", "Lunch?"), appName: "Chat", now: now.addingTimeInterval(5))
        #expect(!claimed2)
    }

    @Test func aSendersOtherMessageIsNotItsBanner() {
        var recent = RecentBanners()
        recent.add(banner(title: "Alex", body: "Lunch?"), now: now)
        let claimed3 = recent.claim(record("Alex", "On my way"), appName: "Chat", now: now.addingTimeInterval(5))
        #expect(!claimed3)
        #expect(recent.entries.count == 1)
    }

    @Test func aBannerKnownOnlyByItsAppNameMatches() {
        var recent = RecentBanners()
        recent.add(banner(app: "Chat", bundleIdentifier: nil, title: nil, body: "Long message that the banner cut"), now: now)
        let full = record(nil, "Long message that the banner cut short at the end")
        let claimed4 = recent.claim(full, appName: "chat", now: now.addingTimeInterval(5))
        #expect(claimed4)
    }

    @Test func otherAppsAndOtherTimesDoNotMatch() {
        var recent = RecentBanners()
        recent.add(banner(title: "Alex", body: "Hi"), now: now)
        let claimed5 = recent.claim(record("Alex", "Hi", bundleIdentifier: "com.example.mail"), appName: "Mail", now: now)
        #expect(!claimed5)
        let claimed6 = recent.claim(record("Alex", "Hi", at: -60), appName: "Chat", now: now)
        #expect(!claimed6)
        let claimed7 = recent.claim(record("Alex", "Hi"), appName: "Chat", now: now)
        #expect(claimed7)
    }

    @Test func aBannerHeldBackPastItsShownRecordIsDropped() {
        var recent = RecentBanners()
        let late = record("Alex", "Lunch?", at: -8)
        recent.addShown(late, appName: "Chat", now: now)
        let claimed = recent.claimShown(banner(title: "Alex", body: "Lunch?"), now: now)
        #expect(claimed)
        #expect(recent.shownRecords.isEmpty)
        // Another banner with other text is shown.
        let other = recent.claimShown(banner(title: "Alex", body: "On my way"), now: now)
        #expect(!other)
    }

    @Test func oldBannersAreForgotten() {
        var recent = RecentBanners()
        recent.add(banner(title: "Alex", body: "Hi"), now: now)
        let claimed8 = recent.claim(record("Alex", "Hi"), appName: "Chat", now: now.addingTimeInterval(RecentBanners.window + 1))
        #expect(!claimed8)
        #expect(recent.entries.isEmpty)
    }
}

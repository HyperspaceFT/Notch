import Foundation
import Testing
@testable import NotificationsFeature

private func item(
    _ id: String,
    token: String? = nil,
    title: String? = nil,
    app: String? = "Messages",
    at seconds: TimeInterval = 0
) -> NotificationItem {
    NotificationItem(
        id: id,
        token: token ?? "token-\(id)",
        appName: app,
        title: title ?? "Title \(id)",
        received: Date(timeIntervalSinceReferenceDate: seconds)
    )
}

@MainActor
struct NotificationInboxTests {
    @Test func newestComesFirst() {
        let inbox = NotificationInbox()
        inbox.insert(item("a"))
        inbox.insert(item("b"))
        inbox.insert(item("c"))
        #expect(inbox.items.map(\.id) == ["c", "b", "a"])
    }

    @Test func sameContentWithinTheWindowIsIgnored() {
        let inbox = NotificationInbox()
        #expect(NotificationInbox.dedupeWindow == 10)
        #expect(inbox.insert(item("a", token: "t1", title: "Hi", at: 0)))
        // Rebuilt by NotificationCenter under a new token, with the same text.
        #expect(!inbox.insert(item("b", token: "ax-2", title: "Hi", at: 10)))
        #expect(inbox.items.map(\.id) == ["a"])
    }

    @Test func sameTokenWithDifferentContentListsBoth() {
        let inbox = NotificationInbox()
        #expect(inbox.insert(item("a", token: "stack-chat", title: "First", at: 0)))
        #expect(inbox.insert(item("b", token: "stack-chat", title: "Second", at: 1)))
        #expect(inbox.items.map(\.id) == ["b", "a"])
        #expect(inbox.items.map(\.token) == ["stack-chat", "stack-chat"])
    }

    @Test func sameContentAfterTheWindowIsListedAgain() {
        let inbox = NotificationInbox()
        #expect(inbox.insert(item("a", token: "t", title: "Hi", at: 0)))
        #expect(inbox.insert(item("b", token: "t", title: "Hi", at: 10.5)))
        #expect(inbox.items.map(\.id) == ["b", "a"])
    }

    @Test func eachArrivalGetsItsOwnID() {
        let first = NotificationItem(token: "t", received: .now)
        let second = NotificationItem(token: "t", received: .now)
        #expect(first.id != second.id)
    }

    @Test func capacityDropsTheOldest() {
        let inbox = NotificationInbox()
        for index in 0..<(NotificationInbox.capacity + 5) {
            inbox.insert(item("\(index)", token: "same", at: TimeInterval(index)))
        }
        #expect(NotificationInbox.capacity == 30)
        #expect(inbox.items.count == 30)
        #expect(inbox.items.first?.id == "34")
        #expect(inbox.items.last?.id == "5")
    }

    @Test func removeAndRemoveAll() {
        let inbox = NotificationInbox()
        inbox.insert(item("a"))
        inbox.insert(item("b"))
        inbox.remove(id: "a")
        #expect(inbox.items.map(\.id) == ["b"])
        inbox.remove(id: "missing")
        #expect(inbox.items.map(\.id) == ["b"])
        inbox.removeAll()
        #expect(inbox.items.isEmpty)
    }

    @Test func lateAppLookupFillsInMatchingItems() {
        let inbox = NotificationInbox()
        inbox.insert(item("a", app: "\u{200E}WeChat"))
        inbox.insert(item("b", app: "Mail"))
        let url = URL(filePath: "/Applications/WeChat.app")
        inbox.setApp(bundleIdentifier: "com.tencent.xinWeChat", url: url, forAppNamed: "wechat")
        #expect(inbox.item(id: "a")?.appURL == url)
        #expect(inbox.item(id: "a")?.bundleIdentifier == "com.tencent.xinWeChat")
        #expect(inbox.item(id: "b")?.appURL == nil)
    }

    @Test func summaryPutsTheTitleOverTheBody() {
        var notification = NotificationItem(id: "a", token: "a", title: "T", subtitle: "S", body: "B", received: .now)
        #expect(notification.summary.headline == "T")
        #expect(notification.summary.detail == "B")
        notification.body = nil
        #expect(notification.summary.detail == "S")
        notification.title = nil
        #expect(notification.summary.headline == "S")
        #expect(notification.summary.detail == nil)
    }
}

struct NotificationAppTests {
    @Test func webKitAndSafariProcessesAreSafari() {
        #expect(NotificationAppResolver.normalizedBundleIdentifier("com.apple.WebKit.WebContent") == "com.apple.Safari")
        #expect(NotificationAppResolver.normalizedBundleIdentifier("com.apple.Safari.SafeBrowsing") == "com.apple.Safari")
        #expect(NotificationAppResolver.normalizedBundleIdentifier("com.apple.Safari") == "com.apple.Safari")
    }

    @Test func helperComponentAndAfterAreDropped() {
        #expect(NotificationAppResolver.normalizedBundleIdentifier("com.google.Chrome.helper") == "com.google.Chrome")
        #expect(NotificationAppResolver.normalizedBundleIdentifier("com.google.Chrome.Helper.Renderer") == "com.google.Chrome")
        #expect(NotificationAppResolver.normalizedBundleIdentifier("com.tinyspeck.slackmacgap") == "com.tinyspeck.slackmacgap")
        // Only a whole component counts.
        #expect(NotificationAppResolver.normalizedBundleIdentifier("com.example.helperkit") == "com.example.helperkit")
    }

    @Test func namesCompareWithoutBidiControlsCaseAndSurroundingSpaces() {
        #expect(NotificationAppResolver.key(for: "\u{2068}Google Chrome\u{2069} ") == "google chrome")
        #expect(NotificationAppResolver.key(for: "微信") == "微信")
    }
}

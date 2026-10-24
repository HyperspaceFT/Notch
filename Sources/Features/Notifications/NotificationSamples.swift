import AppKit
import NotchKit

/// A notification the Debug pane shows, in the interface language, from an app
/// every Mac has, so its icon shows.
struct NotificationSample {
    var bundleIdentifier: String
    var title: String?
    var subtitle: String?
    var body: String?

    /// A one-line message.
    @MainActor static var short: NotificationSample {
        NotificationSample(
            bundleIdentifier: messages,
            title: localized(en: "Alex", zh: "小林"),
            body: localized(en: "On my way!", zh: "我在路上了！")
        )
    }

    /// A long title and body: cut short in the wings, whole in the detail.
    @MainActor static var long: NotificationSample {
        NotificationSample(
            bundleIdentifier: mail,
            title: localized(
                en: "Quarterly Planning Review: Agenda, Notes, and Follow-Up Items for Everyone",
                zh: "季度规划评审：议程、会议纪要以及每个人需要跟进的事项"
            ),
            subtitle: localized(en: "Jordan Lee", zh: "王小明"),
            body: localized(
                en: "Hi all, thanks for joining today. I've attached the slides and the notes we took. Please look through the open items before Friday and reply with anything I missed, so we can lock the plan early next week.",
                zh: "大家好，感谢今天参会。我附上了幻灯片和会议纪要。请在周五前看一下待办事项，如有遗漏请回复补充，以便我们下周初确定计划。"
            )
        )
    }

    /// Three notifications from different apps, shown one after another.
    @MainActor static var sequence: [NotificationSample] {
        [
            NotificationSample(
                bundleIdentifier: messages,
                title: localized(en: "Alex", zh: "小林"),
                body: localized(en: "Lunch at noon?", zh: "中午一起吃饭？")
            ),
            NotificationSample(
                bundleIdentifier: calendar,
                title: localized(en: "Design Sync", zh: "设计同步会"),
                body: localized(en: "In 10 minutes · Room 4", zh: "10 分钟后 · 4 号会议室")
            ),
            NotificationSample(
                bundleIdentifier: mail,
                title: localized(en: "Jordan Lee", zh: "王小明"),
                subtitle: localized(en: "Slides for tomorrow", zh: "明天的幻灯片"),
                body: localized(en: "Here's the latest version.", zh: "这是最新版本。")
            ),
        ]
    }

    /// The item a banner with this text would make, its app found by bundle
    /// identifier and named as the system names it, as a banner would.
    func item(received: Date) -> NotificationItem {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
        let appName = url.map { FileManager.default.displayName(atPath: $0.path) }.map { name in
            name.hasSuffix(".app") ? String(name.dropLast(4)) : name
        }
        return NotificationItem(
            token: "debug-sample",
            appName: appName,
            bundleIdentifier: bundleIdentifier,
            appURL: url,
            title: title,
            subtitle: subtitle,
            body: body,
            received: received
        )
    }

    private static let messages = "com.apple.MobileSMS"
    private static let mail = "com.apple.mail"
    private static let calendar = "com.apple.iCal"
}

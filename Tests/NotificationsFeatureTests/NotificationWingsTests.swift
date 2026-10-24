import Foundation
import Testing
@testable import NotificationsFeature

struct NotificationWingsTests {
    private func item(appName: String?, title: String?, body: String?) -> NotificationItem {
        NotificationItem(token: "t", appName: appName, title: title, body: body, received: Date())
    }

    @Test func aShortNotificationGetsNarrowWings() {
        let wings = NotificationWings.widths(for: item(appName: "Mail", title: "Alex", body: "On my way!"))
        #expect(wings.leading < NotificationWings.maximumWidth)
        #expect(wings.trailing < NotificationWings.maximumWidth)
        // Room for the icon and the name beside it.
        #expect(wings.leading > NotificationWings.iconSide + NotificationWings.iconSpacing)
    }

    @Test func eachWingFollowsItsOwnText() {
        let short = NotificationWings.widths(for: item(appName: "Mail", title: "Hi", body: nil))
        let longerName = NotificationWings.widths(for: item(appName: "Messages", title: "Hi", body: nil))
        let longerText = NotificationWings.widths(for: item(appName: "Mail", title: "Hi", body: "See you at the station"))
        #expect(longerName.leading > short.leading)
        #expect(longerName.trailing == short.trailing)
        #expect(longerText.trailing > short.trailing)
        #expect(longerText.leading == short.leading)
    }

    @Test func longTextStopsAtTheMaximum() {
        let wings = NotificationWings.widths(for: item(
            appName: "A Very Long Application Name Indeed",
            title: "Quarterly Planning Review: Agenda, Notes, and Follow-Up Items",
            body: "Hi all, thanks for joining today."
        ))
        #expect(wings.leading == NotificationWings.maximumWidth)
        #expect(wings.trailing == NotificationWings.maximumWidth)
    }

    @Test func withoutTextTheWingsKeepTheirLeast() {
        let wings = NotificationWings.widths(for: item(appName: nil, title: nil, body: "OK"))
        #expect(wings.trailing == NotificationWings.minimumTrailingWidth)
        // The icon alone, with both clearances.
        #expect(wings.leading == 12 + NotificationWings.iconSide + 6)
    }
}

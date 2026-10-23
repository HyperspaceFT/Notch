import NotchKit
import SwiftUI

/// Offers a Home module with the coming days' events from the Calendar app
/// (through EventKit) and from subscribed iCalendar feeds, such as a Google
/// Calendar or Outlook secret address. Has no tab of its own.
@MainActor
public final class CalendarFeature: NotchFeature {
    public let id = "calendar"
    public var title: String { localized(en: "Calendar", zh: "日历") }
    public let symbol = "calendar"

    public init() {}

    public func activate(context: any NotchContext) {
        LocalCalendars.shared.start()
    }

    public func deactivate() {
        LocalCalendars.shared.stop()
        SubscriptionFeeds.shared.stop()
    }

    public func makeHomeModules() -> [NotchHomeModule] {
        [
            NotchHomeModule(
                id: "calendar",
                title: { localized(en: "Calendar", zh: "日历") },
                symbol: "calendar",
                detail: {
                    localized(
                        en: "Events from the Calendar app and subscribed calendars.",
                        zh: "日程来自「日历」App 和订阅的日历。"
                    )
                },
                sizing: .resizable(minimum: .fraction(1.0 / 3), maximum: nil),
                content: { size in
                    AnyView(CalendarModuleView(
                        settings: .shared,
                        local: .shared,
                        feeds: .shared,
                        size: size
                    ))
                }
            ),
        ]
    }
}

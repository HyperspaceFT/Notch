import NotchKit
import SwiftUI

/// Offers a Home module with the Reminders app's incomplete reminders
/// (`RemindersStore.shared`), where reminders can be added, completed, and
/// deleted. Has no tab of its own.
@MainActor
public final class RemindersFeature: NotchFeature {
    public let id = "reminders"
    public var title: String { localized(en: "Reminders", zh: "提醒事项") }
    public let symbol = "checklist"

    /// The narrowest the Home module may be. With the clock (134 pt), the weather
    /// and the calendar (a third each) in a four-module row of 812 pt, 120 pt are
    /// left; a wider minimum would keep Reminders out of that row.
    static let moduleMinimumWidth: CGFloat = 100

    public init() {}

    public func activate(context: any NotchContext) {
        RemindersStore.shared.start()
    }

    public func deactivate() {
        RemindersStore.shared.stop()
    }

    public func makeHomeModules() -> [NotchHomeModule] {
        // Outside `content`, which runs again for every size Home gives the module.
        let state = RemindersCardState()
        return [
            NotchHomeModule(
                id: "reminders",
                title: { localized(en: "Reminders", zh: "提醒事项") },
                symbol: "checklist",
                detail: {
                    localized(en: "Reminders from the Reminders app.", zh: "来自「提醒事项」App 的待办。")
                },
                sizing: .resizable(minimum: .points(Self.moduleMinimumWidth), maximum: nil),
                content: { size in
                    AnyView(RemindersView(store: .shared, state: state, size: size))
                }
            ),
        ]
    }
}

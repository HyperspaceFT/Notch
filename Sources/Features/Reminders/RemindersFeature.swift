import NotchKit
import SwiftUI

/// The Reminders app's incomplete reminders in the island: a tab right of the
/// notch and a Home module, both showing `RemindersStore.shared`, where
/// reminders can be added, completed, and deleted.
@MainActor
public final class RemindersFeature: NotchFeature {
    public let id = "reminders"
    public var title: String { localized(en: "Reminders", zh: "提醒事项") }
    public let symbol = "checklist"
    public let tabPlacement = NotchTabPlacement.trailing

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

    /// Not tied to the Home module with `notchTabMorph`, unlike Notes: growing the
    /// card from Home into the tab made its text wrap and unwrap on the way.
    public func makeExpandedView() -> AnyView? {
        // Apart from the Home module's: each card scrolls to the reminders it added.
        let state = RemindersCardState()
        return AnyView(
            GeometryReader { proxy in
                RemindersView(store: .shared, state: state, size: proxy.size)
            }
        )
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

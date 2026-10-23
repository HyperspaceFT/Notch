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

    /// Ties the Home module to the tab: switching between Home and Reminders
    /// grows the module's card into the tab's and back (`notchTabMorph`).
    static let morphID = "reminders"

    public init() {}

    public func activate(context: any NotchContext) {
        RemindersStore.shared.start()
    }

    public func deactivate() {
        RemindersStore.shared.stop()
    }

    public func makeExpandedView() -> AnyView? {
        let state = RemindersCardState()
        return AnyView(
            GeometryReader { proxy in
                RemindersView(store: .shared, state: state, size: proxy.size)
            }
            .notchTabMorph(Self.morphID)
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
                content: { _ in
                    // Sized by what it is offered rather than by Home's size: while the
                    // Reminders tab shows, the card takes the tab card's frame.
                    AnyView(
                        GeometryReader { proxy in
                            RemindersView(store: .shared, state: state, size: proxy.size)
                        }
                        .notchTabMorph(Self.morphID)
                    )
                }
            ),
        ]
    }
}

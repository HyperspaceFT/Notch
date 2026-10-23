import NotchKit
import SwiftUI

/// Notes written in the island: a tab right of the notch and a Home module,
/// both showing the same notes (`NotesStore.shared`), kept in a file on this Mac.
@MainActor
public final class NotesFeature: NotchFeature {
    public let id = "notes"
    public var title: String { localized(en: "Notes", zh: "笔记") }
    public let symbol = "note.text"
    public let tabPlacement = NotchTabPlacement.trailing

    /// The narrowest the Home module may be. With the clock (134 pt), the weather
    /// and the calendar (a third each) in a four-module row of 812 pt, 120 pt are
    /// left; a wider minimum would keep Notes out of that row.
    static let moduleMinimumWidth: CGFloat = 100

    public init() {}

    public func deactivate() {
        NotesStore.shared.flush()
    }

    /// Ties the Home module to the tab: switching between Home and Notes grows
    /// the module's card into the tab's and back (`notchTabMorph`).
    static let morphID = "notes"

    public func makeExpandedView() -> AnyView? {
        let focus = NotesEditorFocus()
        return AnyView(
            GeometryReader { proxy in
                NotesView(store: .shared, focus: focus, size: proxy.size)
            }
            .notchTabMorph(Self.morphID)
        )
    }

    public func makeHomeModules() -> [NotchHomeModule] {
        // Outside `content`, which runs again for every size Home gives the module.
        let focus = NotesEditorFocus()
        return [
            NotchHomeModule(
                id: "notes",
                title: { localized(en: "Notes", zh: "笔记") },
                symbol: "note.text",
                detail: {
                    localized(
                        en: "Notes you write in the island, kept on this Mac.",
                        zh: "在岛上写的笔记，保存在这台 Mac 上。"
                    )
                },
                sizing: .resizable(minimum: .points(Self.moduleMinimumWidth), maximum: nil),
                content: { _ in
                    // Sized by what it is offered rather than by Home's size: while the
                    // Notes tab shows, the card takes the tab card's frame.
                    AnyView(
                        GeometryReader { proxy in
                            NotesView(store: .shared, focus: focus, size: proxy.size)
                        }
                        .notchTabMorph(Self.morphID)
                    )
                }
            ),
        ]
    }
}

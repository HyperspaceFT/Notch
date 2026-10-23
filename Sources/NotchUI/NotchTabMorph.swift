import SwiftUI

/// Where a tab's content sits among the expanded panel's tabs, for
/// `View.notchTabMorph(_:)`. The shell sets it on each tab's content.
public struct NotchTabMorph {
    /// Shared by every tab's content.
    public let namespace: Namespace.ID
    /// The tab this content belongs to.
    public let tabID: String
    /// The tab the panel shows.
    public let shownTabID: String?

    public init(namespace: Namespace.ID, tabID: String, shownTabID: String?) {
        self.namespace = namespace
        self.tabID = tabID
        self.shownTabID = shownTabID
    }
}

private struct NotchTabMorphKey: EnvironmentKey {
    static var defaultValue: NotchTabMorph? { nil }
}

extension EnvironmentValues {
    public var notchTabMorph: NotchTabMorph? {
        get { self[NotchTabMorphKey.self] }
        set { self[NotchTabMorphKey.self] = newValue }
    }
}

extension View {
    /// Makes this view one card with the views given the same `id` in other tabs,
    /// such as a Home module and its feature's own tab: on a switch between their
    /// tabs, the card grows or shrinks from the one leaving into the one arriving
    /// while the tabs cross-fade. The view in the shown tab keeps its own frame
    /// and the others take it, so they are laid out at its size and should size
    /// their content from what they are offered. Without a partner in the shown
    /// tab, or outside the expanded panel, it changes nothing.
    public func notchTabMorph(_ id: String) -> some View {
        modifier(NotchTabMorphEffect(id: id))
    }
}

private struct NotchTabMorphEffect: ViewModifier {
    let id: String
    @Environment(\.notchTabMorph) private var morph

    func body(content: Content) -> some View {
        if let morph {
            content.matchedGeometryEffect(id: id, in: morph.namespace, isSource: morph.tabID == morph.shownTabID)
        } else {
            content
        }
    }
}

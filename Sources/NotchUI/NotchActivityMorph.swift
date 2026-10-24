import SwiftUI

/// Where an activity's wings and its feature's tab stand, for
/// `View.notchMorphSlot(_:role:)` and `View.notchMorphHero(_:)`: which slot the
/// heroes sit in, and whether they show at all. Pure, so the rule is testable.
public struct NotchMorphState: Equatable, Sendable {
    /// Where a slot sits.
    public enum Role: Sendable {
        /// In an activity's wings, beside the notch.
        case wing
        /// In the feature's tab of the expanded panel.
        case tab
    }

    public var isExpanded: Bool
    /// The feature whose current activity has `NotchActivity.morphsIntoTab`, so
    /// its wings carry heroes; `nil` when the current activity has not, or there
    /// is none. Set in every state, not only while expanded, so the tab keeps its
    /// slots empty while the heroes fly back to the wings.
    public var wingFeatureID: String?
    /// The tab the expanded panel shows; also set while it is closed.
    public var shownTabID: String?

    public init(isExpanded: Bool, wingFeatureID: String?, shownTabID: String?) {
        self.isExpanded = isExpanded
        self.wingFeatureID = wingFeatureID
        self.shownTabID = shownTabID
    }

    /// Whether a slot is where its hero goes: a wing slot while the island is not
    /// expanded; the tab slot of `tabID` while expanded, when its feature's wings
    /// carry the heroes. At most one slot per id is. Also while that tab is
    /// hidden (it stays mounted): the heroes then move with it as it slides away
    /// or back, fading per `showsHeroes`, instead of falling back to the wings
    /// beside the notch, among the tab buttons.
    public func isSource(_ role: Role, tabID: String?) -> Bool {
        switch role {
        case .wing:
            !isExpanded
        case .tab:
            isExpanded && tabID != nil && tabID == wingFeatureID
        }
    }

    /// Whether the heroes have a slot to sit in. Expanded on another tab they
    /// have none, and fade out where they are.
    public var showsHeroes: Bool {
        !isExpanded || (wingFeatureID != nil && wingFeatureID == shownTabID)
    }

    /// Whether the tab `tabID` leaves its slots empty, because the heroes in its
    /// feature's wings stand in for what they would draw.
    public func heroesStandIn(forTab tabID: String?) -> Bool {
        tabID != nil && tabID == wingFeatureID
    }
}

/// Lets views in an activity's wings fly into their places in the feature's tab
/// as the island opens, and back as it closes. The shell sets it on the wings
/// and on every tab's content.
///
/// A feature marks each place with `notchMorphSlot(_:role:)`, once in the wings
/// and once in its tab, and draws the one visible copy, the hero, in the wings
/// with `notchMorphHero(_:)`. The shell keeps the wings over the open panel only
/// for an activity with `NotchActivity.morphsIntoTab`.
public struct NotchActivityMorph {
    /// Shared by the wings and every tab's content.
    public let namespace: Namespace.ID
    public let state: NotchMorphState

    public init(namespace: Namespace.ID, state: NotchMorphState) {
        self.namespace = namespace
        self.state = state
    }
}

private struct NotchActivityMorphKey: EnvironmentKey {
    static var defaultValue: NotchActivityMorph? { nil }
}

extension EnvironmentValues {
    public var notchActivityMorph: NotchActivityMorph? {
        get { self[NotchActivityMorphKey.self] }
        set { self[NotchActivityMorphKey.self] = newValue }
    }
}

extension View {
    /// Marks the place of the hero `id` (namespaced by feature, e.g.
    /// `"now-playing.cover"`): this view's frame is where the hero goes while the
    /// slot is the source (`NotchMorphState.isSource`). A `.wing` slot is only
    /// reserved space, never drawn or hit. A `.tab` slot draws this view itself
    /// while no hero stands in for it, e.g. while another activity is current;
    /// otherwise it is left empty. The hover shift of the wings must move the
    /// slot by layout (padding, frames), not `offset`, so the hero sees it.
    public func notchMorphSlot(_ id: String, role: NotchMorphState.Role) -> some View {
        modifier(NotchMorphSlotEffect(id: id, role: role))
    }

    /// Makes this view the hero `id`: it takes the frame of whichever slot with
    /// that id is the source, so it should draw at whatever size it is offered,
    /// and moves between slots with the transaction that changes the source. It
    /// fades out while no slot is the source. Place it in the wings.
    public func notchMorphHero(_ id: String) -> some View {
        modifier(NotchMorphHeroEffect(id: id))
    }
}

private struct NotchMorphSlotEffect: ViewModifier {
    let id: String
    let role: NotchMorphState.Role
    @Environment(\.notchActivityMorph) private var morph
    @Environment(\.notchTabMorph) private var tabMorph

    func body(content: Content) -> some View {
        let tabID = tabMorph?.tabID
        let drawsContent = role == .tab && !(morph?.state.heroesStandIn(forTab: tabID) ?? false)
        content
            .opacity(drawsContent ? 1 : 0)
            .allowsHitTesting(drawsContent)
            .accessibilityHidden(!drawsContent)
            .background {
                // A stand-in rather than the content itself: a slot that is not
                // the source is moved onto the one that is, which must not move
                // what the tab draws.
                if let morph {
                    Color.clear
                        .matchedGeometryEffect(
                            id: id,
                            in: morph.namespace,
                            properties: .frame,
                            isSource: morph.state.isSource(role, tabID: tabID)
                        )
                        .allowsHitTesting(false)
                }
            }
    }
}

private struct NotchMorphHeroEffect: ViewModifier {
    let id: String
    @Environment(\.notchActivityMorph) private var morph

    func body(content: Content) -> some View {
        if let morph {
            let isShown = morph.state.showsHeroes
            content
                .matchedGeometryEffect(id: id, in: morph.namespace, properties: .frame, isSource: false)
                .opacity(isShown ? 1 : 0)
                .allowsHitTesting(isShown)
                .accessibilityHidden(!isShown)
        } else {
            content
        }
    }
}

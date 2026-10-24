import Foundation
import SwiftUI

/// A short-lived or persistent status shown while the island is collapsed,
/// rendered as two "wings" to the left and right of the hardware notch (and
/// kept over the open panel for views that fly into the tab, see `morphsIntoTab`),
/// or, with a `rim`, as a band of light around the slightly grown island.
///
/// Only the highest-priority activity is visible at a time; among equal
/// priorities the most recently presented one wins.
public struct NotchActivity: Identifiable {
    public struct Priority: Comparable, Hashable, Sendable {
        public var rawValue: Int

        public init(_ rawValue: Int) {
            self.rawValue = rawValue
        }

        public static let low = Priority(0)
        public static let normal = Priority(50)
        public static let high = Priority(100)

        public static func < (lhs: Priority, rhs: Priority) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    public let id: String
    /// Owning feature. Filled in by the shell's context when presented.
    public var featureID: String
    public var priority: Priority
    /// Seconds until the activity disappears on its own; `nil` keeps it until dismissed.
    public var duration: TimeInterval?
    /// Width of each wing; `nil` uses the shell's standard width
    /// (`NotchTheme.activityWingWidth`). Narrower content asks for less, so the
    /// island grows only as far as it needs.
    public var wingWidth: CGFloat?
    /// Width of the left wing when its content needs less (or more) room than the
    /// right's; `nil` (the default) makes it as wide as the right wing. With
    /// unequal wings the island sits off the notch's center, so the notch stays
    /// between them.
    public var leadingWingWidth: CGFloat?
    /// Keeps the wings on the island while it is expanded and this activity is
    /// current, so views in them can fly into their places in the feature's tab
    /// and back (`notchMorphHero` in NotchUI). While expanded the wings must show
    /// nothing but their heroes: the shell draws them over the open panel, where
    /// anything else would cover the tab buttons beside the notch. `false` (the
    /// default) removes the wings while expanded.
    public var morphsIntoTab: Bool
    /// Keeps the activity for its whole `duration` on the collapsed island:
    /// while the island is expanded (on the tabs or a detail), where its wings
    /// do not show, the duration does not run, and when the island collapses
    /// it starts over in full from that moment. For something the user should
    /// see, such as an event reminder. `false` (the default) lets the duration
    /// run while expanded; without a duration it changes nothing.
    public var holdsWhileExpanded: Bool
    /// Content left of the hardware notch.
    public var leading: AnyView
    /// Content right of the hardware notch.
    public var trailing: AnyView
    /// Draws the activity as a band along the island's edge instead of wings
    /// (see `NotchActivityRim`); `nil` (the default) shows the wings.
    public var rim: NotchActivityRim?

    public init<Leading: View, Trailing: View>(
        id: String,
        featureID: String = "",
        priority: Priority = .normal,
        duration: TimeInterval? = nil,
        wingWidth: CGFloat? = nil,
        leadingWingWidth: CGFloat? = nil,
        morphsIntoTab: Bool = false,
        holdsWhileExpanded: Bool = false,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.id = id
        self.featureID = featureID
        self.priority = priority
        self.duration = duration
        self.wingWidth = wingWidth
        self.leadingWingWidth = leadingWingWidth
        self.morphsIntoTab = morphsIntoTab
        self.holdsWhileExpanded = holdsWhileExpanded
        self.leading = AnyView(leading())
        self.trailing = AnyView(trailing())
        self.rim = nil
    }

    /// An activity shown as a band of light around the island rather than wings.
    public init(
        id: String,
        featureID: String = "",
        priority: Priority = .normal,
        duration: TimeInterval? = nil,
        holdsWhileExpanded: Bool = false,
        rim: NotchActivityRim
    ) {
        self.id = id
        self.featureID = featureID
        self.priority = priority
        self.duration = duration
        self.wingWidth = nil
        self.leadingWingWidth = nil
        self.morphsIntoTab = false
        self.holdsWhileExpanded = holdsWhileExpanded
        self.leading = AnyView(EmptyView())
        self.trailing = AnyView(EmptyView())
        self.rim = rim
    }
}

/// An activity drawn as a band of light just inside the island's edge, from the
/// left side down around the bottom and up the right side, instead of wings. The
/// island grows only by a thin ring around the notch to hold it. The band shows
/// a share of that arc, given by `fraction` and retracting from its left end
/// toward its right end, so it can show something running down, such as time left.
/// It takes no clicks; a click on the island still expands it.
public struct NotchActivityRim {
    /// The band's color.
    public var color: Color
    /// The share of the arc the band covers at a moment, 0…1. Read about once a
    /// second while the band shows, and whenever observable state it reads changes.
    public var fraction: @MainActor (Date) -> Double
    /// Whether the band is drawn faintly, e.g. while what it shows is paused.
    public var isDimmed: @MainActor () -> Bool

    public init(
        color: Color,
        fraction: @escaping @MainActor (Date) -> Double,
        isDimmed: @escaping @MainActor () -> Bool = { false }
    ) {
        self.color = color
        self.fraction = fraction
        self.isDimmed = isDimmed
    }
}

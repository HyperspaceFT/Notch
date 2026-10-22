import Foundation
import SwiftUI

/// A short-lived or persistent status shown while the island is collapsed,
/// rendered as two "wings" to the left and right of the hardware notch.
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
    /// Content left of the hardware notch.
    public var leading: AnyView
    /// Content right of the hardware notch.
    public var trailing: AnyView

    public init<Leading: View, Trailing: View>(
        id: String,
        featureID: String = "",
        priority: Priority = .normal,
        duration: TimeInterval? = nil,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.id = id
        self.featureID = featureID
        self.priority = priority
        self.duration = duration
        self.leading = AnyView(leading())
        self.trailing = AnyView(trailing())
    }
}

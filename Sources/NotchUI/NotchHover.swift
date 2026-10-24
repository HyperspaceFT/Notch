import SwiftUI

private struct NotchIsHoveredKey: EnvironmentKey {
    static var defaultValue: Bool { false }
}

extension EnvironmentValues {
    /// Whether the pointer rests on the activity island, which then grows by
    /// `NotchTheme.hoverGrowth`. Set for an activity's wings, so their content can
    /// move with the outline (the change runs inside the hover animation); `false`
    /// everywhere else.
    public var notchIsHovered: Bool {
        get { self[NotchIsHoveredKey.self] }
        set { self[NotchIsHoveredKey.self] = newValue }
    }
}

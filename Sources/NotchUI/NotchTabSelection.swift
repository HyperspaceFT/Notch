import SwiftUI

private struct NotchTabIsSelectedKey: EnvironmentKey {
    static var defaultValue: Bool { false }
}

extension EnvironmentValues {
    /// Whether the tab whose button draws this view is the selected one. The shell
    /// sets it on a tab button's custom icon (`NotchFeature.makeTabIcon`), so the icon
    /// can take the colors the symbol buttons take: primary text when selected,
    /// secondary otherwise; `false` everywhere else.
    public var notchTabIsSelected: Bool {
        get { self[NotchTabIsSelectedKey.self] }
        set { self[NotchTabIsSelectedKey.self] = newValue }
    }
}

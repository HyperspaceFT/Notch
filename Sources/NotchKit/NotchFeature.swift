import SwiftUI

/// A self-contained module that lives inside the notch.
///
/// A feature may contribute five things:
/// - live activities (via `NotchContext.present`) shown as wings beside the
///   hardware notch while the island is collapsed,
/// - a tab in the expanded panel (via `makeExpandedView`),
/// - a detail the expanded island opens on alone, without the tabs (via
///   `NotchContext.requestExpand(detail:)`),
/// - modules for the Home tab (via `makeHomeModules`), and
/// - entries in the island's right-click menu (via `menuItems`).
///
/// Features are created once in `FeatureCatalog`, activated when the shell
/// starts, and deactivated when it stops. They must not touch windows directly.
@MainActor
public protocol NotchFeature: AnyObject {
    /// Stable identifier, e.g. "battery". Used for activity ownership and tab selection.
    var id: String { get }
    /// Display name shown to the user, e.g. `localized(en: "Battery", zh: "电池")`.
    /// Read while the panel draws, so it follows the interface language.
    var title: String { get }
    /// SF Symbol name used for the feature's tab in the expanded panel. Read while
    /// the panel draws, so it may follow observable state (e.g. the charge level).
    var symbol: String { get }
    /// Whether the feature's tab shows in the expanded panel. Read while the panel
    /// draws, so it may follow observable state (e.g. a device being connected).
    var isTabAvailable: Bool { get }
    /// Which side of the hardware notch the feature's tab button sits on.
    var tabPlacement: NotchTabPlacement { get }
    /// Whether content (such as files) dragged onto the notch opens the island on
    /// this feature's tab. For features whose tab takes drops; the first one wins.
    var opensOnDrag: Bool { get }
    /// Body width of the expanded island while this feature's tab is selected.
    /// Read while the panel draws, so it may follow observable state (e.g. how
    /// wide the modules Home shows are). `nil` uses the standard width; the shell
    /// keeps it between the standard and the maximum width (see `NotchTheme`).
    var expandedWidth: CGFloat? { get }
    /// Entries in the island's right-click menu, above Settings…; empty by default.
    /// Read while the island draws, so they may follow observable state (e.g. a
    /// running timer) and the interface language.
    var menuItems: [NotchMenuItem] { get }

    /// Called once when the shell starts. Keep the context to present activities later.
    func activate(context: any NotchContext)
    /// Called when the shell stops. Release observers, timers, and system resources here.
    func deactivate()
    /// Content of this feature's tab in the expanded panel; `nil` means no tab.
    /// Called once after activation; the returned view should observe its own state.
    func makeExpandedView() -> AnyView?
    /// Modules this feature offers for the Home tab (see `NotchHomeModule`); empty
    /// by default. Home asks once, after every feature is activated; the modules'
    /// views should observe their own state.
    func makeHomeModules() -> [NotchHomeModule]
}

/// Where a feature's tab button sits in the expanded panel's header.
public enum NotchTabPlacement: Sendable {
    /// Left of the hardware notch.
    case leading
    /// Right of the hardware notch.
    case trailing
}

extension NotchFeature {
    public var tabPlacement: NotchTabPlacement { .leading }
    public var opensOnDrag: Bool { false }
    public var isTabAvailable: Bool { true }
    public var expandedWidth: CGFloat? { nil }
    public var menuItems: [NotchMenuItem] { [] }
    public func activate(context: any NotchContext) {}
    public func deactivate() {}
    public func makeExpandedView() -> AnyView? { nil }
    public func makeHomeModules() -> [NotchHomeModule] { [] }
}

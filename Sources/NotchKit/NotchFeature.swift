import SwiftUI

/// A self-contained module that lives inside the notch.
///
/// A feature may contribute two things:
/// - live activities (via `NotchContext.present`) shown as wings beside the
///   hardware notch while the island is collapsed, and
/// - a tab in the expanded panel (via `makeExpandedView`).
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
    /// Which side of the hardware notch the feature's tab button sits on.
    var tabPlacement: NotchTabPlacement { get }
    /// Whether content (such as files) dragged onto the notch opens the island on
    /// this feature's tab. For features whose tab takes drops; the first one wins.
    var opensOnDrag: Bool { get }

    /// Called once when the shell starts. Keep the context to present activities later.
    func activate(context: any NotchContext)
    /// Called when the shell stops. Release observers, timers, and system resources here.
    func deactivate()
    /// Content of this feature's tab in the expanded panel; `nil` means no tab.
    /// Called once after activation; the returned view should observe its own state.
    func makeExpandedView() -> AnyView?
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
    public func activate(context: any NotchContext) {}
    public func deactivate() {}
    public func makeExpandedView() -> AnyView? { nil }
}

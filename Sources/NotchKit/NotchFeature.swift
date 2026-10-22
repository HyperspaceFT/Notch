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
    /// Display name shown to the user (may be localized, e.g. "电池").
    var title: String { get }
    /// SF Symbol name used for the feature's tab in the expanded panel.
    var symbol: String { get }

    /// Called once when the shell starts. Keep the context to present activities later.
    func activate(context: any NotchContext)
    /// Called when the shell stops. Release observers, timers, and system resources here.
    func deactivate()
    /// Content of this feature's tab in the expanded panel; `nil` means no tab.
    /// Called once after activation; the returned view should observe its own state.
    func makeExpandedView() -> AnyView?
}

extension NotchFeature {
    public func activate(context: any NotchContext) {}
    public func deactivate() {}
    public func makeExpandedView() -> AnyView? { nil }
}

import SwiftUI

/// The channel through which a feature talks to the shell.
///
/// Each feature receives its own context; activities presented through it are
/// automatically attributed to that feature.
@MainActor
public protocol NotchContext: AnyObject {
    /// Shows (or replaces, when the id already exists) a live activity.
    func present(_ activity: NotchActivity)
    /// Removes a live activity previously presented by this feature.
    func dismiss(activityID: String)
    /// Opens the expanded panel on this feature's tab, if it has one.
    /// The panel collapses again once the pointer moves away from it.
    func requestExpand()
    /// Opens the expanded island on `detail` alone, without the panel's tab
    /// buttons: a view of one thing that has no tab of its own (e.g. a single
    /// notification). While open, another call replaces what it shows. It
    /// collapses like the panel once the pointer moves away, and the next
    /// ordinary expansion shows the tabs again.
    func requestExpand(detail: AnyView)
}

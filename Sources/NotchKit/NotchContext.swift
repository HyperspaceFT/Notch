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
}

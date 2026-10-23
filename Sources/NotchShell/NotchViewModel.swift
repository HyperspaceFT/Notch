import Foundation
import NotchKit
import NotchUI
import Observation
import SwiftUI

/// Single source of truth for what the island shows.
///
/// State machine:
/// - `.collapsed`: island exactly covers the hardware notch.
/// - `.activity`: the top-priority activity is shown as wings beside the notch.
/// - `.expanded`: the full panel with feature tabs (a click on the hovered
///   island, content dragged onto the notch, or `requestExpand`). Only tabs
///   whose `isAvailable` is true show (`visibleTabs`).
///
/// Expansion always wins over activities; activities keep their queue and
/// timers while expanded and reappear on collapse.
///
/// `isHovered` sits on top of `.collapsed` and `.activity`: the island grows by
/// `NotchTheme.hoverGrowth` and takes the clicks that expand it.
@MainActor
@Observable
final class NotchViewModel {
    enum State: String, Equatable, Sendable {
        case collapsed
        case activity
        case expanded
    }

    struct Tab: Identifiable {
        let id: String
        /// Read while the header draws, so it can follow the interface language.
        let title: @MainActor () -> String
        /// Read while the header draws, so it can follow the feature's observable state.
        let symbol: @MainActor () -> String
        let placement: NotchTabPlacement
        let opensOnDrag: Bool
        /// Read while the panel draws, so the tab can hide while the feature has
        /// nothing to show (e.g. its device is disconnected).
        let isAvailable: @MainActor () -> Bool
        /// Body width of the expanded island while this tab is selected; `nil` for
        /// the standard width. Read while the panel draws, so it can follow the
        /// feature's observable state.
        let expandedWidth: @MainActor () -> CGFloat?
        let content: AnyView

        init(
            id: String,
            title: @escaping @MainActor () -> String,
            symbol: @escaping @MainActor () -> String,
            placement: NotchTabPlacement = .leading,
            opensOnDrag: Bool = false,
            isAvailable: @escaping @MainActor () -> Bool = { true },
            expandedWidth: @escaping @MainActor () -> CGFloat? = { nil },
            content: AnyView
        ) {
            self.id = id
            self.title = title
            self.symbol = symbol
            self.placement = placement
            self.opensOnDrag = opensOnDrag
            self.isAvailable = isAvailable
            self.expandedWidth = expandedWidth
            self.content = content
        }
    }

    private struct ActivityEntry {
        var activity: NotchActivity
        /// Monotonic insertion order; breaks priority ties in favour of the newest.
        var sequence: Int
        var expiresAt: Date?
    }

    private(set) var geometry: NotchGeometry
    private(set) var isExpanded = false
    /// The expanded panel's views are in the tree. Set on expanding and cleared
    /// `expandedContentLinger` after collapsing, so a collapse undone midway turns
    /// the same views around instead of bringing in new ones over the leaving ones.
    private(set) var isExpandedContentMounted = false
    /// The mounted expanded content has appeared, so it can drop from its raised
    /// pose: a view inserted already in place would have nothing to animate from.
    private(set) var hasExpandedContentAppeared = false
    /// The pointer rests on the collapsed or activity island. Always false while expanded.
    private(set) var isHovered = false
    private(set) var tabs: [Tab] = []
    var selectedTabID: String? {
        didSet {
            guard selectedTabID != oldValue else { return }
            onSelectedTabChange?()
        }
    }

    /// When false, the hover controller leaves the state alone (debug pinning).
    var isHoverEnabled = true

    /// How long the expanded content stays mounted after collapsing: long enough
    /// for `NotchTheme.collapseAnimation` (or `activityAnimation`, when an activity
    /// returns) to raise it out of sight.
    @ObservationIgnored var expandedContentLinger: Duration = .milliseconds(500)

    /// Invoked whenever `isInteractive` changes; the shell uses it to toggle mouse
    /// interception on the panel.
    @ObservationIgnored var onInteractivityChange: ((Bool) -> Void)?

    /// Invoked whenever `selectedTabID` changes, and when the expanded panel finds
    /// another tab shown in the selected one's place (`shownTabDidChange()`), so a
    /// switch may report twice. The shell uses it to end text editing, since hidden
    /// tabs stay mounted and could keep the keyboard.
    @ObservationIgnored var onSelectedTabChange: (() -> Void)?

    private var entries: [ActivityEntry] = []
    @ObservationIgnored private var nextSequence = 0
    @ObservationIgnored private var expiryTask: Task<Void, Never>?
    @ObservationIgnored private var contentUnmountTask: Task<Void, Never>?

    init(geometry: NotchGeometry) {
        self.geometry = geometry
    }

    // MARK: Derived state

    var state: State {
        if isExpanded { return .expanded }
        return currentActivity == nil ? .collapsed : .activity
    }

    /// Whether the panel takes mouse events: the hovered island needs its click
    /// and right-click, the expanded one its controls.
    var isInteractive: Bool {
        isExpanded || isHovered
    }

    /// The activity that wins: highest priority, then most recently presented.
    var currentActivity: NotchActivity? {
        entries.max { lhs, rhs in
            if lhs.activity.priority != rhs.activity.priority {
                return lhs.activity.priority < rhs.activity.priority
            }
            return lhs.sequence < rhs.sequence
        }?.activity
    }

    /// Ids of all queued activities in display order (winner first). For tests and debugging.
    var queuedActivityIDs: [String] {
        entries
            .sorted { lhs, rhs in
                if lhs.activity.priority != rhs.activity.priority {
                    return lhs.activity.priority > rhs.activity.priority
                }
                return lhs.sequence > rhs.sequence
            }
            .map(\.activity.id)
    }

    /// The expanded content sits in place; otherwise it is raised into the notch,
    /// where the island's outline hides it.
    var isExpandedContentDropped: Bool {
        isExpanded && hasExpandedContentAppeared
    }

    /// The tabs whose feature currently offers them, in `tabs` order.
    var visibleTabs: [Tab] {
        tabs.filter { $0.isAvailable() }
    }

    /// The visible tab with `selectedTabID`, else the first visible tab. A hidden
    /// selection is not rewritten, so the user's choice returns with its tab.
    var selectedTab: Tab? {
        let visible = visibleTabs
        return visible.first { $0.id == selectedTabID } ?? visible.first
    }

    /// Body width of the expanded island: what the selected tab asks for, kept
    /// between the standard and the maximum width. Also read while collapsed, so
    /// the expanded content keeps its layout while it rises and drops.
    var expandedBodyWidth: CGFloat {
        let standard = NotchTheme.expandedSize.width
        guard let width = selectedTab?.expandedWidth() else { return standard }
        return min(max(width, standard), NotchTheme.maximumExpandedWidth)
    }

    /// Size of the island body (without the ears) for the current state.
    var bodySize: CGSize {
        let notch = geometry.notchRect.size
        let size: CGSize
        switch state {
        case .collapsed:
            size = notch
        case .activity:
            let wingWidth = currentActivity?.wingWidth ?? NotchTheme.activityWingWidth
            size = CGSize(width: notch.width + wingWidth * 2, height: notch.height)
        case .expanded:
            return CGSize(width: expandedBodyWidth, height: NotchTheme.expandedSize.height)
        }
        guard isHovered else { return size }
        return CGSize(
            width: size.width + NotchTheme.hoverGrowth.width * 2,
            height: size.height + NotchTheme.hoverGrowth.height
        )
    }

    var topCornerRadius: CGFloat {
        switch state {
        case .collapsed: NotchTheme.collapsedTopRadius
        case .activity: NotchTheme.activityTopRadius
        case .expanded: NotchTheme.expandedTopRadius
        }
    }

    var bottomCornerRadius: CGFloat {
        switch state {
        case .collapsed: NotchTheme.collapsedBottomRadius
        case .activity: NotchTheme.activityBottomRadius
        case .expanded: NotchTheme.expandedBottomRadius
        }
    }

    /// The bottom corners as `NotchShape` draws them: round at `bottomCornerRadius`,
    /// and while hovered stretched by the ring the island grows by
    /// (`NotchTheme.hoverGrowth`), so they keep the center of the corners they grew from.
    var bottomCornerRadii: CGSize {
        let radius = bottomCornerRadius
        guard isHovered else { return CGSize(width: radius, height: radius) }
        return CGSize(
            width: radius + NotchTheme.hoverGrowth.width,
            height: radius + NotchTheme.hoverGrowth.height
        )
    }

    /// Frame size of the `NotchShape`, i.e. the body plus both ears.
    var islandSize: CGSize {
        CGSize(
            width: NotchShape.frameWidth(bodyWidth: bodySize.width, topCornerRadius: topCornerRadius),
            height: bodySize.height
        )
    }

    /// Island frame in global screen coordinates (for hover hit-testing).
    var islandScreenFrame: CGRect {
        geometry.topCenteredRect(size: islandSize)
    }

    // MARK: Mutations

    func updateGeometry(_ geometry: NotchGeometry) {
        guard geometry != self.geometry else { return }
        self.geometry = geometry
    }

    /// Selects the first tab visible right now when nothing valid is selected, so a
    /// hidden tab that shows up later does not take over the panel.
    func setTabs(_ tabs: [Tab]) {
        self.tabs = tabs
        if selectedTabID == nil || !tabs.contains(where: { $0.id == selectedTabID }) {
            selectedTabID = (tabs.first { $0.isAvailable() } ?? tabs.first)?.id
        }
    }

    func setExpanded(_ expanded: Bool) {
        guard expanded != isExpanded else { return }
        let wasInteractive = isInteractive
        isExpanded = expanded
        // Expanding replaces the hover; collapsing happens with the pointer outside.
        isHovered = false
        if expanded {
            contentUnmountTask?.cancel()
            contentUnmountTask = nil
            isExpandedContentMounted = true
        } else {
            scheduleContentUnmount()
        }
        reportInteractivity(ifChangedFrom: wasInteractive)
    }

    /// Called by the mounted expanded content once it is on screen, to start its drop.
    func expandedContentDidAppear() {
        hasExpandedContentAppeared = true
    }

    private func scheduleContentUnmount() {
        contentUnmountTask?.cancel()
        let linger = expandedContentLinger
        contentUnmountTask = Task { [weak self] in
            try? await Task.sleep(for: linger)
            guard !Task.isCancelled, let self, !self.isExpanded else { return }
            self.isExpandedContentMounted = false
            self.hasExpandedContentAppeared = false
        }
    }

    /// Ignored while expanded.
    func setHovered(_ hovered: Bool) {
        let hovered = hovered && !isExpanded
        guard hovered != isHovered else { return }
        let wasInteractive = isInteractive
        isHovered = hovered
        reportInteractivity(ifChangedFrom: wasInteractive)
    }

    private func reportInteractivity(ifChangedFrom wasInteractive: Bool) {
        guard isInteractive != wasInteractive else { return }
        onInteractivityChange?(isInteractive)
    }

    /// Called by the expanded panel when the tab it shows changes. That also
    /// happens without `selectedTabID` changing: the selected tab hides and the
    /// first visible one takes its place, or it shows again.
    func shownTabDidChange() {
        onSelectedTabChange?()
    }

    /// Expands the island, selecting `tabID` when such a tab exists and is visible.
    func requestExpand(tabID: String?) {
        if let tabID, visibleTabs.contains(where: { $0.id == tabID }) {
            selectedTabID = tabID
        }
        setExpanded(true)
    }

    /// Expands the island for content dragged onto the notch, on the first visible
    /// tab that takes drops (the selected tab when none does).
    func expandForDrop() {
        requestExpand(tabID: visibleTabs.first(where: \.opensOnDrag)?.id)
    }

    /// Adds an activity, replacing any existing one with the same feature and id.
    /// A replaced activity moves to the front of its priority band and restarts its timer.
    func present(_ activity: NotchActivity, now: Date = Date()) {
        entries.removeAll { $0.activity.id == activity.id && $0.activity.featureID == activity.featureID }
        nextSequence += 1
        entries.append(
            ActivityEntry(
                activity: activity,
                sequence: nextSequence,
                expiresAt: activity.duration.map { now.addingTimeInterval(max(0, $0)) }
            )
        )
        scheduleExpiry(now: now)
    }

    /// Removes an activity. When `featureID` is nil, matches the id across all features.
    func dismiss(activityID: String, featureID: String? = nil) {
        entries.removeAll { entry in
            entry.activity.id == activityID && (featureID == nil || entry.activity.featureID == featureID)
        }
        scheduleExpiry(now: Date())
    }

    /// Drops every activity whose auto-dismiss time is at or before `now`.
    func removeExpired(now: Date = Date()) {
        entries.removeAll { entry in
            guard let expiresAt = entry.expiresAt else { return false }
            return expiresAt <= now
        }
        scheduleExpiry(now: now)
    }

    /// Keeps a single timer aimed at the earliest expiry instead of one task per activity.
    private func scheduleExpiry(now: Date) {
        expiryTask?.cancel()
        expiryTask = nil
        guard let next = entries.compactMap(\.expiresAt).min() else { return }

        let delay = max(0, next.timeIntervalSince(now))
        expiryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.removeExpired()
        }
    }
}

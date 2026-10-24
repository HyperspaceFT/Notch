import Foundation
import NotchKit
import NotchUI
import Observation
import SwiftUI

/// Single source of truth for what the island shows.
///
/// State machine:
/// - `.collapsed`: island exactly covers the hardware notch.
/// - `.activity`: the top-priority activity is shown as wings beside the notch,
///   or as a band of light around it (`NotchActivity.rim`).
/// - `.expanded`: the full panel with feature tabs (a click on the hovered
///   island, content dragged onto the notch, or `requestExpand`). Only tabs
///   whose `isAvailable` is true show (`visibleTabs`).
///   With a `detail` (`requestExpand(detail:featureID:)`) it shows that one view
///   instead, without the tabs. The detail stays while the collapsed content
///   rises out of sight and goes with it; every ordinary expansion (a click,
///   `requestExpand(tabID:)`, a drop) clears it and brings the tabs back.
///
/// Expansion always wins over activities; activities keep their queue while
/// expanded and reappear on collapse. Their timers run on while expanded, except
/// for those that hold (`NotchActivity.holdsWhileExpanded`): theirs stop on
/// expanding and start over in full on collapse.
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
        /// Drawn in the tab button in place of `symbol`; `nil` draws the symbol.
        let icon: AnyView?
        let content: AnyView

        init(
            id: String,
            title: @escaping @MainActor () -> String,
            symbol: @escaping @MainActor () -> String,
            placement: NotchTabPlacement = .leading,
            opensOnDrag: Bool = false,
            isAvailable: @escaping @MainActor () -> Bool = { true },
            expandedWidth: @escaping @MainActor () -> CGFloat? = { nil },
            icon: AnyView? = nil,
            content: AnyView
        ) {
            self.id = id
            self.title = title
            self.symbol = symbol
            self.placement = placement
            self.opensOnDrag = opensOnDrag
            self.isAvailable = isAvailable
            self.expandedWidth = expandedWidth
            self.icon = icon
            self.content = content
        }
    }

    /// A view a feature opened the island on in place of the tabs.
    struct Detail {
        let featureID: String
        /// Distinct for every request, so a new detail replaces the old one's views
        /// even when it comes from the same feature.
        let sequence: Int
        let content: AnyView
    }

    private struct ActivityEntry {
        var activity: NotchActivity
        /// Monotonic insertion order; breaks priority ties in favour of the newest.
        var sequence: Int
        /// Nil without a duration, and for a holding activity while expanded.
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
    /// One per feature, in feature order: the entries it adds to the island's
    /// right-click menu (`NotchFeature.menuItems`).
    private(set) var menuSources: [@MainActor () -> [NotchMenuItem]] = []
    /// Shown instead of the tabs while set. Kept after collapsing until the
    /// expanded content unmounts, so the detail rises out rather than the tabs.
    private(set) var detail: Detail?
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
    /// another tab shown in the selected one's place (`shownTabDidChange()`), or a
    /// detail replaces what the open panel shows, so a switch may report twice.
    /// The shell uses it to end text editing, since hidden tabs stay mounted and
    /// could keep the keyboard.
    @ObservationIgnored var onSelectedTabChange: (() -> Void)?

    private var entries: [ActivityEntry] = []
    @ObservationIgnored private var nextSequence = 0
    @ObservationIgnored private var nextDetailSequence = 0
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
        entries.max(by: Self.ranksBelow)?.activity
    }

    /// The winning activity among those whose wings fly into their tab
    /// (`NotchActivity.morphsIntoTab`). While expanded the shell keeps its wings
    /// whatever is current: activities draw nothing over the open panel, so one
    /// arriving there (a volume change) must not take the heroes away.
    var morphingActivity: NotchActivity? {
        entries.filter(\.activity.morphsIntoTab).max(by: Self.ranksBelow)?.activity
    }

    /// The winning activity among those with a band (`NotchActivity.rim`). The
    /// shell keeps its band while the island is open or another activity is
    /// current, retracted, so the band leaves and returns along the moving outline
    /// instead of appearing on the outline the island is still heading for.
    var rimActivity: NotchActivity? {
        entries.filter { $0.activity.rim != nil }.max(by: Self.ranksBelow)?.activity
    }

    private static func ranksBelow(_ lhs: ActivityEntry, _ rhs: ActivityEntry) -> Bool {
        if lhs.activity.priority != rhs.activity.priority {
            return lhs.activity.priority < rhs.activity.priority
        }
        return lhs.sequence < rhs.sequence
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
    /// between the standard and the maximum width; the standard width for a
    /// detail. Also read while collapsed, so the expanded content keeps its
    /// layout while it rises and drops.
    var expandedBodyWidth: CGFloat {
        let standard = NotchTheme.expandedSize.width
        guard detail == nil, let width = selectedTab?.expandedWidth() else { return standard }
        return min(max(width, standard), NotchTheme.maximumExpandedWidth)
    }

    /// Size of the island body (without the ears) for the current state.
    var bodySize: CGSize {
        let notch = geometry.notchRect.size
        let size: CGSize
        switch state {
        case .collapsed:
            size = notch
        case .activity where currentActivity?.rim != nil:
            // Just room for the band around the notch.
            let thickness = NotchTheme.activityRimThickness
            size = CGSize(width: notch.width + thickness * 2, height: notch.height + thickness)
        case .activity:
            let wings = currentActivity.map(Self.wingWidths)
                ?? (leading: NotchTheme.activityWingWidth, trailing: NotchTheme.activityWingWidth)
            size = CGSize(width: notch.width + wings.leading + wings.trailing, height: notch.height)
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

    /// The widths of `activity`'s wings, left and right (`NotchActivity.wingWidth`
    /// and `leadingWingWidth`).
    static func wingWidths(of activity: NotchActivity) -> (leading: CGFloat, trailing: CGFloat) {
        let trailing = activity.wingWidth ?? NotchTheme.activityWingWidth
        return (activity.leadingWingWidth ?? trailing, trailing)
    }

    /// How far the island's center sits right of the notch's: half of how much
    /// wider the current activity's right wing is than its left, so the notch stays
    /// between them. 0 in every other state.
    var islandOffset: CGFloat {
        guard state == .activity, let activity = currentActivity, activity.rim == nil else { return 0 }
        let wings = Self.wingWidths(of: activity)
        return (wings.trailing - wings.leading) / 2
    }

    /// Island frame in global screen coordinates (for hover hit-testing).
    var islandScreenFrame: CGRect {
        geometry.topCenteredRect(size: islandSize).offsetBy(dx: islandOffset, dy: 0)
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

    func setMenuSources(_ sources: [@MainActor () -> [NotchMenuItem]]) {
        menuSources = sources
    }

    /// The features' menu entries as the right-click menu shows them: one group
    /// per feature that has any, in feature order. Read while the menu draws.
    var menuGroups: [[NotchMenuItem]] {
        menuSources.map { $0() }.filter { !$0.isEmpty }
    }

    /// Expanding from collapsed shows the tabs, even while a detail still rises out.
    func setExpanded(_ expanded: Bool) {
        guard expanded != isExpanded else { return }
        if expanded {
            detail = nil
        }
        applyExpanded(expanded)
    }

    private func applyExpanded(_ expanded: Bool) {
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
        holdExpiries(whileExpanded: expanded, now: Date())
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
            self.detail = nil
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
    /// Already expanded on a detail, it brings the tabs back.
    func requestExpand(tabID: String?) {
        let replacesDetail = isExpanded && detail != nil
        detail = nil
        if let tabID, visibleTabs.contains(where: { $0.id == tabID }) {
            selectedTabID = tabID
        }
        setExpanded(true)
        if replacesDetail {
            shownTabDidChange()
        }
    }

    /// Expands the island on `content` alone, without the tabs. Already expanded,
    /// it replaces what is shown (the tabs or another detail), which ends any text
    /// editing as a tab switch does.
    func requestExpand(detail content: AnyView, featureID: String) {
        nextDetailSequence += 1
        detail = Detail(featureID: featureID, sequence: nextDetailSequence, content: content)
        if isExpanded {
            shownTabDidChange()
        } else {
            applyExpanded(true)
        }
    }

    /// Expands the island for content dragged onto the notch, on the first visible
    /// tab that takes drops (the selected tab when none does).
    func expandForDrop() {
        requestExpand(tabID: visibleTabs.first(where: \.opensOnDrag)?.id)
    }

    /// Adds an activity, replacing any existing one with the same feature and id.
    /// A replaced activity moves to the front of its priority band and restarts its
    /// timer; one that holds, presented while expanded, starts it on collapse.
    func present(_ activity: NotchActivity, now: Date = Date()) {
        entries.removeAll { $0.activity.id == activity.id && $0.activity.featureID == activity.featureID }
        nextSequence += 1
        entries.append(
            ActivityEntry(
                activity: activity,
                sequence: nextSequence,
                expiresAt: expiry(of: activity, now: now)
            )
        )
        scheduleExpiry(now: now)
    }

    /// `duration` after `now`; nil without one, or while expanded for an
    /// activity that holds.
    private func expiry(of activity: NotchActivity, now: Date) -> Date? {
        guard !(activity.holdsWhileExpanded && isExpanded) else { return nil }
        return activity.duration.map { now.addingTimeInterval(max(0, $0)) }
    }

    /// Stops the timers of activities that hold on expanding, and gives them
    /// their whole duration again on collapse.
    private func holdExpiries(whileExpanded expanded: Bool, now: Date) {
        guard entries.contains(where: { $0.activity.holdsWhileExpanded && $0.activity.duration != nil }) else { return }
        for index in entries.indices where entries[index].activity.holdsWhileExpanded {
            entries[index].expiresAt = expanded ? nil : expiry(of: entries[index].activity, now: now)
        }
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

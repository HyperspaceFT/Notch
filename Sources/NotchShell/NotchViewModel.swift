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
///   island, or `requestExpand`).
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
        let title: String
        let symbol: String
        let content: AnyView
    }

    private struct ActivityEntry {
        var activity: NotchActivity
        /// Monotonic insertion order; breaks priority ties in favour of the newest.
        var sequence: Int
        var expiresAt: Date?
    }

    private(set) var geometry: NotchGeometry
    private(set) var isExpanded = false
    /// The pointer rests on the collapsed or activity island. Always false while expanded.
    private(set) var isHovered = false
    private(set) var tabs: [Tab] = []
    var selectedTabID: String?

    /// When false, the hover controller leaves the state alone (debug pinning).
    var isHoverEnabled = true

    /// Invoked whenever `isInteractive` changes; the shell uses it to toggle mouse
    /// interception on the panel.
    @ObservationIgnored var onInteractivityChange: ((Bool) -> Void)?

    private var entries: [ActivityEntry] = []
    @ObservationIgnored private var nextSequence = 0
    @ObservationIgnored private var expiryTask: Task<Void, Never>?

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

    var selectedTab: Tab? {
        tabs.first { $0.id == selectedTabID } ?? tabs.first
    }

    /// Size of the island body (without the ears) for the current state.
    var bodySize: CGSize {
        let notch = geometry.notchRect.size
        let size: CGSize
        switch state {
        case .collapsed:
            size = notch
        case .activity:
            size = CGSize(width: notch.width + NotchTheme.activityWingWidth * 2, height: notch.height)
        case .expanded:
            return NotchTheme.expandedSize
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

    func setTabs(_ tabs: [Tab]) {
        self.tabs = tabs
        if selectedTabID == nil || !tabs.contains(where: { $0.id == selectedTabID }) {
            selectedTabID = tabs.first?.id
        }
    }

    func setExpanded(_ expanded: Bool) {
        guard expanded != isExpanded else { return }
        let wasInteractive = isInteractive
        isExpanded = expanded
        // Expanding replaces the hover; collapsing happens with the pointer outside.
        isHovered = false
        reportInteractivity(ifChangedFrom: wasInteractive)
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

    /// Expands the island, selecting `tabID` when such a tab exists.
    func requestExpand(tabID: String?) {
        if let tabID, tabs.contains(where: { $0.id == tabID }) {
            selectedTabID = tabID
        }
        setExpanded(true)
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

import AppKit

/// Marks the island hovered when the pointer stays on the notch for `hoverDelay`
/// (it grows and the trackpad taps once), drops the hover when the pointer leaves it, and
/// collapses the expanded island when the pointer leaves that. Expanding itself
/// takes a click on the hovered island, handled in `NotchRootView`.
///
/// Uses global + local NSEvent mouse monitors. Mouse-move monitors do not require
/// the Accessibility permission (only keyboard monitors do), so none is requested.
@MainActor
final class HoverController {
    /// Time from entering the hot zone to the hover; a sweep across the menu bar
    /// that leaves sooner neither grows the island nor taps the trackpad.
    static let hoverDelay: Duration = .milliseconds(80)
    /// Debounce before collapsing after the pointer leaves the expanded island.
    static let collapseDelay: Duration = .milliseconds(250)
    /// How far the hot zone extends beyond the collapsed island.
    static let hotZoneInset = CGSize(width: 6, height: 4)
    /// Extra room around the expanded island before it counts as "left".
    static let exitMargin: CGFloat = 8
    /// The same for the hovered island. Kept small because the whole panel takes
    /// clicks while hovered; the ring alone already reaches past the hot zone.
    static let hoverExitMargin: CGFloat = 2

    private enum Pending {
        case hover
        case collapse
    }

    private let model: NotchViewModel
    private var monitors: [Any] = []
    private var pending: Pending?
    private var pendingTask: Task<Void, Never>?

    init(model: NotchViewModel) {
        self.model = model
    }

    isolated deinit {
        stop()
    }

    func start() {
        guard monitors.isEmpty else { return }
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]

        // Events for other apps (most of the time, since the panel ignores the mouse when collapsed).
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            // AppKit delivers monitor callbacks on the main thread.
            MainActor.assumeIsolated { self?.pointerMoved() }
        }) {
            monitors.append(global)
        }
        // Events for our own panel (while hovered or expanded and accepting the mouse).
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.pointerMoved() }
            return event
        }) {
            monitors.append(local)
        }
    }

    func stop() {
        for monitor in monitors {
            NSEvent.removeMonitor(monitor)
        }
        monitors = []
        cancelPending()
    }

    private func pointerMoved() {
        guard model.isHoverEnabled else {
            cancelPending()
            return
        }
        let location = NSEvent.mouseLocation

        if model.isExpanded {
            if isInsideIsland(location, margin: Self.exitMargin) {
                cancelPending(.collapse)
            } else {
                schedule(.collapse, after: Self.collapseDelay)
            }
        } else if model.isHovered {
            // No debounce: while hovered the whole panel takes the mouse, so any
            // lingering would swallow clicks meant for the menu bar beside it.
            if !isInsideIsland(location, margin: Self.hoverExitMargin) {
                model.setHovered(false)
            }
        } else {
            if isInsideHotZone(location) {
                schedule(.hover, after: Self.hoverDelay)
            } else {
                cancelPending(.hover)
            }
        }
    }

    private func isInsideHotZone(_ point: CGPoint) -> Bool {
        model.islandScreenFrame
            .insetBy(dx: -Self.hotZoneInset.width, dy: -Self.hotZoneInset.height)
            .contains(point)
    }

    /// For the hovered or expanded island, whose frame already has its final size.
    private func isInsideIsland(_ point: CGPoint, margin: CGFloat) -> Bool {
        model.islandScreenFrame
            .insetBy(dx: -margin, dy: -margin)
            .contains(point)
    }

    private func schedule(_ action: Pending, after delay: Duration) {
        guard pending != action else { return }
        cancelPending()
        pending = action
        pendingTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.firePending(action)
        }
    }

    private func firePending(_ action: Pending) {
        pending = nil
        pendingTask = nil
        guard model.isHoverEnabled else { return }
        // Re-check against the pointer position at fire time, not at schedule time.
        let location = NSEvent.mouseLocation
        switch action {
        case .hover:
            if !model.isExpanded, !model.isHovered, isInsideHotZone(location) {
                model.setHovered(true)
                // Felt only on a Force Touch trackpad with a finger on it; a no-op otherwise.
                NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
            }
        case .collapse:
            if model.isExpanded, !isInsideIsland(location, margin: Self.exitMargin) {
                model.setExpanded(false)
            }
        }
    }

    /// Cancels the pending action, or only `action` when given.
    private func cancelPending(_ action: Pending? = nil) {
        guard let pending, action == nil || action == pending else { return }
        pendingTask?.cancel()
        pendingTask = nil
        self.pending = nil
    }
}

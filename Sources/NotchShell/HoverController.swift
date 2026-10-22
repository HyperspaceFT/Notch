import AppKit

/// Expands the island when the pointer enters the notch and collapses it when
/// the pointer leaves the expanded island.
///
/// Uses global + local NSEvent mouse monitors. Mouse-move monitors do not require
/// the Accessibility permission (only keyboard monitors do), so none is requested.
@MainActor
final class HoverController {
    /// Delay before expanding, so quickly sweeping across the menu bar does not open the island.
    static let expandDelay: Duration = .milliseconds(80)
    /// Debounce before collapsing after the pointer leaves the island.
    static let collapseDelay: Duration = .milliseconds(250)
    /// How far the hot zone extends beyond the collapsed island.
    static let hotZoneInset = CGSize(width: 6, height: 4)
    /// Extra room around the expanded island before it counts as "left".
    static let exitMargin: CGFloat = 8

    private enum Pending {
        case expand
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
        // Events for our own panel (while expanded and accepting the mouse).
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
            if isInsideExpandedIsland(location) {
                cancelPending(.collapse)
            } else {
                schedule(.collapse, after: Self.collapseDelay)
            }
        } else {
            if isInsideHotZone(location) {
                schedule(.expand, after: Self.expandDelay)
            } else {
                cancelPending(.expand)
            }
        }
    }

    private func isInsideHotZone(_ point: CGPoint) -> Bool {
        model.islandScreenFrame
            .insetBy(dx: -Self.hotZoneInset.width, dy: -Self.hotZoneInset.height)
            .contains(point)
    }

    private func isInsideExpandedIsland(_ point: CGPoint) -> Bool {
        model.islandScreenFrame
            .insetBy(dx: -Self.exitMargin, dy: -Self.exitMargin)
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
        case .expand:
            if !model.isExpanded, isInsideHotZone(location) {
                model.setExpanded(true)
            }
        case .collapse:
            if model.isExpanded, !isInsideExpandedIsland(location) {
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

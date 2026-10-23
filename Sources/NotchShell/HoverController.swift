import AppKit

/// Marks the island hovered when the pointer stays on the notch for `hoverDelay`
/// (it grows and the trackpad taps once), drops the hover when the pointer leaves it, and
/// collapses the expanded island when the pointer leaves that. Expanding itself
/// takes a click on the hovered island, handled in `NotchRootView`; only content
/// dragged onto the notch (files, for instance) expands it directly, because a
/// drag cannot click.
///
/// Uses global + local NSEvent mouse monitors. Mouse-move monitors do not require
/// the Accessibility permission (only keyboard monitors do), so none is requested.
@MainActor
final class HoverController {
    /// Time from entering the hot zone to the hover; a sweep across the menu bar
    /// that leaves sooner neither grows the island nor taps the trackpad.
    /// Content dragged onto the notch waits as long before the island opens.
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
        case dropExpand
        case collapse
    }

    private let model: NotchViewModel
    /// A drag that carries content (files, text, images) writes this pasteboard when it starts.
    private let dragPasteboard = NSPasteboard(name: .drag)
    /// `dragPasteboard.changeCount` at the last left mouse-down; a different count
    /// while the button is still held means the current drag carries content.
    private var dragChangeCountAtMouseDown: Int?
    private var monitors: [Any] = []
    private var pending: Pending?
    private var pendingTask: Task<Void, Never>?
    /// The expanded island's frame the last time the pointer was inside it. Its width
    /// follows the selected tab, so a click on a tab button near the edge of a wide
    /// tab can leave the pointer outside the narrower new frame; that is not a
    /// departure. Replaced as soon as the pointer is inside the current frame again,
    /// and cleared whenever the island is not expanded.
    private var frameWithPointer: CGRect?

    init(model: NotchViewModel) {
        self.model = model
    }

    isolated deinit {
        stop()
    }

    func start() {
        guard monitors.isEmpty else { return }
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .leftMouseDown]

        // Events for other apps (most of the time, since the panel ignores the mouse when collapsed).
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            let type = event.type
            // AppKit delivers monitor callbacks on the main thread.
            MainActor.assumeIsolated { self?.handle(type) }
        }) {
            monitors.append(global)
        }
        // Events for our own panel (while hovered or expanded and accepting the mouse).
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            let type = event.type
            MainActor.assumeIsolated { self?.handle(type) }
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
        frameWithPointer = nil
    }

    private func handle(_ type: NSEvent.EventType) {
        if type == .leftMouseDown {
            dragChangeCountAtMouseDown = dragPasteboard.changeCount
        } else {
            pointerMoved(dragging: type == .leftMouseDragged)
        }
    }

    private func pointerMoved(dragging: Bool) {
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
        } else if model.isHovered {
            frameWithPointer = nil
            // No debounce: while hovered the whole panel takes the mouse, so any
            // lingering would swallow clicks meant for the menu bar beside it.
            if !isInsideIsland(location, margin: Self.hoverExitMargin) {
                model.setHovered(false)
            }
        } else {
            frameWithPointer = nil
            if isInsideHotZone(location) {
                schedule(dragging && isDraggingContent ? .dropExpand : .hover, after: Self.hoverDelay)
            } else {
                cancelPending(.hover)
                cancelPending(.dropExpand)
            }
        }
    }

    /// Only meaningful while the left button is held, i.e. for dragged events.
    private var isDraggingContent: Bool {
        guard let dragChangeCountAtMouseDown else { return false }
        return dragPasteboard.changeCount != dragChangeCountAtMouseDown
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

    /// Whether `point` is within `margin` of the `current` expanded frame or of the
    /// `remembered` one, the frame before the island resized under the pointer.
    nonisolated static func isInsideExpanded(_ point: CGPoint, current: CGRect, remembered: CGRect?, margin: CGFloat) -> Bool {
        if current.insetBy(dx: -margin, dy: -margin).contains(point) { return true }
        return remembered?.insetBy(dx: -margin, dy: -margin).contains(point) ?? false
    }

    /// The expanded island's exit test; refreshes `frameWithPointer` while the
    /// pointer is inside the current frame.
    private func isInsideExpandedIsland(_ point: CGPoint) -> Bool {
        let current = model.islandScreenFrame
        if isInsideIsland(point, margin: Self.exitMargin) {
            frameWithPointer = current
            return true
        }
        return Self.isInsideExpanded(point, current: current, remembered: frameWithPointer, margin: Self.exitMargin)
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
        case .dropExpand:
            // A drag released within the delay landed on the menu bar; there is nothing to drop.
            if !model.isExpanded, NSEvent.pressedMouseButtons & 1 != 0, isInsideHotZone(location) {
                model.expandForDrop()
                NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
            }
        case .collapse:
            if model.isExpanded, !isInsideExpandedIsland(location) {
                frameWithPointer = nil
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

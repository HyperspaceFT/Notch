import AppKit

/// Finds the screen that hosts the island and reports geometry changes
/// (display connected/disconnected, resolution or arrangement changed).
@MainActor
final class ScreenLocator: NSObject {
    var onChange: ((NotchGeometry) -> Void)?
    private var isObserving = false

    func start() {
        guard !isObserving else { return }
        isObserving = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange(_:)),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    func stop() {
        guard isObserving else { return }
        isObserving = false
        NotificationCenter.default.removeObserver(
            self,
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    /// Geometry for the preferred screen: the first one with a hardware notch,
    /// else the main screen. `nil` only when no screen is attached at all.
    func currentGeometry() -> NotchGeometry? {
        let screens = NSScreen.screens
        let screen = screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? screens.first
        guard let screen else { return nil }
        return NotchGeometry(
            screenFrame: screen.frame,
            safeAreaTop: screen.safeAreaInsets.top,
            auxiliaryTopLeftArea: screen.auxiliaryTopLeftArea ?? .zero,
            auxiliaryTopRightArea: screen.auxiliaryTopRightArea ?? .zero
        )
    }

    // Posted on the main thread by AppKit.
    @objc private func screenParametersDidChange(_ notification: Notification) {
        guard let geometry = currentGeometry() else { return }
        onChange?(geometry)
    }
}

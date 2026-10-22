import AppKit
import ApplicationServices
import Observation

/// Whether Notch shows its own volume and brightness HUD instead of the system's,
/// and whether it has the Accessibility access that intercepting the keys needs.
@MainActor
@Observable
public final class SystemHUDSettings {
    public static let shared = SystemHUDSettings(defaults: .standard)

    static let enabledKey = "NotchReplacesSystemHUD"

    /// On by default; takes effect only with Accessibility access.
    public var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Self.enabledKey) }
    }

    /// Whether macOS trusts Notch for Accessibility. Read again by
    /// `refreshAccessibilityAccess()`, since the user grants it in System Settings.
    public private(set) var hasAccessibilityAccess: Bool

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var hasPrompted = false

    init(defaults: UserDefaults) {
        self.defaults = defaults
        isEnabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? true
        hasAccessibilityAccess = AXIsProcessTrusted()
    }

    public func refreshAccessibilityAccess() {
        let trusted = AXIsProcessTrusted()
        // Only a real change notifies observers, so polling does not redraw anything.
        if trusted != hasAccessibilityAccess {
            hasAccessibilityAccess = trusted
        }
    }

    /// Opens System Settings at Privacy & Security → Accessibility.
    public func requestAccessibilityAccess() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    /// Shows the system's Accessibility prompt, at most once per launch.
    func promptForAccessibilityAccessOnce() {
        guard !hasPrompted else { return }
        hasPrompted = true
        // The literal value of `kAXTrustedCheckOptionPrompt`, which imports as a
        // mutable global that Swift 6 rejects as not concurrency-safe.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        hasAccessibilityAccess = AXIsProcessTrustedWithOptions(options)
    }
}

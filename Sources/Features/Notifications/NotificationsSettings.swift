import AppKit
import ApplicationServices
import Observation

/// Whether the island shows other apps' notification banners and hides the
/// system's, and whether Notch has the Accessibility access reading them needs.
@MainActor
@Observable
public final class NotificationsSettings {
    public static let shared = NotificationsSettings(defaults: .standard)

    static let enabledKey = "NotchMirrorsNotifications"
    static let hidesBannersKey = "NotchHidesNotificationBanners"

    /// On by default; takes effect only with Accessibility access.
    public var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Self.enabledKey) }
    }

    /// Off by default: moves the system's banner off screen while the island shows it.
    public var hidesSystemBanners: Bool {
        didSet { defaults.set(hidesSystemBanners, forKey: Self.hidesBannersKey) }
    }

    /// Whether macOS trusts Notch for Accessibility. Read again by
    /// `refreshAccessibilityAccess()`, since the user grants it in System Settings.
    public private(set) var hasAccessibilityAccess: Bool

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
        isEnabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? true
        hidesSystemBanners = defaults.object(forKey: Self.hidesBannersKey) as? Bool ?? false
        hasAccessibilityAccess = AXIsProcessTrusted()
    }

    public func refreshAccessibilityAccess() {
        let trusted = AXIsProcessTrusted()
        // Only a real change notifies observers, so polling does not redraw anything.
        if trusted != hasAccessibilityAccess {
            hasAccessibilityAccess = trusted
        }
    }

    /// Opens System Settings at Privacy & Security → Accessibility. Never shows the
    /// system prompt: the volume HUD already does, once per launch, and a second
    /// one would stack on it.
    public func requestAccessibilityAccess() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}

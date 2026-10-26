import AppKit
import ApplicationServices
import Observation

/// How reading the notification database goes, for the settings window.
public enum NotificationDatabaseStatus: Equatable, Sendable {
    /// Not read yet, or reading is off.
    case unknown
    case working
    /// Full Disk Access is missing.
    case noAccess
    /// The database is missing or no longer reads as Notch expects: macOS
    /// changed it, most likely in an update.
    case broken
}

/// Whether the island shows other apps' notification banners and hides the
/// system's, whether it also reads the notification database, and whether Notch
/// has the Accessibility and Full Disk Access these need.
@MainActor
@Observable
public final class NotificationsSettings {
    public static let shared = NotificationsSettings(defaults: .standard)

    static let enabledKey = "NotchMirrorsNotifications"
    static let hidesBannersKey = "NotchHidesNotificationBanners"
    static let readsDatabaseKey = "NotchReadsNotificationDatabase"

    /// On by default; takes effect only with Accessibility access.
    public var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Self.enabledKey) }
    }

    /// Off by default: moves the system's banner off screen while the island shows it.
    public var hidesSystemBanners: Bool {
        didSet { defaults.set(hidesSystemBanners, forKey: Self.hidesBannersKey) }
    }

    /// Off by default: also reads usernoted's database (`NotificationDatabase`),
    /// for the notifications macOS lists without showing a banner. Needs Full
    /// Disk Access.
    public var readsDatabase: Bool {
        didSet { defaults.set(readsDatabase, forKey: Self.readsDatabaseKey) }
    }

    /// Whether Notch may open the notification database. Read again by
    /// `refreshFullDiskAccess()`, since the user grants it in System Settings.
    /// Also true while the file is missing, which `databaseStatus` reports.
    public private(set) var hasFullDiskAccess: Bool

    /// Set by the feature while it reads the database.
    public internal(set) var databaseStatus = NotificationDatabaseStatus.unknown

    /// Whether macOS trusts Notch for Accessibility. Read again by
    /// `refreshAccessibilityAccess()`, since the user grants it in System Settings.
    public private(set) var hasAccessibilityAccess: Bool

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
        isEnabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? true
        hidesSystemBanners = defaults.object(forKey: Self.hidesBannersKey) as? Bool ?? false
        readsDatabase = defaults.object(forKey: Self.readsDatabaseKey) as? Bool ?? false
        hasAccessibilityAccess = AXIsProcessTrusted()
        hasFullDiskAccess = NotificationDatabase.access() != .denied
    }

    public func refreshAccessibilityAccess() {
        let trusted = AXIsProcessTrusted()
        // Only a real change notifies observers, so polling does not redraw anything.
        if trusted != hasAccessibilityAccess {
            hasAccessibilityAccess = trusted
        }
    }

    public func refreshFullDiskAccess() {
        let readable = NotificationDatabase.access() != .denied
        if readable != hasFullDiskAccess {
            hasFullDiskAccess = readable
        }
    }

    /// Opens System Settings at Privacy & Security → Full Disk Access, where the
    /// user adds Notch; macOS has no prompt for it.
    public func requestFullDiskAccess() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else {
            return
        }
        NSWorkspace.shared.open(url)
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

import AppKit
import os
import UserNotifications

/// Posts the Debug pane's samples as real notifications from Notch, so they take
/// the path any app's do: the system shows the banner, or holds it back (Focus,
/// Notch's notifications turned off), and the island shows it only if
/// `NotificationBannerWatcher` catches that banner. Permission is asked for on
/// the first post; once denied, Notch's page in Notifications settings opens
/// instead.
@MainActor
final class SystemNotificationPoster {
    /// How long apart the samples of one run are posted.
    static let interval: Duration = .seconds(1)

    private let presenter = ForegroundPresenter()
    private var run: Task<Void, Never>?

    /// Posts `samples` one after another, replacing a run still going.
    func post(_ samples: [NotificationSample]) {
        // UNUserNotificationCenter raises outside an app bundle (`swift run`).
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return }
        run?.cancel()
        run = Task { [presenter] in
            let center = UNUserNotificationCenter.current()
            center.delegate = presenter
            guard await Self.isAuthorized(center) else {
                Logger.notifications.notice("Debug notifications are not allowed; opening Notifications settings")
                Self.openSettings(bundleIdentifier: bundleIdentifier)
                return
            }
            for (index, sample) in samples.enumerated() {
                if index > 0 {
                    try? await Task.sleep(for: Self.interval)
                }
                guard !Task.isCancelled else { return }
                let content = UNMutableNotificationContent()
                content.title = sample.title
                if let subtitle = sample.subtitle {
                    content.subtitle = subtitle
                }
                content.body = sample.body
                // A fresh identifier each time, so no post replaces an earlier one.
                let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
                do {
                    try await center.add(request)
                    Logger.notifications.notice("Posted debug notification \(index + 1) of \(samples.count)")
                } catch {
                    Logger.notifications.error("Could not post a debug notification: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    /// Stops a run; what was posted stays in Notification Center.
    func cancel() {
        run?.cancel()
        run = nil
    }

    /// Asks the first time; after that, follows what the user chose.
    private static func isAuthorized(_ center: UNUserNotificationCenter) async -> Bool {
        switch await center.notificationSettings().authorizationStatus {
        case .notDetermined:
            (try? await center.requestAuthorization(options: [.alert])) ?? false
        case .denied:
            false
        default:
            true
        }
    }

    private static func openSettings(bundleIdentifier: String) {
        let address = "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(bundleIdentifier)"
        guard let url = URL(string: address) else { return }
        NSWorkspace.shared.open(url)
    }
}

/// Notch is the active app when a Debug pane button is clicked, and the system
/// shows an active app's notifications only in Notification Center unless its
/// delegate asks for the banner.
private final class ForegroundPresenter: NSObject, UNUserNotificationCenterDelegate, Sendable {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }
}

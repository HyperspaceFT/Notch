import NotchKit
import NotchUI
import Observation
import os
import SwiftUI

/// Mirrors other apps' notification banners into the island: each new banner
/// shows as an activity beside the notch, its app on the left and its text on
/// the right, and joins a tab right of the notch that lists the notifications
/// caught since launch, in memory only. A click on the activity opens the island
/// on that notification alone, in full (`NotificationDetailView`). There is no
/// API for this: the banners are read from NotificationCenter through
/// Accessibility (`NotificationBannerWatcher`), so the feature waits until Notch
/// has that access.
///
/// With "Hide System Banners" on (`NotificationsSettings`, off by default), the
/// system's banner moves off screen while the island shows it.
@MainActor
public final class NotificationsFeature: NotchFeature {
    public let id = "notifications"
    public var title: String { localized(en: "Notifications", zh: "通知") }
    public let symbol = "bell.badge"
    public let tabPlacement = NotchTabPlacement.trailing
    public var isTabAvailable: Bool { !inbox.items.isEmpty }

    static let activityID = "banner"
    /// How long a banner's activity stays visible.
    static let activityDuration: TimeInterval = 6
    /// How often Accessibility access is checked again while it is missing.
    static let accessPollInterval: Duration = .seconds(2)

    private let settings = NotificationsSettings.shared
    private let inbox = NotificationInbox()
    private let apps = NotificationAppResolver()
    private var watcher: NotificationBannerWatcher?
    private var accessPoll: Task<Void, Never>?
    /// Posts the Debug pane's notifications through the system.
    private let samplePoster = SystemNotificationPoster()
    /// Bumped on activate and deactivate; an observation armed under another
    /// generation is stale and does nothing when it fires.
    private var observationGeneration = 0
    private weak var context: (any NotchContext)?

    public init() {}

    public func activate(context: any NotchContext) {
        self.context = context
        apps.onResolved = { [weak self] name, app in
            self?.inbox.setApp(bundleIdentifier: app.bundleIdentifier, url: app.url, forAppNamed: name)
        }
        observationGeneration += 1
        followSettings(generation: observationGeneration)
    }

    public func deactivate() {
        // `withObservationTracking` cannot be cancelled; the new generation makes
        // its pending change handler a no-op.
        observationGeneration += 1
        stopWatching()
        samplePoster.cancel()
        context?.dismiss(activityID: Self.activityID)
        inbox.removeAll()
        apps.onResolved = nil
        context = nil
    }

    public func makeExpandedView() -> AnyView? {
        AnyView(NotificationsTabView(inbox: inbox, apps: apps) { [weak self] item in
            self?.openApp(of: item)
        })
    }

    /// Real notifications from Notch, posted through the system: the island shows
    /// them only as it would any app's banner, so only with mirroring on,
    /// Accessibility access, and the banner caught.
    public var debugItems: [NotchMenuItem] {
        [
            .button(localized(en: "Short Notification", zh: "短通知"), symbol: "bell") { [weak self] in
                self?.samplePoster.post([NotificationSample.short])
            },
            .button(localized(en: "Long Notification", zh: "长通知"), symbol: "text.alignleft") { [weak self] in
                self?.samplePoster.post([NotificationSample.long])
            },
            .button(localized(en: "Three Notifications in a Row", zh: "连续 3 条通知"), symbol: "square.stack") { [weak self] in
                self?.samplePoster.post(NotificationSample.sequence)
            },
        ]
    }

    /// Starts or stops watching to match `isEnabled`, and passes on
    /// `hidesSystemBanners`, again on every change.
    private func followSettings(generation: Int) {
        guard generation == observationGeneration else { return }
        let (isEnabled, hidesBanners) = withObservationTracking {
            (settings.isEnabled, settings.hidesSystemBanners)
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.followSettings(generation: generation)
            }
        }
        Logger.notifications.notice("Mirroring \(isEnabled ? "on" : "off", privacy: .public), hide system banners: \(hidesBanners)")
        if isEnabled {
            startWatching()
            watcher?.hidesBanners = hidesBanners
        } else {
            stopWatching()
            context?.dismiss(activityID: Self.activityID)
            inbox.removeAll()
        }
    }

    private func startWatching() {
        guard watcher == nil else { return }
        settings.refreshAccessibilityAccess()
        if settings.hasAccessibilityAccess {
            accessPoll?.cancel()
            accessPoll = nil
            makeWatcher()
            return
        }
        // No prompt: the volume HUD shows the system's, and the settings window
        // links to System Settings.
        Logger.notifications.notice("No Accessibility access; checking again every 2 s")
        startPolling()
    }

    private func stopWatching() {
        watcher?.stop()
        watcher = nil
        accessPoll?.cancel()
        accessPoll = nil
    }

    private func makeWatcher() {
        let watcher = NotificationBannerWatcher(defaults: .standard) { [weak self] captures in
            self?.bannersArrived(captures)
        }
        watcher.hidesBanners = settings.hidesSystemBanners
        self.watcher = watcher
        watcher.start()
    }

    private func startPolling() {
        guard accessPoll == nil else { return }
        accessPoll = Task { [weak self] in
            while true {
                try? await Task.sleep(for: Self.accessPollInterval)
                guard !Task.isCancelled, let self else { return }
                settings.refreshAccessibilityAccess()
                if settings.hasAccessibilityAccess {
                    Logger.notifications.notice("Accessibility access granted")
                    accessPoll = nil
                    if watcher == nil {
                        makeWatcher()
                    }
                    return
                }
            }
        }
    }

    /// Lists every new banner and shows the newest beside the notch.
    private func bannersArrived(_ captures: [BannerCapture]) {
        let now = Date()
        notificationsArrived(captures.map { capture in
            let app = capture.appName.flatMap(apps.resolve)
            return NotificationItem(
                token: capture.token,
                appName: capture.appName,
                bundleIdentifier: app?.bundleIdentifier,
                appURL: app?.url,
                title: capture.title,
                subtitle: capture.subtitle,
                body: capture.body,
                received: now
            )
        })
    }

    /// Lists `items` and shows the last beside the notch.
    private func notificationsArrived(_ items: [NotificationItem]) {
        for item in items {
            inbox.insert(item)
        }
        guard let newest = items.last else { return }
        let listed = inbox.items.count
        Logger.notifications.notice(
            "Presenting the activity for \(newest.appName ?? "unknown app", privacy: .public) (\(items.count) new, \(listed) listed)"
        )
        // The same id replaces the previous banner's activity and restarts its timer.
        let open: @MainActor () -> Void = { [weak self] in
            self?.openDetail(of: newest)
        }
        // Fitted to this notification's text: a short one keeps the island small.
        let wings = NotificationWings.widths(for: newest)
        context?.present(NotchActivity(
            id: Self.activityID,
            priority: .high,
            duration: Self.activityDuration,
            wingWidth: wings.trailing,
            leadingWingWidth: wings.leading
        ) { [inbox, apps] in
            NotificationWingLeading(item: newest, inbox: inbox, apps: apps, open: open)
        } trailing: { [inbox] in
            NotificationWingTrailing(item: newest, inbox: inbox, open: open)
        })
    }

    /// Opens the island on the whole notification, in place of its activity.
    private func openDetail(of item: NotificationItem) {
        context?.requestExpand(detail: AnyView(NotificationDetailView(item: item, inbox: inbox, apps: apps)))
        context?.dismiss(activityID: Self.activityID)
    }

    /// Brings the item's app forward and takes the item off the list; leaves it
    /// listed when there is no app to open.
    private func openApp(of item: NotificationItem) {
        if apps.open(bundleIdentifier: item.bundleIdentifier, url: item.appURL) {
            inbox.remove(id: item.id)
        }
    }
}

import NotchKit
import NotchUI
import Observation
import SwiftUI

/// Mirrors other apps' notification banners into the island: each new banner
/// shows as an activity beside the notch, its app on the left and its text on
/// the right, and joins a tab right of the notch that lists the notifications
/// caught since launch, in memory only. There is no API for this: the banners
/// are read from NotificationCenter through Accessibility
/// (`NotificationBannerWatcher`), so the feature waits until Notch has that access.
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
        var newest: NotificationItem?
        for capture in captures {
            let app = capture.appName.flatMap(apps.resolve)
            let item = NotificationItem(
                token: capture.token,
                appName: capture.appName,
                bundleIdentifier: app?.bundleIdentifier,
                appURL: app?.url,
                title: capture.title,
                subtitle: capture.subtitle,
                body: capture.body,
                received: now
            )
            inbox.insert(item)
            newest = item
        }
        guard let newest else { return }
        // The same id replaces the previous banner's activity and restarts its timer.
        let open: @MainActor () -> Void = { [weak self] in
            self?.openTab()
        }
        context?.present(NotchActivity(
            id: Self.activityID,
            priority: .high,
            duration: Self.activityDuration,
            wingWidth: notificationWingWidth
        ) { [inbox, apps] in
            NotificationWingLeading(item: newest, inbox: inbox, apps: apps, open: open)
        } trailing: { [inbox] in
            NotificationWingTrailing(item: newest, inbox: inbox, open: open)
        })
    }

    private func openTab() {
        context?.requestExpand()
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

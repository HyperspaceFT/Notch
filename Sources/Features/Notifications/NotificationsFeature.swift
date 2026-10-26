import AppKit
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
/// system's banner moves off screen while the island shows it. With "Read the
/// Notification Database" on (off by default, needs Full Disk Access), the
/// notifications macOS listed without a banner are shown too, from usernoted's
/// database (`NotificationDatabaseWatcher`), some seconds late; those whose
/// banner the island already showed are recognized (`RecentBanners`).
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
    private var databaseWatcher: NotificationDatabaseWatcher?
    /// The banners shown lately, which database records are matched against.
    private var recentBanners = RecentBanners()
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
        stopReadingDatabase()
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

    /// Starts or stops watching to match `isEnabled` and `readsDatabase`, and
    /// passes on `hidesSystemBanners`, again on every change.
    private func followSettings(generation: Int) {
        guard generation == observationGeneration else { return }
        let (isEnabled, hidesBanners, readsDatabase) = withObservationTracking {
            (settings.isEnabled, settings.hidesSystemBanners, settings.readsDatabase)
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.followSettings(generation: generation)
            }
        }
        Logger.notifications.notice(
            "Mirroring \(isEnabled ? "on" : "off", privacy: .public), hide system banners: \(hidesBanners), read database: \(readsDatabase)"
        )
        if isEnabled {
            startWatching()
            watcher?.hidesBanners = hidesBanners
        } else {
            stopWatching()
            context?.dismiss(activityID: Self.activityID)
            inbox.removeAll()
        }
        if isEnabled, readsDatabase {
            startReadingDatabase()
        } else {
            stopReadingDatabase()
        }
    }

    /// Without Full Disk Access the watcher keeps trying, so access granted later
    /// takes effect without turning the switch off and on.
    private func startReadingDatabase() {
        guard databaseWatcher == nil else { return }
        let watcher = NotificationDatabaseWatcher { [weak self] records in
            self?.recordsArrived(records)
        }
        databaseWatcher = watcher
        watcher.start()
    }

    private func stopReadingDatabase() {
        databaseWatcher?.stop()
        databaseWatcher = nil
        recentBanners = RecentBanners()
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
        let items = captures.map { capture in
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
        }
        guard databaseWatcher != nil else {
            notificationsArrived(items)
            return
        }
        // A banner NotificationCenter held back past its record's arrival was
        // shown from the database already.
        let unseen = items.filter { !recentBanners.claimShown($0, now: now) }
        if unseen.count < items.count {
            Logger.notifications.notice("\(items.count - unseen.count) banners were shown from the database already")
        }
        for item in unseen {
            recentBanners.add(item, now: now)
        }
        if !unseen.isEmpty {
            notificationsArrived(unseen)
        }
    }

    /// Lists the records that no banner shown lately stands for, and shows the
    /// newest beside the notch. Records a Focus held back, and those of apps
    /// whose alert style is None, are left out, as their banners would have been.
    private func recordsArrived(_ records: [DatabaseNotification]) {
        let now = Date()
        var items: [NotificationItem] = []
        var matched = 0
        var heldBack = 0
        var bannerless = 0
        for record in records where record.hasContent {
            if record.isHeldBack {
                heldBack += 1
                continue
            }
            if !record.showsBanner {
                bannerless += 1
                continue
            }
            let app = Self.app(bundleIdentifier: record.bundleIdentifier)
            if recentBanners.claim(record, appName: app.name, now: now) {
                matched += 1
                continue
            }
            recentBanners.addShown(record, appName: app.name, now: now)
            items.append(NotificationItem(
                token: "database-\(record.recordID)",
                appName: app.name,
                bundleIdentifier: app.bundleIdentifier ?? record.bundleIdentifier,
                appURL: app.url,
                title: record.title,
                subtitle: record.subtitle,
                body: record.body,
                received: record.delivered
            ))
        }
        let apps = items.map { $0.appName ?? "unknown app" }.joined(separator: ", ")
        Logger.notifications.notice(
            "Database: \(records.count) new records, \(matched) already shown from banners, \(heldBack) held back by Focus, \(bannerless) from apps without banners, \(items.count) shown [\(apps, privacy: .public)]"
        )
        if !items.isEmpty {
            notificationsArrived(items)
        }
    }

    /// The installed app with this bundle identifier (which the database may have
    /// lowercased), named as the system names it.
    private static func app(bundleIdentifier: String) -> (name: String?, bundleIdentifier: String?, url: URL?) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return (nil, nil, nil)
        }
        let name = FileManager.default.displayName(atPath: url.path)
        return (
            name.hasSuffix(".app") ? String(name.dropLast(4)) : name,
            // Not `Bundle(url:)`, which keeps every bundle it opens for the rest of the launch.
            NotificationAppResolver.infoPlist(of: url)?["CFBundleIdentifier"] as? String,
            url
        )
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

import AppKit
import ApplicationServices

/// Watches NotificationCenter's banners through Accessibility and reports each
/// new one (`BannerScan`), and, while `hidesBanners` is on, moves the windows of
/// new banners off screen until they are gone (`BannerParking`). Needs
/// Accessibility access; without it NotificationCenter's tree reads as empty.
///
/// NotificationCenter is a process like any other, so the watcher follows the
/// workspace's running applications: while it is not running the watcher waits
/// for it, and when it quits (or crashes) everything read from it is dropped,
/// its windows and elements having died with it. The workspace's launch and
/// termination notifications would not do: macOS posts none for apps without a
/// Dock icon (`LSUIElement`), which NotificationCenter is.
///
/// While a window is parked, its home position is also kept in the user
/// defaults, so that a Notch killed meanwhile (no chance to move it back) moves
/// it back the next time it attaches.
@MainActor
final class NotificationBannerWatcher {
    nonisolated static let bundleIdentifier = "com.apple.notificationcenterui"
    /// How long one Accessibility request to NotificationCenter may block the main
    /// thread when it hangs, in seconds.
    nonisolated static let messagingTimeout: Float = 0.25
    /// A second scan after a burst of events, for banners still being built
    /// when the first one ran.
    static let settleDelay: Duration = .milliseconds(150)
    /// A NotificationCenter that just launched may not answer Accessibility yet.
    static let attachRetryInterval: Duration = .seconds(1)
    static let attachAttempts = 10
    /// Moving a window back that failed is tried again, this often and this many
    /// times in all.
    static let restoreRetryInterval: TimeInterval = 0.5
    static let restoreAttempts = 5
    static let parkedHomeKey = "NotchParkedBannerHome"

    private static let appNotifications = [
        "AXWindowCreated", "AXCreated", "AXUIElementDestroyed", "AXChildrenChanged", "AXLayoutChanged",
    ]
    /// Windows post no "AXWindowCreated" of their own.
    private static let windowNotifications = appNotifications.filter { $0 != "AXWindowCreated" }

    /// A window whose move back failed, waiting for the next try.
    private struct PendingRestore {
        var window: AXUIElement
        var position: CGPoint
        var triesLeft: Int
        var nextTry: Date
    }

    /// Turning it off moves every parked window back at once; turning it on
    /// affects banners that arrive afterwards.
    var hidesBanners = false {
        didSet {
            if !hidesBanners, oldValue {
                restoreAllWindows()
                scheduleParkingTimer()
            }
        }
    }

    private let defaults: UserDefaults
    private let onBanners: @MainActor ([BannerCapture]) -> Void
    private var runningObservation: NSKeyValueObservation?
    private var processID: pid_t?
    /// The process an attach retry is waiting for.
    private var pendingAttachProcessID: pid_t?
    private var application: AXUIElement?
    private var observer: AXObserver?
    private var runLoopSource: CFRunLoopSource?
    /// Windows with their own notifications registered, by window key.
    private var observedWindows: [Int: AXUIElement] = [:]
    private var seen = SeenBanners()
    private var parking = BannerParking()
    /// The elements of the windows in `parking`, by window key.
    private var parkedWindows: [Int: AXUIElement] = [:]
    private var pendingRestores: [Int: PendingRestore] = [:]
    /// A move back ran out of tries: the stored home stays for the next attach.
    private var hasStrandedWindow = false
    /// What `parkedHomeKey` holds, so it is written only when it changes.
    private var storedHome: CGPoint?
    /// Each banner token of the last scan, with its window key.
    private var liveTokens: [String: Int] = [:]
    /// Windows of the last scan that show an alert, which are never parked.
    private var blockedWindows: Set<Int> = []
    private var scanTask: Task<Void, Never>?
    private var settleTask: Task<Void, Never>?
    private var attachTask: Task<Void, Never>?
    private var parkingTimer: Task<Void, Never>?

    init(defaults: UserDefaults, onBanners: @escaping @MainActor ([BannerCapture]) -> Void) {
        self.defaults = defaults
        self.onBanners = onBanners
        if let stored = defaults.array(forKey: Self.parkedHomeKey) as? [Double], stored.count == 2 {
            storedHome = CGPoint(x: stored[0], y: stored[1])
        }
    }

    isolated deinit {
        stop()
    }

    var isRunning: Bool { runningObservation != nil }

    func start() {
        guard runningObservation == nil else { return }
        runningObservation = NSWorkspace.shared.observe(\.runningApplications, options: [.initial, .new]) {
            [weak self] _, _ in
            // KVO may call on any thread; follow on the main actor.
            Task { @MainActor in
                self?.runningApplicationsChanged()
            }
        }
    }

    /// Stops watching and moves every parked window back.
    func stop() {
        runningObservation?.invalidate()
        runningObservation = nil
        detach(isAlive: true)
    }

    // MARK: Observing

    /// Detaches from a NotificationCenter that is gone and attaches to one that runs.
    private func runningApplicationsChanged() {
        guard isRunning else { return }
        let running = Self.runningNotificationCenters()
        if let processID, !running.contains(processID) {
            detach(isAlive: false)
        }
        if let pending = pendingAttachProcessID, !running.contains(pending) {
            attachTask?.cancel()
            attachTask = nil
            pendingAttachProcessID = nil
        }
        guard application == nil, pendingAttachProcessID == nil, let processID = running.first else { return }
        attach(to: processID, attemptsLeft: Self.attachAttempts)
    }

    private static func runningNotificationCenters() -> [pid_t] {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .filter { !$0.isTerminated }
            .map(\.processIdentifier)
    }

    private func attach(to processID: pid_t, attemptsLeft: Int) {
        guard isRunning, application == nil else { return }
        attachTask?.cancel()
        attachTask = nil
        pendingAttachProcessID = nil

        let application = AXUIElementCreateApplication(processID)
        AXUIElementSetMessagingTimeout(application, Self.messagingTimeout)
        var created: AXObserver?
        // The C callback cannot capture context, so `self` travels as an unretained
        // pointer. This is safe because `detach` (called at the latest from deinit)
        // removes the observer's source before `self` is freed.
        let status = AXObserverCreate(processID, { _, element, notification, context in
            guard let context else { return }
            // The observer's source is added to the main run loop below, so the
            // callback always runs on the main thread.
            MainActor.assumeIsolated {
                Unmanaged<NotificationBannerWatcher>.fromOpaque(context).takeUnretainedValue()
                    .received(notification as String, from: element)
            }
        }, &created)
        guard status == .success, let observer = created else {
            retryAttach(to: processID, attemptsLeft: attemptsLeft)
            return
        }
        let context = Unmanaged.passUnretained(self).toOpaque()
        var isRegistered = false
        for name in Self.appNotifications
        where AXObserverAddNotification(observer, application, name as CFString, context) == .success {
            isRegistered = true
        }
        guard isRegistered else {
            retryAttach(to: processID, attemptsLeft: attemptsLeft)
            return
        }
        let source = AXObserverGetRunLoopSource(observer)
        // Common modes so banners are also caught while a menu or drag is tracking.
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        self.processID = processID
        self.application = application
        self.observer = observer
        runLoopSource = source
        recoverStrandedWindows()
        scan()
    }

    private func retryAttach(to processID: pid_t, attemptsLeft: Int) {
        guard attemptsLeft > 1 else { return }
        pendingAttachProcessID = processID
        attachTask = Task { [weak self] in
            try? await Task.sleep(for: Self.attachRetryInterval)
            guard !Task.isCancelled, let self else { return }
            attachTask = nil
            pendingAttachProcessID = nil
            // The process may have gone while this waited.
            guard Self.runningNotificationCenters().contains(processID) else { return }
            attach(to: processID, attemptsLeft: attemptsLeft - 1)
        }
    }

    /// Drops the observer and everything read from NotificationCenter. While it
    /// is alive, the registrations are removed and parked windows moved back
    /// first; once it is gone, there is nothing left to write to.
    private func detach(isAlive: Bool) {
        attachTask?.cancel()
        attachTask = nil
        pendingAttachProcessID = nil
        scanTask?.cancel()
        scanTask = nil
        settleTask?.cancel()
        settleTask = nil
        parkingTimer?.cancel()
        parkingTimer = nil
        if isAlive {
            restoreAllWindows()
            // No time left to try failed moves again; the stored home lets the
            // next attach move them back.
            if !pendingRestores.isEmpty {
                hasStrandedWindow = true
            }
        } else {
            parking = BannerParking()
            parkedWindows = [:]
            // Its windows died with it, wherever they were.
            hasStrandedWindow = false
        }
        pendingRestores = [:]
        persistHome()
        if let observer {
            if isAlive {
                for element in observedWindows.values {
                    for name in Self.windowNotifications {
                        AXObserverRemoveNotification(observer, element, name as CFString)
                    }
                }
                if let application {
                    for name in Self.appNotifications {
                        AXObserverRemoveNotification(observer, application, name as CFString)
                    }
                }
            }
            if let runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            }
        }
        observer = nil
        runLoopSource = nil
        application = nil
        processID = nil
        observedWindows = [:]
        seen = SeenBanners()
        liveTokens = [:]
        blockedWindows = []
    }

    private func received(_ notification: String, from element: AXUIElement) {
        guard application != nil else { return }
        // A destroyed element cannot be read; a created window is not a panel yet.
        if notification != "AXWindowCreated", notification != "AXUIElementDestroyed",
           BannerScan.isPanelOrWidget(AXNode(element)) {
            return
        }
        scheduleScan()
    }

    /// Scans on the next turn of the main queue, once for any number of events
    /// until then, and again `settleDelay` later.
    private func scheduleScan() {
        if scanTask == nil {
            scanTask = Task { [weak self] in
                guard !Task.isCancelled, let self else { return }
                scanTask = nil
                scan()
            }
        }
        if settleTask == nil {
            settleTask = Task { [weak self] in
                try? await Task.sleep(for: Self.settleDelay)
                guard !Task.isCancelled, let self else { return }
                settleTask = nil
                scan()
            }
        }
    }

    // MARK: Scanning

    private func scan() {
        guard let application, let windows = AXNode(application).windows else { return }
        var captures: [BannerCapture] = []
        var watchedWindows: [AXNode] = []
        var windowsByKey: [Int: AXUIElement] = [:]
        for window in windows {
            let result = BannerScan.scan(window: window)
            if !result.isPanelOrWidget {
                watchedWindows.append(window)
            }
            if case .banners(let banners) = result {
                captures += banners
                windowsByKey[window.nodeKey] = window.element
            }
        }
        observeWindows(watchedWindows)

        var identities: Set<String> = []
        captures = captures.filter { identities.insert($0.identity).inserted }
        let newCaptures = seen.update(captures)
        liveTokens = Dictionary(captures.map { ($0.token, $0.windowKey) }, uniquingKeysWith: { first, _ in first })
        blockedWindows = Set(captures.filter { !$0.isParkable }.map(\.windowKey))
        if hidesBanners {
            park(newCaptures, windows: windowsByKey)
        }
        updateParking()

        let reported = newCaptures.filter(\.hasContent)
        if !reported.isEmpty {
            onBanners(reported)
        }
    }

    /// Registers the notifications on windows that appeared and removes them from
    /// windows that went away (or turned into a panel).
    private func observeWindows(_ windows: [AXNode]) {
        guard let observer else { return }
        let current = Dictionary(windows.map { ($0.nodeKey, $0.element) }, uniquingKeysWith: { first, _ in first })
        for (key, element) in observedWindows where current[key] == nil {
            for name in Self.windowNotifications {
                AXObserverRemoveNotification(observer, element, name as CFString)
            }
        }
        let context = Unmanaged.passUnretained(self).toOpaque()
        for (key, element) in current where observedWindows[key] == nil {
            for name in Self.windowNotifications {
                AXObserverAddNotification(observer, element, name as CFString, context)
            }
        }
        observedWindows = current
    }

    // MARK: Parking

    /// Parks the windows of new banners, except those that also show an alert.
    private func park(_ captures: [BannerCapture], windows: [Int: AXUIElement]) {
        let now = Date()
        for capture in captures where capture.isParkable && parking.canPark(capture.token) {
            let key = capture.windowKey
            if parking.join(capture.token, window: key, at: now, blocked: blockedWindows) { continue }
            // A window that cannot be read or moved stays where it is, as does one
            // still waiting to be moved back or already off screen (its position is
            // no home); its banner is still mirrored.
            guard
                !blockedWindows.contains(key),
                pendingRestores[key] == nil,
                let window = windows[key],
                let position = Self.position(of: window),
                BannerParking.isHome(position),
                Self.move(window, to: BannerParking.parkingPosition)
            else { continue }
            parking.park(capture.token, window: key, savedPosition: position, at: now, blocked: blockedWindows)
            parkedWindows[key] = window
        }
    }

    /// Moves back the windows whose banners are gone, that show an alert, or
    /// whose time is up, tries failed moves again, and waits for what is next.
    private func updateParking() {
        let now = Date()
        moveBack(parking.update(live: liveTokens, blocked: blockedWindows, at: now), at: now)
        retryPendingRestores(at: now)
        scheduleParkingTimer()
    }

    private func restoreAllWindows() {
        let now = Date()
        moveBack(parking.restoreAll(), at: now)
        parkedWindows = [:]
        persistHome()
    }

    /// Moves windows back; one that does not move waits in `pendingRestores`.
    private func moveBack(_ windows: [Int: CGPoint], at now: Date) {
        for (key, position) in windows {
            guard let window = parkedWindows.removeValue(forKey: key) else { continue }
            if !Self.move(window, to: position) {
                pendingRestores[key] = PendingRestore(
                    window: window,
                    position: position,
                    triesLeft: Self.restoreAttempts - 1,
                    nextTry: now.addingTimeInterval(Self.restoreRetryInterval)
                )
            }
        }
        persistHome()
    }

    private func retryPendingRestores(at now: Date) {
        for (key, pending) in pendingRestores where pending.nextTry <= now {
            if Self.move(pending.window, to: pending.position) {
                pendingRestores[key] = nil
            } else if pending.triesLeft <= 1 {
                pendingRestores[key] = nil
                hasStrandedWindow = true
            } else {
                pendingRestores[key]?.triesLeft -= 1
                pendingRestores[key]?.nextTry = now.addingTimeInterval(Self.restoreRetryInterval)
            }
        }
        persistHome()
    }

    /// Wakes `updateParking` at the next timeout, end of a restore delay, or retry.
    private func scheduleParkingTimer() {
        parkingTimer?.cancel()
        parkingTimer = nil
        let deadlines = [parking.nextDeadline].compactMap { $0 } + pendingRestores.values.map(\.nextTry)
        guard let deadline = deadlines.min() else { return }
        parkingTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(deadline.timeIntervalSinceNow, 0)))
            guard !Task.isCancelled, let self else { return }
            parkingTimer = nil
            updateParking()
        }
    }

    /// Keeps the latest home of a window that is off screen in the user defaults,
    /// and removes it once none is.
    private func persistHome() {
        let home = parking.latestSavedPosition ?? pendingRestores.values.first?.position
        if let home {
            guard home != storedHome else { return }
            defaults.set([Double(home.x), Double(home.y)], forKey: Self.parkedHomeKey)
            storedHome = home
        } else if !hasStrandedWindow, storedHome != nil {
            defaults.removeObject(forKey: Self.parkedHomeKey)
            storedHome = nil
        }
    }

    /// Moves windows a previous run left off screen back to the stored home.
    private func recoverStrandedWindows() {
        guard let home = storedHome, let application, let windows = AXNode(application).windows else { return }
        var positions: [Int: CGPoint] = [:]
        var elements: [Int: AXUIElement] = [:]
        for window in windows {
            guard let position = Self.position(of: window.element) else { continue }
            positions[window.nodeKey] = position
            elements[window.nodeKey] = window.element
        }
        for key in BannerParking.windowsToRecover(positions: positions, home: home) {
            if let window = elements[key] {
                Self.move(window, to: home)
            }
        }
        hasStrandedWindow = false
        persistHome()
    }

    private static func position(of window: AXUIElement) -> CGPoint? {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(window, "AXPosition" as CFString, &value) == .success,
            let value,
            CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }
        var point = CGPoint.zero
        // Checked to be an AXValue just above.
        guard AXValueGetValue(unsafeDowncast(value, to: AXValue.self), .cgPoint, &point) else { return nil }
        return point
    }

    @discardableResult
    private static func move(_ window: AXUIElement, to position: CGPoint) -> Bool {
        var position = position
        guard let value = AXValueCreate(.cgPoint, &position) else { return false }
        return AXUIElementSetAttributeValue(window, "AXPosition" as CFString, value) == .success
    }
}

/// An element of NotificationCenter's tree for `BannerScan`. The attributes every
/// node is asked for come in one request, on first use; the rest only when asked.
final class AXNode: BannerNode {
    let element: AXUIElement
    let nodeKey: Int
    private var common: [String: AnyObject]?

    private static let commonAttributes = ["AXRole", "AXSubrole", "AXIdentifier", "AXChildren", "AXOrderedChildren"]

    init(_ element: AXUIElement) {
        self.element = element
        nodeKey = Int(bitPattern: CFHash(element))
        // Set per element: a hung NotificationCenter then blocks each request for
        // at most this long, whichever element it is about. A local call, no request.
        AXUIElementSetMessagingTimeout(element, NotificationBannerWatcher.messagingTimeout)
    }

    var role: String? { commonValue("AXRole") as? String }
    var subrole: String? { commonValue("AXSubrole") as? String }
    var identifier: String? { commonValue("AXIdentifier") as? String }
    var stackingIdentifier: String? { copy("AXStackingIdentifier") as? String }
    var value: String? { copy("AXValue") as? String }

    var attributedDescription: String? {
        switch copy("AXAttributedDescription") {
        case let text as String: text
        case let text as NSAttributedString: text.string
        default: nil
        }
    }

    var children: [AXNode] {
        let elements = Self.elements(commonValue("AXChildren")) + Self.elements(commonValue("AXOrderedChildren"))
        return elements.map(AXNode.init)
    }

    /// "AXWindows" of an application element; `nil` when it cannot be read.
    var windows: [AXNode]? {
        guard let value = copy("AXWindows") else { return nil }
        return Self.elements(value).map(AXNode.init)
    }

    private func commonValue(_ attribute: String) -> AnyObject? {
        if common == nil {
            var values: CFArray?
            let names = Self.commonAttributes as CFArray
            var read: [String: AnyObject] = [:]
            if AXUIElementCopyMultipleAttributeValues(element, names, AXCopyMultipleAttributeOptions(rawValue: 0), &values)
                == .success, let values = values as? [AnyObject] {
                // Attributes the element lacks come back as AXValues holding an error.
                for (name, value) in zip(Self.commonAttributes, values) where !Self.isError(value) {
                    read[name] = value
                }
            }
            common = read
        }
        return common?[attribute]
    }

    private func copy(_ attribute: String) -> AnyObject? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    private static func isError(_ value: AnyObject) -> Bool {
        CFGetTypeID(value) == AXValueGetTypeID() && AXValueGetType(unsafeDowncast(value, to: AXValue.self)) == .axError
    }

    private static func elements(_ value: AnyObject?) -> [AXUIElement] {
        guard let array = value as? [AnyObject] else { return [] }
        return array.compactMap { item in
            CFGetTypeID(item) == AXUIElementGetTypeID() ? unsafeDowncast(item, to: AXUIElement.self) : nil
        }
    }
}

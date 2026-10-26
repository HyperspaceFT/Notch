import Foundation

/// Which of NotificationCenter's windows Notch has moved off screen ("parked")
/// to hide their banners, and where each goes back to. Only the bookkeeping:
/// `NotificationBannerWatcher` reads and writes the positions.
///
/// A window is parked for the banners (tokens) it shows. It goes back
/// `restoreDelay` after none of them is live any more, so the outgoing banner
/// finishes sliding out unseen, and in any case `maximumDuration` after the
/// latest new banner joined it, so a stream of banners keeps it parked; a banner
/// still live then is not parked again, so a banner that lingers (or a token
/// NotificationCenter reuses) cannot keep a window off screen. A window that also shows an alert ("blocked", see
/// `BannerCapture.isParkable`) is never parked and goes back at once.
struct BannerParking {
    struct Window: Equatable {
        /// Where the window was before it was moved.
        var savedPosition: CGPoint
        var parkedAt: Date
        /// When the latest new banner was parked in it or joined it, which its
        /// timeout counts from.
        var lastBannerAt: Date
        var tokens: Set<String>
        /// When its last live token went; `nil` while one is live.
        var emptySince: Date?
    }

    static let maximumDuration: TimeInterval = 8
    static let restoreDelay: TimeInterval = 0.35
    /// Where parked windows go: off every screen.
    static let parkingPosition = CGPoint(x: -10_000, y: -10_000)

    /// Parked windows by window key (`CFHash` of the window element).
    private(set) var windows: [Int: Window] = [:]
    /// Tokens whose window went back at the timeout while they were live.
    private(set) var released: Set<String> = []

    func canPark(_ token: String) -> Bool {
        !released.contains(token)
    }

    func isParked(window: Int) -> Bool {
        windows[window] != nil
    }

    /// Whether `position` may be kept as a window's home. A window already at
    /// `parkingPosition` was left there (by a restore that failed, or a Notch that
    /// was killed); saving that would park it for good.
    static func isHome(_ position: CGPoint) -> Bool {
        position != parkingPosition
    }

    /// The windows, among those at `positions`, to move to `home` after a restart:
    /// those left at `parkingPosition`. None without a stored home.
    static func windowsToRecover(positions: [Int: CGPoint], home: CGPoint?) -> [Int] {
        guard home != nil else { return [] }
        return positions.filter { $0.value == parkingPosition }.map(\.key).sorted()
    }

    /// The next time `update` has something to do on its own: a window reaching
    /// its timeout or the end of its restore delay.
    var nextDeadline: Date? {
        windows.values.flatMap { window in
            [window.lastBannerAt.addingTimeInterval(Self.maximumDuration)]
                + (window.emptySince.map { [$0.addingTimeInterval(Self.restoreDelay)] } ?? [])
        }.min()
    }

    /// The saved position of the window parked last, which a relaunched Notch
    /// moves stranded windows back to.
    var latestSavedPosition: CGPoint? {
        windows.values.max { $0.parkedAt < $1.parkedAt }?.savedPosition
    }

    /// Records that `window`, showing `token`, was moved away from `savedPosition`.
    /// Refused (`false`) for a blocked window or a position that is no home.
    @discardableResult
    mutating func park(
        _ token: String,
        window: Int,
        savedPosition: CGPoint,
        at date: Date,
        blocked: Set<Int> = []
    ) -> Bool {
        guard !blocked.contains(window), Self.isHome(savedPosition) else { return false }
        windows[window] = Window(savedPosition: savedPosition, parkedAt: date, lastBannerAt: date, tokens: [token])
        return true
    }

    /// Adds the new banner `token` to a window that is already parked, also
    /// during its restore delay, keeping the window's saved position and starting
    /// its timeout over. `false` when the window is not parked or is blocked.
    @discardableResult
    mutating func join(_ token: String, window: Int, at date: Date, blocked: Set<Int> = []) -> Bool {
        guard windows[window] != nil, !blocked.contains(window) else { return false }
        windows[window]?.tokens.insert(token)
        windows[window]?.lastBannerAt = date
        windows[window]?.emptySince = nil
        return true
    }

    /// Follows the banners of the latest scan, `live` mapping each token to its
    /// window, and returns the windows to move back, with their saved positions.
    /// `blocked` windows go back at once.
    mutating func update(live: [String: Int], blocked: Set<Int> = [], at now: Date) -> [Int: CGPoint] {
        var restored: [Int: CGPoint] = [:]
        for (key, window) in windows {
            let liveTokens = window.tokens.filter { live[$0] == key }
            if blocked.contains(key) {
                restored[key] = window.savedPosition
                windows[key] = nil
            } else if now.timeIntervalSince(window.lastBannerAt) >= Self.maximumDuration {
                restored[key] = window.savedPosition
                released.formUnion(liveTokens)
                windows[key] = nil
            } else if liveTokens.isEmpty {
                // The tokens stay, so one that comes back keeps the window parked.
                let emptySince = window.emptySince ?? now
                if now.timeIntervalSince(emptySince) >= Self.restoreDelay {
                    restored[key] = window.savedPosition
                    windows[key] = nil
                } else {
                    windows[key]?.emptySince = emptySince
                }
            } else {
                windows[key]?.tokens = liveTokens
                windows[key]?.emptySince = nil
            }
        }
        released = released.filter { live[$0] != nil }
        return restored
    }

    /// Forgets everything and returns every parked window with its saved position.
    mutating func restoreAll() -> [Int: CGPoint] {
        let restored = windows.mapValues(\.savedPosition)
        windows = [:]
        released = []
        return restored
    }
}

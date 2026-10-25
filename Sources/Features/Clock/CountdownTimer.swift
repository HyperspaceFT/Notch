import Foundation

/// One countdown: how long it was set for and where it stands, running toward an
/// end date or paused with some time left. Every reading and change takes the
/// moment it applies to, so it can be checked against any clock.
struct CountdownTimer: Equatable, Sendable {
    enum State: Equatable, Sendable {
        case running(endDate: Date)
        case paused(remaining: TimeInterval)
    }

    /// Minutes the tab's picker goes from and to, in steps of one (`MinuteRuler`).
    /// It starts at 0, the ruler's natural end, though a 0-minute timer cannot start.
    static let setterMinutes = 0...120

    /// Seconds the timer was set for, plus every minute added since.
    private(set) var total: TimeInterval
    private(set) var state: State

    init(duration: TimeInterval, startingAt now: Date) {
        total = duration
        state = .running(endDate: now.addingTimeInterval(duration))
    }

    var isPaused: Bool {
        if case .paused = state { return true }
        return false
    }

    /// When the timer runs out; `nil` while paused.
    var endDate: Date? {
        if case .running(let endDate) = state { return endDate }
        return nil
    }

    /// Seconds left at `now`, never below zero.
    func remaining(at now: Date) -> TimeInterval {
        switch state {
        case .running(let endDate): max(endDate.timeIntervalSince(now), 0)
        case .paused(let remaining): max(remaining, 0)
        }
    }

    /// The share of `total` still left at `now`: 1 when started, 0 when finished.
    func progress(at now: Date) -> Double {
        guard total > 0 else { return 0 }
        return min(remaining(at: now) / total, 1)
    }

    func isFinished(at now: Date) -> Bool {
        remaining(at: now) <= 0
    }

    mutating func pause(at now: Date) {
        guard case .running = state else { return }
        state = .paused(remaining: remaining(at: now))
    }

    mutating func resume(at now: Date) {
        guard case .paused(let remaining) = state else { return }
        state = .running(endDate: now.addingTimeInterval(remaining))
    }

    /// Extends the timer, and what it was set for, by `seconds`.
    mutating func add(_ seconds: TimeInterval, at now: Date) {
        total += seconds
        switch state {
        case .running(let endDate):
            // An end already past (one not yet noticed) counts from now.
            state = .running(endDate: max(endDate, now).addingTimeInterval(seconds))
        case .paused(let remaining):
            state = .paused(remaining: max(remaining, 0) + seconds)
        }
    }

    /// `remaining` as the timer shows it: rounded up to whole seconds, so a fresh
    /// five-minute timer reads "5:00" and a second later "4:59"; "m:ss" under an
    /// hour, "h:mm:ss" from one.
    static func display(_ remaining: TimeInterval) -> String {
        let seconds = Int(max(remaining, 0).rounded(.up))
        let hours = seconds / 3600
        let minutes = seconds / 60 % 60
        let rest = seconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, rest)
        }
        return String(format: "%d:%02d", minutes, rest)
    }

    /// `minutes` kept within `setterMinutes`.
    static func clampedSetterMinutes(_ minutes: Int) -> Int {
        min(max(minutes, setterMinutes.lowerBound), setterMinutes.upperBound)
    }
}

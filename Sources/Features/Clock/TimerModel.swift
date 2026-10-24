import AppKit
import Foundation
import Observation

/// The countdown timer, one at a time and in memory only: idle, counting down
/// (running or paused), or finished and sounding its alert until dismissed.
/// The views observe it; `ClockFeature` follows its events to show the wings.
@MainActor
@Observable
final class TimerModel {
    enum Phase: Equatable {
        case idle
        case counting(CountdownTimer)
        /// Ran out after `total` seconds; the alert stays until dismissed.
        case finished(total: TimeInterval)
    }

    enum Event {
        /// A timer started (or started again).
        case started
        /// The running timer ran out.
        case finished
        /// The timer was cancelled or its alert dismissed.
        case ended
    }

    static let lastMinutesKey = "NotchClockTimerMinutes"
    static let defaultMinutes = 5
    /// The alert sound plays this many times at most, `alertInterval` apart.
    static let alertRepeats = 5
    static let alertInterval: Duration = .seconds(3)

    private(set) var phase = Phase.idle
    /// The panel setter's value: the last started duration until changed there.
    private(set) var setterMinutes: Int

    /// Called after every phase change the wings follow.
    @ObservationIgnored var onEvent: ((Event) -> Void)?

    @ObservationIgnored private let defaults: UserDefaults
    /// Wakes when the running timer is due; cancelled whenever it stops running.
    @ObservationIgnored private var finishTask: Task<Void, Never>?
    /// Repeats the alert sound while the finished timer is not dismissed.
    @ObservationIgnored private var alertTask: Task<Void, Never>?
    @ObservationIgnored private var sound: NSSound?

    init(defaults: UserDefaults) {
        self.defaults = defaults
        let saved = defaults.integer(forKey: Self.lastMinutesKey)
        setterMinutes = saved > 0 ? CountdownTimer.clampedSetterMinutes(saved) : Self.defaultMinutes
    }

    // MARK: Setter

    func adjustSetter(by minutes: Int) {
        setterMinutes = CountdownTimer.clampedSetterMinutes(setterMinutes + minutes)
    }

    // MARK: Actions

    func start(minutes: Int, now: Date = Date()) {
        start(duration: TimeInterval(minutes * 60), now: now)
    }

    /// Starts a timer for `duration` seconds, replacing whatever ran or sounded
    /// before, and remembers it, in whole minutes, as the setter's next value.
    func start(duration: TimeInterval, now: Date = Date()) {
        stopAlert(notifying: false)
        let minutes = CountdownTimer.clampedSetterMinutes(Int((duration / 60).rounded()))
        setterMinutes = minutes
        defaults.set(minutes, forKey: Self.lastMinutesKey)
        phase = .counting(CountdownTimer(duration: duration, startingAt: now))
        scheduleFinish()
        onEvent?(.started)
    }

    func togglePause(now: Date = Date()) {
        guard case .counting(var timer) = phase else { return }
        if timer.isPaused {
            timer.resume(at: now)
        } else {
            // Already run out, its finish task not yet run: ring rather than
            // stay paused at 0:00.
            guard !timer.isFinished(at: now) else {
                finish()
                return
            }
            timer.pause(at: now)
        }
        phase = .counting(timer)
        scheduleFinish()
    }

    func addMinute(now: Date = Date()) {
        guard case .counting(var timer) = phase else { return }
        timer.add(60, at: now)
        phase = .counting(timer)
        scheduleFinish()
    }

    func cancel() {
        guard case .counting = phase else { return }
        finishTask?.cancel()
        finishTask = nil
        phase = .idle
        onEvent?(.ended)
    }

    /// Starts again for what the timer was last set for, counting or finished.
    func restart(now: Date = Date()) {
        switch phase {
        case .idle: return
        case .counting(let timer): start(duration: timer.total, now: now)
        case .finished(let total): start(duration: total, now: now)
        }
    }

    /// Silences and dismisses the finished timer's alert.
    func stopAlert() {
        stopAlert(notifying: true)
    }

    /// Back to idle without events, silencing everything; for deactivation.
    func reset() {
        finishTask?.cancel()
        finishTask = nil
        stopSound()
        phase = .idle
    }

    // MARK: Finishing

    /// Sleeps until the running timer's end, then checks the wall clock again,
    /// since the sleep may end early or late (e.g. across the Mac sleeping).
    private func scheduleFinish() {
        finishTask?.cancel()
        finishTask = nil
        guard case .counting(let timer) = phase, let endDate = timer.endDate else { return }
        finishTask = Task { [weak self] in
            while !Task.isCancelled {
                let wait = endDate.timeIntervalSinceNow
                guard wait > 0 else {
                    self?.finish()
                    return
                }
                try? await Task.sleep(for: .seconds(wait))
            }
        }
    }

    private func finish() {
        guard case .counting(let timer) = phase, timer.isFinished(at: Date()) else { return }
        finishTask = nil
        phase = .finished(total: timer.total)
        playAlert()
        onEvent?(.finished)
    }

    private func stopAlert(notifying: Bool) {
        guard case .finished = phase else { return }
        stopSound()
        phase = .idle
        if notifying {
            onEvent?(.ended)
        }
    }

    private func playAlert() {
        stopSound()
        alertTask = Task { [weak self] in
            for index in 0..<Self.alertRepeats {
                if index > 0 {
                    try? await Task.sleep(for: Self.alertInterval)
                }
                guard !Task.isCancelled, let self else { return }
                sound?.stop()
                sound = NSSound(named: "Glass")
                sound?.play()
            }
            self?.alertTask = nil
        }
    }

    private func stopSound() {
        alertTask?.cancel()
        alertTask = nil
        sound?.stop()
        sound = nil
    }
}

import Foundation
import Testing
@testable import ClockFeature

private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

private func at(_ seconds: TimeInterval) -> Date {
    start.addingTimeInterval(seconds)
}

struct CountdownTimerTests {
    @Test func startsRunningForTheWholeDuration() {
        let timer = CountdownTimer(duration: 300, startingAt: start)
        #expect(!timer.isPaused)
        #expect(timer.total == 300)
        #expect(timer.endDate == at(300))
        #expect(timer.remaining(at: start) == 300)
        #expect(timer.remaining(at: at(120)) == 180)
        #expect(timer.progress(at: start) == 1)
        #expect(timer.progress(at: at(150)) == 0.5)
    }

    @Test func remainingNeverGoesBelowZero() {
        let timer = CountdownTimer(duration: 60, startingAt: start)
        #expect(timer.remaining(at: at(60)) == 0)
        #expect(timer.remaining(at: at(500)) == 0)
        #expect(timer.progress(at: at(500)) == 0)
    }

    @Test func pauseThenResumeKeepsTheTimeLeft() {
        var timer = CountdownTimer(duration: 300, startingAt: start)
        timer.pause(at: at(100))
        #expect(timer.isPaused)
        #expect(timer.endDate == nil)
        // Paused time does not count.
        #expect(timer.remaining(at: at(1000)) == 200)
        timer.resume(at: at(1000))
        #expect(!timer.isPaused)
        #expect(timer.remaining(at: at(1000)) == 200)
        #expect(timer.endDate == at(1200))
    }

    @Test func addingWhileRunningExtendsTheTimeLeftAndTheTotal() {
        var timer = CountdownTimer(duration: 300, startingAt: start)
        timer.add(60, at: at(100))
        #expect(timer.total == 360)
        #expect(timer.remaining(at: at(100)) == 260)
        #expect(timer.endDate == at(360))
    }

    @Test func addingWhilePausedExtendsTheTimeLeftAndTheTotal() {
        var timer = CountdownTimer(duration: 300, startingAt: start)
        timer.pause(at: at(100))
        timer.add(60, at: at(150))
        #expect(timer.isPaused)
        #expect(timer.total == 360)
        #expect(timer.remaining(at: at(500)) == 260)
    }

    @Test func isFinishedAtAndAfterTheEnd() {
        let timer = CountdownTimer(duration: 300, startingAt: start)
        #expect(!timer.isFinished(at: at(299.9)))
        #expect(timer.isFinished(at: at(300)))
        #expect(timer.isFinished(at: at(301)))
    }

    @Test func displaysTheTimeLeftRoundedUpToWholeSeconds() {
        #expect(CountdownTimer.display(300) == "5:00")
        #expect(CountdownTimer.display(299.2) == "5:00")
        #expect(CountdownTimer.display(299.0) == "4:59")
        #expect(CountdownTimer.display(0) == "0:00")
        #expect(CountdownTimer.display(3600) == "1:00:00")
        #expect(CountdownTimer.display(3899) == "1:04:59")
    }

    @Test func setterStaysWithinZeroToOneHundredTwentyMinutes() {
        #expect(CountdownTimer.setterMinutes == 0...120)
        #expect(CountdownTimer.clampedSetterMinutes(-5) == 0)
        #expect(CountdownTimer.clampedSetterMinutes(0) == 0)
        #expect(CountdownTimer.clampedSetterMinutes(1) == 1)
        #expect(CountdownTimer.clampedSetterMinutes(25) == 25)
        #expect(CountdownTimer.clampedSetterMinutes(120) == 120)
        #expect(CountdownTimer.clampedSetterMinutes(121) == 120)
        #expect(CountdownTimer.clampedSetterMinutes(180) == 120)
    }
}

@MainActor
struct TimerModelTests {
    @Test func setterStartsAtFiveMinutesAndStaysInRange() throws {
        let suite = "TimerModelTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = TimerModel(defaults: defaults)
        #expect(model.setterMinutes == 5)
        model.selectSetter(-3)
        #expect(model.setterMinutes == 0)
        model.selectSetter(42)
        #expect(model.setterMinutes == 42)
        model.selectSetter(200)
        #expect(model.setterMinutes == 120)
    }

    @Test func aRememberedDurationAboveTheRangeOpensAtItsTop() throws {
        let suite = "TimerModelTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        // Saved while the setter still went to 180 minutes.
        defaults.set(150, forKey: TimerModel.lastMinutesKey)
        #expect(TimerModel(defaults: defaults).setterMinutes == 120)
        defaults.set(90, forKey: TimerModel.lastMinutesKey)
        #expect(TimerModel(defaults: defaults).setterMinutes == 90)
    }

    @Test func remembersTheLastStartedDuration() throws {
        let suite = "TimerModelTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = TimerModel(defaults: defaults)
        model.start(minutes: 25)
        model.cancel()
        #expect(model.phase == .idle)
        #expect(TimerModel(defaults: defaults).setterMinutes == 25)
    }
}

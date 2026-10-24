import Foundation
import Testing
@testable import ClockFeature

@MainActor
struct TimerModelRememberedDurationTests {
    /// A defaults domain of its own, empty, so nothing else is read or written.
    private func makeDefaults() throws -> UserDefaults {
        let name = "TimerModelTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func aNormalStartRemembersItsMinutes() throws {
        let defaults = try makeDefaults()
        let model = TimerModel(defaults: defaults)
        model.start(minutes: 25)
        #expect(defaults.integer(forKey: TimerModel.lastMinutesKey) == 25)
        #expect(model.setterMinutes == 25)
        model.reset()
    }

    @Test func aStartNotRememberedLeavesTheSavedMinutesAndSetterAlone() throws {
        let defaults = try makeDefaults()
        let model = TimerModel(defaults: defaults)
        model.start(minutes: 25)
        model.start(duration: 10, remembering: false)
        #expect(defaults.integer(forKey: TimerModel.lastMinutesKey) == 25)
        #expect(model.setterMinutes == 25)
        guard case .counting(let timer) = model.phase else {
            Issue.record("expected a counting timer")
            return
        }
        #expect(timer.total == 10)
        model.reset()
    }

    @Test func aStartNotRememberedSavesNothingWhenNothingWasSaved() throws {
        let defaults = try makeDefaults()
        let model = TimerModel(defaults: defaults)
        model.start(duration: 65 * 60, remembering: false)
        #expect(defaults.object(forKey: TimerModel.lastMinutesKey) == nil)
        #expect(model.setterMinutes == TimerModel.defaultMinutes)
        model.reset()
    }

    @Test func restartingAnUnrememberedTimerStaysUnremembered() throws {
        let defaults = try makeDefaults()
        let model = TimerModel(defaults: defaults)
        model.start(duration: 5 * 60, remembering: false)
        model.restart()
        #expect(defaults.object(forKey: TimerModel.lastMinutesKey) == nil)
        // A normal start after it remembers again, and restarts with it.
        model.start(minutes: 10)
        model.restart()
        #expect(defaults.integer(forKey: TimerModel.lastMinutesKey) == 10)
        model.reset()
    }
}

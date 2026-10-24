import Foundation
import Testing
@testable import ClockFeature

struct MinuteRulerTests {
    @Test func theSelectedMinuteIsTheNearestWholeOneOnTheRuler() {
        #expect(MinuteRuler.minute(at: 25) == 25)
        #expect(MinuteRuler.minute(at: 24.6) == 25)
        #expect(MinuteRuler.minute(at: 24.4) == 24)
        #expect(MinuteRuler.minute(at: -3) == 0)
        #expect(MinuteRuler.minute(at: 130) == 120)
    }

    @Test func ticksMovingLeftBringLargerMinutesUnderTheCenter() {
        let spacing = MinuteRuler.spacing
        #expect(MinuteRuler.position(25, movedBy: -2 * spacing) == 27)
        #expect(MinuteRuler.position(25, movedBy: spacing) == 24)
        #expect(MinuteRuler.position(25, movedBy: -spacing / 2) == 25.5)
    }

    @Test func theRulerStopsAtZeroAndOneHundredTwenty() {
        let spacing = MinuteRuler.spacing
        #expect(MinuteRuler.position(119, movedBy: -10 * spacing) == 120)
        #expect(MinuteRuler.position(2, movedBy: 10 * spacing) == 0)
    }

    @Test func aClickSelectsTheTickUnderThePointer() {
        let spacing = MinuteRuler.spacing
        #expect(MinuteRuler.minute(atOffset: 0, from: 25) == 25)
        #expect(MinuteRuler.minute(atOffset: 3 * spacing, from: 25) == 28)
        #expect(MinuteRuler.minute(atOffset: -3 * spacing, from: 25) == 22)
        // Closer to the selected tick than to its neighbour.
        #expect(MinuteRuler.minute(atOffset: 0.4 * spacing, from: 25) == 25)
        #expect(MinuteRuler.minute(atOffset: 200 * spacing, from: 25) == 120)
    }

    @Test func theSelectedTickStandsTallestAndTheOthersEaseBackToNormal() {
        let radius = MinuteRuler.falloffRadius
        #expect(MinuteRuler.emphasis(distance: 0) == 1)
        #expect(MinuteRuler.emphasis(distance: radius) == 0)
        #expect(MinuteRuler.emphasis(distance: radius + 3) == 0)
        // The same either side, and lower with each tick away.
        var previous = 1.0
        for distance in 1...Int(radius) {
            let emphasis = MinuteRuler.emphasis(distance: Double(distance))
            #expect(emphasis == MinuteRuler.emphasis(distance: -Double(distance)))
            #expect(emphasis < previous)
            previous = emphasis
        }
        // Gradual, over several ticks each side.
        #expect(radius >= 4 && radius <= 6)
        #expect(MinuteRuler.emphasis(distance: 1) > 0.5)
    }

    @Test func tickHeights() {
        #expect(MinuteRuler.height(ofTick: 25, position: 25) == MinuteRuler.selectedTickHeight)
        #expect(MinuteRuler.height(ofTick: 25, position: 25 - MinuteRuler.falloffRadius) == MinuteRuler.tickHeight)
        #expect(MinuteRuler.height(ofTick: 26, position: 25) < MinuteRuler.selectedTickHeight)
        #expect(MinuteRuler.height(ofTick: 26, position: 25) > MinuteRuler.tickHeight)
        // Every ten minutes a slightly taller tick, still below the selected one.
        #expect(MinuteRuler.height(ofTick: 60, position: 25) == MinuteRuler.majorTickHeight)
        #expect(MinuteRuler.majorTickHeight > MinuteRuler.tickHeight)
        #expect(MinuteRuler.majorTickHeight < MinuteRuler.selectedTickHeight)
        // Halfway between two ticks, both stand out equally.
        #expect(MinuteRuler.height(ofTick: 25, position: 25.5) == MinuteRuler.height(ofTick: 26, position: 25.5))
    }

    @Test func ticksDarkenAwayFromTheSelection() {
        // The selected tick is the timer's own orange; the others darken over the
        // falloff, to the same dark orange beyond it whether major or not.
        #expect(MinuteRuler.dimming(ofTick: 25, position: 25) == 0)
        var previous = 0.0
        for minute in 26...30 {
            let dimming = MinuteRuler.dimming(ofTick: minute, position: 25)
            #expect(dimming > previous)
            #expect(dimming == MinuteRuler.dimming(ofTick: 50 - minute, position: 25))
            previous = dimming
        }
        #expect(previous == MinuteRuler.farTickDimming)
        #expect(MinuteRuler.dimming(ofTick: 60, position: 25) == MinuteRuler.farTickDimming)
        // Dark, but still orange rather than black.
        #expect(MinuteRuler.farTickDimming > 0.3 && MinuteRuler.farTickDimming < 0.8)
    }
}

@MainActor
struct TimerPickerTests {
    /// A defaults domain of its own, empty, so nothing else is read or written.
    private func makeDefaults() throws -> UserDefaults {
        let name = "TimerPickerTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func opensOnTheRememberedMinutes() throws {
        let defaults = try makeDefaults()
        defaults.set(25, forKey: TimerModel.lastMinutesKey)
        let picker = TimerPicker(model: TimerModel(defaults: defaults))
        #expect(picker.position == 25)
        #expect(picker.model.setterMinutes == 25)
    }

    @Test func movingSelectsTheNearestMinuteAndSettlesOnIt() throws {
        let picker = TimerPicker(model: TimerModel(defaults: try makeDefaults()))
        picker.move(to: 12.3)
        #expect(picker.position == 12.3)
        #expect(picker.model.setterMinutes == 12)
        picker.move(by: -MinuteRuler.spacing)
        #expect(abs(picker.position - 13.3) < 1e-9)
        #expect(picker.model.setterMinutes == 13)
        picker.settle()
        #expect(picker.position == 13)
        #expect(picker.model.setterMinutes == 13)
    }

    @Test func resettingDropsTheMovingPositionAtOnce() throws {
        let picker = TimerPicker(model: TimerModel(defaults: try makeDefaults()))
        picker.move(to: 12.3)
        #expect(picker.position == 12.3)
        picker.reset()
        #expect(picker.position == 12)
        #expect(picker.model.setterMinutes == 12)
        // A later change from outside is not overridden by a leftover fraction.
        picker.move(to: 40.4)
        picker.reset()
        picker.model.selectSetter(15)
        #expect(picker.position == 15)
    }

    @Test func aMinuteSetFromOutsideWinsOverAStaleMovingPosition() throws {
        let picker = TimerPicker(model: TimerModel(defaults: try makeDefaults()))
        picker.move(to: 40.4)
        picker.model.selectSetter(15)
        #expect(picker.position == 15)
        // Moving again starts from the model's minute.
        picker.move(by: -MinuteRuler.spacing / 2)
        #expect(picker.position == 15.5)
    }

    @Test func movingStopsAtTheEnds() throws {
        let picker = TimerPicker(model: TimerModel(defaults: try makeDefaults()))
        picker.move(to: 500)
        #expect(picker.model.setterMinutes == 120)
        picker.move(by: 1000 * MinuteRuler.spacing)
        picker.settle()
        #expect(picker.position == 0)
        #expect(picker.model.setterMinutes == 0)
    }

    @Test func pickingAndSteppingSelectAWholeMinute() throws {
        let picker = TimerPicker(model: TimerModel(defaults: try makeDefaults()))
        picker.pick(30)
        #expect(picker.position == 30)
        picker.step(by: 1)
        #expect(picker.model.setterMinutes == 31)
        picker.step(by: -2)
        #expect(picker.model.setterMinutes == 29)
        picker.pick(-4)
        #expect(picker.model.setterMinutes == 0)
        picker.step(by: -1)
        #expect(picker.model.setterMinutes == 0)
    }

    @Test func movingDoesNotRememberTheMinutesUntilAStart() throws {
        let defaults = try makeDefaults()
        let picker = TimerPicker(model: TimerModel(defaults: defaults))
        picker.pick(42)
        #expect(defaults.object(forKey: TimerModel.lastMinutesKey) == nil)
        picker.model.start(minutes: picker.model.setterMinutes)
        #expect(defaults.integer(forKey: TimerModel.lastMinutesKey) == 42)
        picker.model.reset()
    }
}

@MainActor
struct ClockFeatureTabTests {
    private func makeDefaults() throws -> UserDefaults {
        let name = "ClockFeatureTabTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func theTabIsAlwaysAvailableOnTheRight() throws {
        let feature = ClockFeature(defaults: try makeDefaults())
        #expect(feature.isTabAvailable)
        #expect(feature.tabPlacement == .trailing)
        feature.model.start(minutes: 5)
        #expect(feature.isTabAvailable)
        feature.model.reset()
    }

    @Test func theTabIsActiveOnlyWhileCountingOrRinging() throws {
        let feature = ClockFeature(defaults: try makeDefaults())
        #expect(!feature.isTabActive)
        feature.model.start(minutes: 5)
        #expect(feature.isTabActive)
        feature.model.togglePause()
        #expect(feature.isTabActive)
        feature.model.cancel()
        #expect(!feature.isTabActive)
        feature.model.startFinished()
        #expect(feature.isTabActive)
        feature.model.stopAlert()
        #expect(!feature.isTabActive)
    }
}

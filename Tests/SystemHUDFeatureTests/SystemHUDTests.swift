import Testing
@testable import SystemHUDFeature

struct LevelStepTests {
    @Test func stepsUpToTheNextGridPoint() {
        #expect(LevelStep.up(from: 0.5, step: LevelStep.normal) == 0.5625)
        #expect(LevelStep.up(from: 0.52, step: LevelStep.normal) == 0.5625)
        #expect(LevelStep.up(from: 0.49999, step: LevelStep.normal) == 0.5625)
    }

    @Test func stepsDownToTheNextGridPoint() {
        #expect(LevelStep.down(from: 0.5, step: LevelStep.normal) == 0.4375)
        #expect(LevelStep.down(from: 0.52, step: LevelStep.normal) == 0.5)
    }

    @Test func clampsAtTheEnds() {
        #expect(LevelStep.up(from: 1.0, step: LevelStep.normal) == 1.0)
        #expect(LevelStep.down(from: 0, step: LevelStep.normal) == 0)
    }

    @Test func fineStepIsOneSixtyFourth() {
        #expect(LevelStep.fine == 1.0 / 64)
        #expect(LevelStep.up(from: 0.5, step: LevelStep.fine) == 0.515625)
    }

    @Test func stepsFromTheLastSetLevelWhenTheReadingIsSlightlyOff() {
        // A device that stores 0.0625 as 0.0622 must still move down a step.
        #expect(LevelStep.origin(current: 0.0622, lastSet: 0.0625, step: LevelStep.normal) == 0.0625)
        #expect(LevelStep.down(from: LevelStep.origin(current: 0.063, lastSet: 0.0625, step: LevelStep.normal), step: LevelStep.normal) == 0)
    }

    @Test func stepsFromTheReadingWhenTheLevelChangedElsewhere() {
        #expect(LevelStep.origin(current: 0.3, lastSet: 0.0625, step: LevelStep.normal) == 0.3)
        #expect(LevelStep.origin(current: 0.3, lastSet: nil, step: LevelStep.normal) == 0.3)
    }

    @Test func modifiersPickTheStep() {
        #expect(LevelStep.step(option: false, shift: false) == LevelStep.normal)
        #expect(LevelStep.step(option: false, shift: true) == LevelStep.normal)
        #expect(LevelStep.step(option: true, shift: true) == LevelStep.fine)
        #expect(LevelStep.step(option: true, shift: false) == nil)
    }
}

@MainActor
struct BrightnessIconTests {
    @Test func raysLengthenInThirds() {
        #expect(BrightnessIcon.tier(for: 0) == 0)
        #expect(BrightnessIcon.tier(for: 5.0 / 16) == 0)
        #expect(BrightnessIcon.tier(for: 6.0 / 16) == 1)
        #expect(BrightnessIcon.tier(for: 10.0 / 16) == 1)
        #expect(BrightnessIcon.tier(for: 11.0 / 16) == 2)
        #expect(BrightnessIcon.tier(for: 1) == 2)
    }

    @Test func brighterTiersHaveLongerRays() {
        let lengths = BrightnessIcon.rayLengths
        #expect(lengths.count == 3)
        #expect(lengths[0] < lengths[1] && lengths[1] < lengths[2])
    }
}

struct MediaKeyEventTests {
    @Test func decodesSoundUpDown() {
        #expect(MediaKeyEvent(data1: (0 << 16) | (0x0A << 8)) == MediaKeyEvent(key: .soundUp, isDown: true, isRepeat: false))
    }

    @Test func decodesSoundDownUp() {
        #expect(MediaKeyEvent(data1: (1 << 16) | (0x0B << 8)) == MediaKeyEvent(key: .soundDown, isDown: false, isRepeat: false))
    }

    @Test func decodesMuteRepeat() {
        #expect(MediaKeyEvent(data1: (7 << 16) | (0x0A << 8) | 1) == MediaKeyEvent(key: .mute, isDown: true, isRepeat: true))
    }

    @Test func decodesBrightness() {
        #expect(MediaKeyEvent(data1: (2 << 16) | (0x0A << 8)) == MediaKeyEvent(key: .brightnessUp, isDown: true, isRepeat: false))
        #expect(MediaKeyEvent(data1: (3 << 16) | (0x0B << 8)) == MediaKeyEvent(key: .brightnessDown, isDown: false, isRepeat: false))
    }

    @Test func ignoresOtherKeys() {
        // NX_KEYTYPE_PLAY.
        #expect(MediaKeyEvent(data1: (16 << 16) | (0x0A << 8)) == nil)
    }
}

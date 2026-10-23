import Foundation
import NotchKit
import Testing
@testable import NotchShell

struct SkyLightTests {
    /// Local midnight in Berlin (UTC+2) on 2026-10-22.
    private let midnight = Date(timeIntervalSince1970: 1_792_706_400)
    /// Sunrise at 07:30, sunset at 18:00.
    private var today: SunTimes {
        SunTimes(sunrise: midnight.addingTimeInterval(7.5 * 3600), sunset: midnight.addingTimeInterval(18 * 3600))!
    }

    private func date(at hours: Double) -> Date {
        midnight.addingTimeInterval(hours * 3600)
    }

    private func light(at hours: Double, days: [SunTimes]? = nil) -> SkyLight {
        SkyLight.at(date(at: hours), sunTimes: days ?? [today])
    }

    @Test func withoutSunTimesTheEdgeIsPlain() {
        #expect(SkyLight.at(midnight, sunTimes: []) == .unknown)
    }

    @Test func atNoonTheSunIsHighAtTheBottom() {
        let noon = light(at: 12.75)
        #expect(abs(noon.sun.position - 0.5) < 0.001)
        #expect(noon.sun.strength == 1)
        #expect(difference(noon.sun.color, SkyLight.sunlight) < 0.001)
        #expect(difference(noon.rim, SkyLight.dayRim) < 0.001)
    }

    @Test func atSunriseTheSunIsOrangeOnTheLeft() {
        let sunrise = light(at: 7.5)
        #expect(abs(sunrise.sun.position) < 0.001)
        #expect(sunrise.sun.strength == 1)
        #expect(difference(sunrise.sun.color, SkyLight.horizonOrange) < 0.001)
        #expect(difference(sunrise.rim, SkyLight.twilightRim) < 0.001)
    }

    @Test func atSunsetTheSunIsOrangeOnTheRight() {
        let sunset = light(at: 18)
        #expect(abs(sunset.sun.position - 1) < 0.001)
        #expect(sunset.sun.strength == 1)
        #expect(difference(sunset.sun.color, SkyLight.horizonOrange) < 0.001)
        #expect(difference(sunset.rim, SkyLight.twilightRim) < 0.001)
    }

    @Test func theSunWarmsTowardTheHorizon() {
        let early = light(at: 8.5).sun.color
        let later = light(at: 10).sun.color
        #expect(early.blue < later.blue)
        #expect(early.green < later.green)
    }

    @Test func atNightThereIsOnlyMoonlight() {
        let night = light(at: 23)
        #expect(night.sun.strength == 0)
        let moon = SkyLight.moonRim(illumination: MoonPhase.illumination(at: date(at: 23)))
        #expect(difference(night.rim, moon) < 0.001)
    }

    @Test func aFullerMoonLightsMoreOfTheEdge() {
        let new = SkyLight.moonRim(illumination: 0)
        let full = SkyLight.moonRim(illumination: 1)
        #expect(full.intensity > new.intensity)
        #expect(full.reach > new.reach)
        #expect(full.halo > new.halo)
    }

    @Test func aKnownDayServesTheDaysAround() {
        let yesterday = SunTimes(
            sunrise: today.sunrise.addingTimeInterval(-24 * 3600),
            sunset: today.sunset.addingTimeInterval(-24 * 3600)
        )!
        let sunset = light(at: 18, days: [yesterday])
        #expect(abs(sunset.sun.position - 1) < 0.001)
        #expect(sunset.sun.strength == 1)
    }

    @Test func staleSunTimesAreIgnored() {
        let monthAgo = SunTimes(
            sunrise: today.sunrise.addingTimeInterval(-30 * 24 * 3600),
            sunset: today.sunset.addingTimeInterval(-30 * 24 * 3600)
        )!
        #expect(light(at: 12, days: [monthAgo]) == .unknown)
    }

    /// The cutoff falls at night, so the sun never vanishes in the middle of a day.
    @Test func knownDaysRunOutAtNight() {
        let lastDay = 14 * 24 + 12.75
        #expect(light(at: lastDay).sun.strength == 1)
        #expect(light(at: lastDay + 11).sun.strength == 0)
        #expect(light(at: lastDay + 24) == .unknown)
    }

    @Test func theLightChangesSmoothly() {
        expectSmooth(days: [today])
    }

    @Test func theLightChangesSmoothlyBetweenTwoKnownDays() {
        let tomorrow = SunTimes(
            sunrise: today.sunrise.addingTimeInterval(24 * 3600 + 2 * 60),
            sunset: today.sunset.addingTimeInterval(24 * 3600 - 3 * 60)
        )!
        expectSmooth(days: [today, tomorrow])
    }

    /// A summer night far north: the sun sets at 23:45 and rises at 00:45, so it
    /// still shows when it moves on to the next day.
    @Test func theLightChangesSmoothlyOverAShortNight() {
        let long = SunTimes(sunrise: date(at: 0.75), sunset: date(at: 23.75))!
        expectSmooth(days: [long])
    }

    /// Minute by minute over two days, nothing visible jumps. The sun's position
    /// may jump while it is too faint to see.
    private func expectSmooth(days: [SunTimes]) {
        var rimStep = 0.0
        var strengthStep = 0.0
        var positionStep = 0.0
        var colorStep = 0.0
        var previous = light(at: 0, days: days)
        for minute in 1...(48 * 60) {
            let current = light(at: Double(minute) / 60, days: days)
            rimStep = max(rimStep, difference(previous.rim, current.rim))
            strengthStep = max(strengthStep, abs(previous.sun.strength - current.sun.strength))
            if previous.sun.strength > 0.01, current.sun.strength > 0.01 {
                positionStep = max(positionStep, abs(previous.sun.position - current.sun.position))
                colorStep = max(colorStep, difference(previous.sun.color, current.sun.color))
            }
            previous = current
        }
        #expect(rimStep < 0.05)
        #expect(strengthStep < 0.05)
        #expect(positionStep < 0.01)
        #expect(colorStep < 0.05)
    }

    private func difference(_ a: SkyLight.RGB, _ b: SkyLight.RGB) -> Double {
        max(abs(a.red - b.red), abs(a.green - b.green), abs(a.blue - b.blue))
    }

    private func difference(_ a: SkyLight.Rim, _ b: SkyLight.Rim) -> Double {
        max(
            difference(a.color, b.color),
            abs(a.intensity - b.intensity),
            abs(a.reach - b.reach),
            abs(a.halo - b.halo)
        )
    }
}

struct MoonPhaseTests {
    @Test func newMoonIsDark() {
        // 2024-10-02 18:49 UTC.
        #expect(MoonPhase.illumination(at: Date(timeIntervalSince1970: 1_727_894_940)) < 0.03)
    }

    @Test func fullMoonIsLit() {
        // 2024-10-17 11:26 UTC.
        #expect(MoonPhase.illumination(at: Date(timeIntervalSince1970: 1_729_164_360)) > 0.97)
    }

    @Test func phaseStaysInRangeBeforeTheReference() {
        // 1990-01-01, before the reference new moon.
        let phase = MoonPhase.phase(at: Date(timeIntervalSince1970: 631_152_000))
        #expect(phase >= 0)
        #expect(phase < 1)
    }
}

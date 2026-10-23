import Foundation
import NotchKit
import Testing
@testable import NotchShell

struct SkyLightTests {
    /// Local midnight in Berlin (UTC+2) on 2026-10-23. The clocks there go back
    /// an hour two days later, at the end of the two days `expectSmooth` covers.
    private let midnight = Date(timeIntervalSince1970: 1_792_706_400)
    private let berlin: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }()
    /// Sunrise at 07:30, sunset at 18:00; noon at 12:45, solar midnight at 00:45.
    private var today: SunTimes {
        SunTimes(sunrise: date(at: 7.5), sunset: date(at: 18))!
    }

    private func date(at hours: Double) -> Date {
        midnight.addingTimeInterval(hours * 3600)
    }

    private func light(at hours: Double, days: [SunTimes]? = nil) -> SkyLight {
        SkyLight.at(date(at: hours), sunTimes: days ?? [today], calendar: berlin)
    }

    @Test func atNoonTheSunIsAtTheBottom() {
        let noon = light(at: 12.75)
        #expect(abs(noon.sun.position - 0.5) < 0.001)
        #expect(noon.sun.strength == 1)
        #expect(difference(noon.sun.color, SkyLight.sunlight) < 0.001)
        #expect(noon.moon.strength == 0)
    }

    @Test func atSunriseTheSunIsOrangeOnTheLeft() {
        let sunrise = light(at: 7.5)
        #expect(sunrise.sun.position == 0)
        #expect(sunrise.sun.strength == 1)
        #expect(difference(sunrise.sun.color, SkyLight.horizonOrange) < 0.001)
        // The moon has just finished its path there, on the left.
        #expect(sunrise.moon.position == 1)
        #expect(sunrise.moon.strength == 0)
    }

    @Test func atSunsetTheSunIsOrangeOnTheRight() {
        let sunset = light(at: 18)
        #expect(sunset.sun.position == 1)
        #expect(sunset.sun.strength == 1)
        #expect(difference(sunset.sun.color, SkyLight.horizonOrange) < 0.001)
        // The moon is about to start its path there, on the right.
        #expect(sunset.moon.position == 0)
        #expect(sunset.moon.strength == 0)
    }

    @Test func theSunWarmsTowardTheHorizon() {
        let early = light(at: 8.5).sun.color
        let later = light(at: 10).sun.color
        #expect(early.blue < later.blue)
        #expect(early.green < later.green)
    }

    @Test func atMidnightTheMoonIsAtTheTop() {
        let night = light(at: 24.75)
        #expect(night.sun.strength == 0)
        #expect(abs(night.moon.position - 0.5) < 0.001)
        #expect(night.moon.strength > 0)
        #expect(difference(night.moon.color, SkyLight.moonlight) < 0.001)
    }

    @Test func aFullerMoonIsBrighterAndLarger() {
        // Midnight halfway through a night around each moment.
        func moon(at instant: Date) -> SkyLight.Halo {
            let day = SunTimes(sunrise: instant.addingTimeInterval(6 * 3600), sunset: instant.addingTimeInterval(18 * 3600))!
            return SkyLight.at(instant, sunTimes: [day]).moon
        }
        // New moon 2024-10-02 18:49 UTC, full moon 2024-10-17 11:26 UTC.
        let new = moon(at: Date(timeIntervalSince1970: 1_727_894_940))
        let full = moon(at: Date(timeIntervalSince1970: 1_729_164_360))
        #expect(full.strength > new.strength * 2)
        #expect(full.size > new.size)
    }

    @Test func withoutSunTimesItAssumesSixToSix() {
        let noon = SkyLight.at(date(at: 12), sunTimes: [], calendar: berlin)
        #expect(abs(noon.sun.position - 0.5) < 0.001)
        #expect(noon.sun.strength == 1)
        let sunset = SkyLight.at(date(at: 18), sunTimes: [], calendar: berlin)
        #expect(sunset.sun.position == 1)
        let night = SkyLight.at(date(at: 24), sunTimes: [], calendar: berlin)
        #expect(abs(night.moon.position - 0.5) < 0.001)
    }

    @Test func aKnownDayServesTheDaysAround() {
        let yesterday = SunTimes(
            sunrise: today.sunrise.addingTimeInterval(-24 * 3600),
            sunset: today.sunset.addingTimeInterval(-24 * 3600)
        )!
        let sunset = light(at: 18, days: [yesterday])
        #expect(sunset.sun.position == 1)
        #expect(sunset.sun.strength == 1)
    }

    @Test func staleSunTimesGiveWayToTheAssumedOnes() {
        let monthAgo = SunTimes(
            sunrise: today.sunrise.addingTimeInterval(-30 * 24 * 3600),
            sunset: today.sunset.addingTimeInterval(-30 * 24 * 3600)
        )!
        #expect(light(at: 12, days: [monthAgo]) == light(at: 12, days: []))
    }

    /// The cutoff falls at night, so the sun never jumps in the middle of a day.
    @Test func knownDaysRunOutAtNight() {
        let lastNoon = 14 * 24 + 12.75
        #expect(abs(light(at: lastNoon).sun.position - 0.5) < 0.001)
        #expect(light(at: lastNoon + 11).sun.strength == 0)
        #expect(light(at: lastNoon + 24) == light(at: lastNoon + 24, days: []))
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

    @Test func theLightChangesSmoothlyWithAssumedTimes() {
        expectSmooth(days: [])
    }

    /// Minute by minute over two days, nothing visible jumps. A halo's position
    /// may jump while it is too faint to see. In an hour-long night the moon
    /// crosses the whole top, a sixtieth of its path a minute.
    private func expectSmooth(days: [SunTimes]) {
        var strengthStep = 0.0
        var sizeStep = 0.0
        var positionStep = 0.0
        var colorStep = 0.0
        var previous = light(at: 0, days: days)
        for minute in 1...(48 * 60) {
            let current = light(at: Double(minute) / 60, days: days)
            for (before, after) in [(previous.sun, current.sun), (previous.moon, current.moon)] {
                strengthStep = max(strengthStep, abs(before.strength - after.strength))
                if before.strength > 0.01, after.strength > 0.01 {
                    sizeStep = max(sizeStep, abs(before.size - after.size))
                    positionStep = max(positionStep, abs(before.position - after.position))
                    colorStep = max(colorStep, difference(before.color, after.color))
                }
            }
            previous = current
        }
        #expect(strengthStep < 0.05)
        #expect(sizeStep < 0.05)
        #expect(positionStep < 0.02)
        #expect(colorStep < 0.05)
    }

    private func difference(_ a: SkyLight.RGB, _ b: SkyLight.RGB) -> Double {
        max(abs(a.red - b.red), abs(a.green - b.green), abs(a.blue - b.blue))
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

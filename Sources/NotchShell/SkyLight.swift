import Foundation
import NotchKit

/// The light along the expanded island's edge at one moment.
///
/// By day the sun is a soft band on the edge where it stands in the sky: it
/// rises on the left side, crosses the bottom at noon, and sets on the right,
/// white while it is high and orange near the horizon. At night the whole edge
/// takes moonlight, brighter and higher up the sides the fuller the moon. Around
/// sunrise and sunset the edge glows orange, and day and night ease into each
/// other. Pure, so it can be tested without a window.
struct SkyLight: Equatable, Sendable {
    /// A color, components 0…1.
    struct RGB: Equatable, Sendable {
        var red: Double
        var green: Double
        var blue: Double
    }

    /// The even light along the whole edge.
    struct Rim: Equatable, Sendable {
        var color: RGB
        /// Opacity at the bottom of the island.
        var intensity: Double
        /// How far up the sides it climbs, as a share of the island's height.
        var reach: Double
        /// Strength of a soft halo inside it, 0…1.
        var halo: Double
    }

    /// The sun: a soft band of light on the edge.
    struct Sun: Equatable, Sendable {
        /// Along the edge from where it rises (0, the left side) to where it sets
        /// (1, the right side); a little outside that during twilight.
        var position: Double
        var color: RGB
        /// 0 at night, 1 by day.
        var strength: Double
    }

    var rim: Rim
    var sun: Sun

    static let sunlight = RGB(red: 1, green: 0.96, blue: 0.88)
    static let horizonOrange = RGB(red: 1, green: 0.55, blue: 0.2)

    /// The edge by day, under the sun's band.
    static let dayRim = Rim(color: RGB(red: 1, green: 1, blue: 1), intensity: 0.1, reach: 0.7, halo: 0)
    /// The edge around sunrise and sunset.
    static let twilightRim = Rim(color: RGB(red: 1, green: 0.62, blue: 0.3), intensity: 0.28, reach: 0.78, halo: 0.45)

    /// The edge by night under a moon `illumination` lit (0 new, 1 full).
    static func moonRim(illumination: Double) -> Rim {
        let lit = min(max(illumination, 0), 1)
        return Rim(
            color: RGB(red: 0.74, green: 0.82, blue: 1),
            intensity: 0.05 + 0.23 * lit,
            reach: 0.25 + 0.5 * lit,
            halo: 0.35 * lit
        )
    }

    /// Without sun times: an even white edge and no sun.
    static let unknown = SkyLight(
        rim: Rim(color: RGB(red: 1, green: 1, blue: 1), intensity: 0.16, reach: 0.7, halo: 0),
        sun: Sun(position: 0.5, color: sunlight, strength: 0)
    )

    /// How long before and after sunrise and sunset the edge glows, and day and
    /// night ease into each other.
    static let twilight: TimeInterval = 45 * 60
    /// How many days from the nearest known day a moment may be: sunrise and
    /// sunset move by a few minutes a day at most, so a known day serves for a
    /// while.
    static let maximumAge = 14.0

    /// The light at `date`, with the sun at the times `sunTimes` gives (see
    /// `solarDay(near:in:)`); `unknown` without a day near enough.
    static func at(_ date: Date, sunTimes: [SunTimes]) -> SkyLight {
        guard let day = solarDay(near: date, in: sunTimes) else { return .unknown }
        let oneDay: TimeInterval = 24 * 3600
        // 1 between sunrise and sunset, 0 at night, easing across twilight.
        let daylight = rise(date, around: day.sunrise) * (1 - rise(date, around: day.sunset))
        // 1 at sunrise and sunset, 0 from `twilight` away. The neighbouring days'
        // events count too, for short nights.
        let events = [day.sunset - oneDay, day.sunrise, day.sunset, day.sunrise + oneDay]
        let glow = events.map { 1 - smoothstep(abs(date.timeIntervalSince($0)) / twilight) }.max() ?? 0

        let rim = moonRim(illumination: MoonPhase.illumination(at: date))
            .mixed(with: dayRim, by: daylight)
            .mixed(with: twilightRim, by: glow)

        let position = date.timeIntervalSince(day.sunrise) / day.sunset.timeIntervalSince(day.sunrise)
        // How high the sun stands: 0 on the horizon, 1 at noon.
        let height = sin(.pi * min(max(position, 0), 1))
        // Halfway between two noons the sun moves on to the next day, from the
        // right end of the edge to the left. Only a night shorter than twice
        // `twilight` still shows it then, so it fades out across the switch.
        let untilNextDay = oneDay / 2 - abs(date.timeIntervalSince(day.noon))
        let sun = Sun(
            // Past either end it fades out by strength before it leaves the
            // edge; the bound only matters for days of a few hours.
            position: min(max(position, -0.2), 1.2),
            color: horizonOrange.mixed(with: sunlight, by: smoothstep(height / 0.6)),
            strength: max(daylight, glow) * smoothstep(untilNextDay / twilight)
        )
        return SkyLight(rim: rim, sun: sun)
    }

    /// The known day whose noon is nearest `date`, moved to `date`'s own day by
    /// whole days; `nil` when that is more than `maximumAge` days away. The
    /// cutoff falls halfway between two noons, at night, not in the middle of a day.
    static func solarDay(near date: Date, in sunTimes: [SunTimes]) -> (sunrise: Date, sunset: Date, noon: Date)? {
        guard let nearest = sunTimes.min(by: {
            abs(noon(of: $0).timeIntervalSince(date)) < abs(noon(of: $1).timeIntervalSince(date))
        }) else { return nil }
        let oneDay: TimeInterval = 24 * 3600
        let days = (date.timeIntervalSince(noon(of: nearest)) / oneDay).rounded()
        guard abs(days) <= maximumAge else { return nil }
        let shift = days * oneDay
        return (
            nearest.sunrise.addingTimeInterval(shift),
            nearest.sunset.addingTimeInterval(shift),
            noon(of: nearest).addingTimeInterval(shift)
        )
    }

    private static func noon(of day: SunTimes) -> Date {
        day.sunrise.addingTimeInterval(day.sunset.timeIntervalSince(day.sunrise) / 2)
    }

    /// 0 until `twilight` before `event`, 1 from `twilight` after it, easing between.
    private static func rise(_ date: Date, around event: Date) -> Double {
        smoothstep((date.timeIntervalSince(event) + twilight) / (2 * twilight))
    }

    private static func smoothstep(_ x: Double) -> Double {
        let t = min(max(x, 0), 1)
        return t * t * (3 - 2 * t)
    }
}

/// `amount` of the way from `a` to `b`.
private func mix(_ a: Double, _ b: Double, by amount: Double) -> Double {
    a + (b - a) * amount
}

extension SkyLight.RGB {
    func mixed(with other: Self, by amount: Double) -> Self {
        Self(
            red: mix(red, other.red, by: amount),
            green: mix(green, other.green, by: amount),
            blue: mix(blue, other.blue, by: amount)
        )
    }
}

extension SkyLight.Rim {
    func mixed(with other: Self, by amount: Double) -> Self {
        Self(
            color: color.mixed(with: other.color, by: amount),
            intensity: mix(intensity, other.intensity, by: amount),
            reach: mix(reach, other.reach, by: amount),
            halo: mix(halo, other.halo, by: amount)
        )
    }
}

/// The moon's phase, from the mean length of a lunar month. It can be off by
/// about half a day, which is close enough for how brightly it lights the island.
enum MoonPhase {
    /// Mean time from one new moon to the next.
    static let synodicMonth: TimeInterval = 29.530588853 * 24 * 3600
    /// A new moon: 2000-01-06 18:14 UTC.
    static let referenceNewMoon = Date(timeIntervalSince1970: 947_182_440)

    /// 0 at new moon, 0.5 at full moon, nearing 1 before the next new moon.
    static func phase(at date: Date) -> Double {
        let cycles = date.timeIntervalSince(referenceNewMoon) / synodicMonth
        return cycles - cycles.rounded(.down)
    }

    /// The lit share of the moon's disc: 0 at new moon, 1 at full moon.
    static func illumination(at date: Date) -> Double {
        (1 - cos(2 * .pi * phase(at: date))) / 2
    }
}

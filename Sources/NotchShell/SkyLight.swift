import Foundation
import NotchKit

/// The light on the expanded island's edge at one moment: a soft halo for the
/// sun by day and one for the moon by night, so the light goes once around the
/// island a day.
///
/// The sun rises on the left side, crosses the bottom at noon, and sets on the
/// right, white while it is high and orange near the horizon. The moon takes
/// over at sunset: up the right side, across the top from right to left (partly
/// behind the camera housing around midnight), and down the left side by
/// sunrise, brighter and larger the fuller it is. Across twilight one fades into
/// the other. Pure, so it can be tested without a window.
struct SkyLight: Equatable, Sendable {
    /// A color, components 0…1.
    struct RGB: Equatable, Sendable {
        var red: Double
        var green: Double
        var blue: Double
    }

    /// A soft halo on the island's edge.
    struct Halo: Equatable, Sendable {
        /// How far along its path, 0…1. The sun's path runs left to right around
        /// the bottom, the moon's right to left across the top.
        var position: Double
        var color: RGB
        /// How strongly it shows, 0…1.
        var strength: Double
        /// Its size, as a share of the largest.
        var size: Double
    }

    var sun: Halo
    var moon: Halo

    /// The sun's times around one day.
    struct SolarDay: Equatable, Sendable {
        var sunrise: Date
        var sunset: Date
        /// Halfway between sunrise and sunset.
        var noon: Date
        var previousSunset: Date
        var nextSunrise: Date
    }

    static let sunlight = RGB(red: 1, green: 0.96, blue: 0.88)
    static let horizonOrange = RGB(red: 1, green: 0.55, blue: 0.2)
    static let moonlight = RGB(red: 0.74, green: 0.82, blue: 1)

    /// How long before and after sunrise and sunset the sun glows larger and
    /// orange, and the sun and moon fade into each other.
    static let twilight: TimeInterval = 45 * 60
    /// How many days from the nearest known day a moment may be: sunrise and
    /// sunset move by a few minutes a day at most, so a known day serves for a
    /// while.
    static let maximumAge = 14.0
    /// The hours of sunrise and sunset assumed without a known day near enough.
    static let assumedSunrise = 6
    static let assumedSunset = 18

    /// The light at `date`, with the sun at the times `sunTimes` gives (see
    /// `solarDay(near:in:)`), or at `assumedSunrise` and `assumedSunset` in
    /// `calendar` without a known day near enough.
    static func at(_ date: Date, sunTimes: [SunTimes], calendar: Calendar = .current) -> SkyLight {
        let day = solarDay(near: date, in: sunTimes) ?? assumedDay(around: date, calendar: calendar)
        let oneDay: TimeInterval = 24 * 3600
        // 1 between sunrise and sunset, 0 at night, easing across twilight.
        let daylight = rise(date, around: day.sunrise) * (1 - rise(date, around: day.sunset))
        // 1 at sunrise and sunset, 0 from `twilight` away. The neighbouring days'
        // events count too, for short nights.
        let events = [day.previousSunset, day.sunrise, day.sunset, day.nextSunrise]
        let glow = events.map { 1 - smoothstep(abs(date.timeIntervalSince($0)) / twilight) }.max() ?? 0
        // The sun shows all day and around sunrise and sunset; the moon the rest.
        let sunShare = max(daylight, glow)

        let position = date.timeIntervalSince(day.sunrise) / day.sunset.timeIntervalSince(day.sunrise)
        // How high the sun stands: 0 on the horizon, 1 at noon.
        let height = sin(.pi * min(max(position, 0), 1))
        // Halfway between two noons the sun moves on to the next day, from the
        // right end of its path to the left. Only a night shorter than twice
        // `twilight` still shows it then, so it fades out across the switch.
        let untilNextDay = oneDay / 2 - abs(date.timeIntervalSince(day.noon))
        let sun = Halo(
            position: min(max(position, 0), 1),
            color: horizonOrange.mixed(with: sunlight, by: smoothstep(height / 0.6)),
            strength: sunShare * smoothstep(untilNextDay / twilight),
            size: 0.85 + 0.15 * glow
        )

        // The night the moon crosses: before noon the one ending at this
        // sunrise, after noon the one starting at this sunset. It switches at
        // noon, while the moon does not show.
        let night = date < day.noon
            ? (start: day.previousSunset, end: day.sunrise)
            : (start: day.sunset, end: day.nextSunrise)
        let lit = MoonPhase.illumination(at: date)
        let moon = Halo(
            position: min(max(date.timeIntervalSince(night.start) / night.end.timeIntervalSince(night.start), 0), 1),
            color: moonlight,
            strength: (1 - sunShare) * (0.25 + 0.75 * lit),
            size: 0.6 + 0.4 * lit
        )
        return SkyLight(sun: sun, moon: moon)
    }

    /// The known day whose noon is nearest `date`, moved to `date`'s own day by
    /// whole days; `nil` when that is more than `maximumAge` days away. The
    /// cutoff falls halfway between two noons, at night, not in the middle of a day.
    static func solarDay(near date: Date, in sunTimes: [SunTimes]) -> SolarDay? {
        guard let nearest = sunTimes.min(by: {
            abs(noon(of: $0).timeIntervalSince(date)) < abs(noon(of: $1).timeIntervalSince(date))
        }) else { return nil }
        let oneDay: TimeInterval = 24 * 3600
        let days = (date.timeIntervalSince(noon(of: nearest)) / oneDay).rounded()
        guard abs(days) <= maximumAge else { return nil }
        // The sun keeps absolute time, so whole days of seconds, clock changes or not.
        let shift = days * oneDay
        let sunrise = nearest.sunrise.addingTimeInterval(shift)
        let sunset = nearest.sunset.addingTimeInterval(shift)
        return SolarDay(
            sunrise: sunrise,
            sunset: sunset,
            noon: noon(of: nearest).addingTimeInterval(shift),
            previousSunset: sunset - oneDay,
            nextSunrise: sunrise + oneDay
        )
    }

    /// `assumedSunrise` to `assumedSunset` on `date`'s day in `calendar`. These
    /// are clock times, so the neighbouring days' come from the calendar too: a
    /// clock change makes a day an hour longer or shorter.
    static func assumedDay(around date: Date, calendar: Calendar) -> SolarDay {
        func at(_ hour: Int, daysFrom offset: Int = 0) -> Date {
            let day = calendar.date(byAdding: .day, value: offset, to: date) ?? date
            return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
        }
        return SolarDay(
            sunrise: at(assumedSunrise),
            sunset: at(assumedSunset),
            noon: at((assumedSunrise + assumedSunset) / 2),
            previousSunset: at(assumedSunset, daysFrom: -1),
            nextSunrise: at(assumedSunrise, daysFrom: 1)
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

extension SkyLight.RGB {
    /// `amount` of the way from this color to `other`.
    func mixed(with other: Self, by amount: Double) -> Self {
        func mix(_ a: Double, _ b: Double) -> Double { a + (b - a) * amount }
        return Self(red: mix(red, other.red), green: mix(green, other.green), blue: mix(blue, other.blue))
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

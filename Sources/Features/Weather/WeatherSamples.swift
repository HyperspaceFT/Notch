import Foundation

/// Sample reports for the Debug pane, plausible for the condition they show.
enum WeatherSample {
    /// A report of `condition` now and through today and tomorrow: every hour
    /// of both days, and both days' summaries, so each of the module's modes has
    /// data. All of it is `isDay` as asked, so the choice shows in every column.
    /// Has no sun times, so nothing reaches `Daylight`.
    static func report(
        for condition: WeatherCondition,
        isDay: Bool,
        now: Date,
        calendar: Calendar = .current
    ) -> WeatherReport {
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today.addingTimeInterval(86_400)
        let mean = meanTemperature(of: condition)
        let chance = precipitationChance(of: condition)

        func hours(from start: Date) -> [WeatherReport.Reading] {
            (0..<24).map { hour in
                WeatherReport.Reading(
                    time: start.addingTimeInterval(TimeInterval(hour) * 3600),
                    temperature: temperature(mean: mean, hour: Double(hour)),
                    condition: condition,
                    isDay: isDay
                )
            }
        }
        func day(from start: Date, meanShift: Double) -> WeatherReport.Day {
            WeatherReport.Day(
                start: start,
                condition: condition,
                high: round1(mean + meanShift + swing),
                low: round1(mean + meanShift - swing),
                precipitationChance: chance
            )
        }

        let components = calendar.dateComponents([.hour, .minute], from: now)
        let hourOfDay = Double(components.hour ?? 0) + Double(components.minute ?? 0) / 60
        return WeatherReport(
            current: WeatherReport.Reading(
                time: now,
                temperature: temperature(mean: mean, hour: hourOfDay),
                condition: condition,
                isDay: isDay
            ),
            hours: hours(from: today) + hours(from: tomorrow),
            days: [day(from: today, meanShift: 0), day(from: tomorrow, meanShift: -1)]
        )
    }

    /// Half the day's span in degrees Celsius: the curve peaks at 15:00.
    private static let swing = 3.0

    private static func temperature(mean: Double, hour: Double) -> Double {
        round1(mean + swing * cos((hour - 15) / 24 * 2 * .pi))
    }

    private static func round1(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }

    /// The day's mean in degrees Celsius: below freezing all day for snow and
    /// the freezing kinds.
    private static func meanTemperature(of condition: WeatherCondition) -> Double {
        switch condition {
        case .clear, .mostlyClear, .thunderstorms: 24
        case .partlyCloudy, .thunderstormsWithHail: 21
        case .cloudy, .unknown, .showers: 18
        case .fog: 10
        case .drizzle, .lightRain: 15
        case .rain, .heavyShowers: 14
        case .heavyRain: 13
        case .freezingDrizzle, .lightSnow, .snowGrains: -4
        case .freezingRain, .snow, .snowShowers: -5
        case .heavySnow: -7
        }
    }

    /// Percent: high for anything that precipitates.
    private static func precipitationChance(of condition: WeatherCondition) -> Int {
        switch condition {
        case .clear, .mostlyClear: 0
        case .partlyCloudy, .cloudy, .unknown: 10
        case .fog: 20
        case .drizzle, .freezingDrizzle: 55
        case .lightRain, .lightSnow, .snowGrains: 65
        case .rain, .snow, .showers, .freezingRain, .snowShowers: 80
        case .heavyRain, .heavySnow, .heavyShowers, .thunderstorms, .thunderstormsWithHail: 90
        }
    }
}

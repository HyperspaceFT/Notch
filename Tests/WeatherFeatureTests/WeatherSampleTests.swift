import Foundation
import Testing
@testable import WeatherFeature

private let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    return calendar
}()

/// Thursday 22 October 2026, 14:30 UTC.
private let now = Date(timeIntervalSince1970: 1_792_679_400)

private func sample(_ condition: WeatherCondition, isDay: Bool = true) -> WeatherReport {
    WeatherSample.report(for: condition, isDay: isDay, now: now, calendar: utc)
}

struct WeatherSampleTests {
    @Test func theReportShowsTheConditionAndDaylightAsAsked() {
        for condition in WeatherCondition.allCases {
            for isDay in [true, false] {
                let report = sample(condition, isDay: isDay)
                #expect(report.current.condition == condition)
                #expect(report.current.isDay == isDay)
                #expect(report.current.time == now)
                #expect(report.hours.allSatisfy { $0.condition == condition && $0.isDay == isDay })
                #expect(report.days.allSatisfy { $0.condition == condition })
            }
        }
    }

    @Test func theReportHasNoSunTimesSoDaylightIsLeftAlone() {
        #expect(WeatherCondition.allCases.allSatisfy { sample($0).sunTimes.isEmpty })
    }

    @Test func todayAndTomorrowAreThereWithAllTheirHours() throws {
        let report = sample(.rain)
        let today = try #require(report.today)
        let tomorrow = try #require(report.tomorrow)
        #expect(today.start == utc.startOfDay(for: now))
        #expect(tomorrow.start == utc.date(byAdding: .day, value: 1, to: today.start))
        #expect(report.hours.count == 48)
        #expect(report.hours.first?.time == today.start)
        #expect(report.hours.last?.time == tomorrow.start.addingTimeInterval(23 * 3600))
        // Every mode has its columns: the day's named hours, and hours still to come.
        #expect(report.hours(on: today, count: 4).count == 4)
        #expect(report.hours(on: tomorrow, count: 4).count == 4)
        #expect(report.upcomingHours(after: now).count >= 24)
    }

    @Test func theDaysHighsAndLowsSpanTheirTemperatures() throws {
        let report = sample(.partlyCloudy)
        for day in report.days {
            #expect(day.high > day.low)
        }
        let today = try #require(report.today)
        let temperatures = report.hours.prefix(24).map(\.temperature)
        #expect(temperatures.max().map { $0 <= today.high } == true)
        #expect(temperatures.min().map { $0 >= today.low } == true)
    }

    @Test func snowAndTheFreezingKindsAreBelowFreezingThroughout() {
        let cold: [WeatherCondition] = [
            .freezingDrizzle, .freezingRain, .lightSnow, .snow, .heavySnow, .snowGrains, .snowShowers,
        ]
        for condition in cold {
            let report = sample(condition)
            let temperatures = [report.current.temperature]
                + report.hours.map(\.temperature)
                + report.days.flatMap { [$0.high, $0.low] }
            #expect(temperatures.allSatisfy { $0 < 0 })
        }
    }

    @Test func rainKindsLikelyRainAndFairWeatherNot() {
        let wet: [WeatherCondition] = [.lightRain, .rain, .heavyRain, .showers, .heavyShowers, .thunderstorms]
        for condition in wet {
            #expect(sample(condition).days.allSatisfy { ($0.precipitationChance ?? 0) >= 60 })
        }
        #expect(sample(.clear).days.allSatisfy { ($0.precipitationChance ?? 0) <= 10 })
    }
}

@MainActor
struct WeatherModelSampleTests {
    @Test func aSampleReportIsReadyAndAStatusHasNoReport() {
        let model = WeatherModel()
        let report = sample(.snow)
        model.showSample(report)
        #expect(model.status == .ready)
        #expect(model.report == report)
        model.showStatus(.locationNotAllowed)
        #expect(model.status == .locationNotAllowed)
        #expect(model.report == nil)
        model.showStatus(.failed)
        #expect(model.status == .failed)
        model.showStatus(.loading)
        #expect(model.status == .loading)
    }
}

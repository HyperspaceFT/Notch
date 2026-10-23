import Foundation
import NotchKit
import Testing
@testable import WeatherFeature

/// A real Open-Meteo response for Berlin, fetched when "now" was 1792714199.
private let sampleResponse = """
{"latitude":52.512604,"longitude":13.419517,"generationtime_ms":0.22101402282714844,"utc_offset_seconds":7200,"timezone":"Europe/Berlin","timezone_abbreviation":"GMT+2","elevation":38.0,"current_units":{"time":"unixtime","interval":"seconds","temperature_2m":"°C","weather_code":"wmo code","is_day":""},"current":{"time":1792713600,"interval":900,"temperature_2m":9.7,"weather_code":3,"is_day":0},"hourly_units":{"time":"unixtime","temperature_2m":"°C","weather_code":"wmo code","is_day":""},"hourly":{"time":[1792713600,1792717200,1792720800,1792724400],"temperature_2m":[9.7,9.2,8.7,8.3],"weather_code":[3,2,2,2],"is_day":[0,0,0,0]},"daily_units":{"time":"unixtime","temperature_2m_max":"°C","temperature_2m_min":"°C"},"daily":{"time":[1792706400,1792792800],"temperature_2m_max":[14.7,11.8],"temperature_2m_min":[6.9,6.6]}}
"""

/// A real response for the same place to the current query: two days of daily
/// values and hourly readings from today's local midnight, fetched at 1792716300.
private let twoDayResponse = """
{"latitude":52.512604,"longitude":13.419517,"generationtime_ms":0.39839744567871094,"utc_offset_seconds":7200,"timezone":"Europe/Berlin","timezone_abbreviation":"GMT+2","elevation":38.0,"current_units":{"time":"unixtime","interval":"seconds","temperature_2m":"°C","weather_code":"wmo code","is_day":""},"current":{"time":1792716300,"interval":900,"temperature_2m":9.2,"weather_code":0,"is_day":0},"hourly_units":{"time":"unixtime","temperature_2m":"°C","weather_code":"wmo code","is_day":""},"hourly":{"time":[1792706400,1792710000,1792713600,1792717200,1792720800,1792724400,1792728000,1792731600,1792735200,1792738800,1792742400,1792746000,1792749600,1792753200,1792756800,1792760400,1792764000,1792767600,1792771200,1792774800,1792778400,1792782000,1792785600,1792789200,1792792800,1792796400,1792800000,1792803600,1792807200,1792810800,1792814400,1792818000,1792821600,1792825200,1792828800,1792832400,1792836000,1792839600,1792843200,1792846800,1792850400,1792854000,1792857600,1792861200,1792864800,1792868400,1792872000,1792875600],"temperature_2m":[10.6,10.1,9.5,9.1,8.6,8.3,7.9,7.5,6.9,7.0,8.3,9.9,11.9,13.3,14.4,14.4,14.5,14.1,13.5,12.8,12.0,11.2,11.1,11.1,11.3,11.2,10.6,10.6,10.0,9.6,9.3,9.2,9.1,9.4,9.6,9.0,8.8,8.9,9.8,10.8,11.5,11.8,11.6,11.1,10.5,9.6,8.7,7.7],"weather_code":[2,2,3,0,2,2,3,0,1,2,3,3,3,3,3,3,3,61,61,3,80,3,3,3,3,2,2,2,2,2,2,2,3,3,3,61,61,61,61,3,3,3,3,3,3,1,0,0],"is_day":[0,0,0,0,0,0,0,0,1,1,1,1,1,1,1,1,1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,1,1,1,1,1,1,1,1,0,0,0,0,0,0]},"daily_units":{"time":"unixtime","weather_code":"wmo code","temperature_2m_max":"°C","temperature_2m_min":"°C","precipitation_probability_max":"%"},"daily":{"time":[1792706400,1792792800],"weather_code":[80,61],"temperature_2m_max":[14.5,11.8],"temperature_2m_min":[6.8,6.6],"precipitation_probability_max":[53,55]}}
"""

struct OpenMeteoDecodingTests {
    @Test func sampleResponseDecodes() throws {
        let report = try OpenMeteo.decode(Data(sampleResponse.utf8))
        #expect(report.current.temperature == 9.7)
        #expect(report.current.condition == .cloudy)
        #expect(report.current.isDay == false)
        #expect(report.hours.count == 4)
        // This older response has no daily weather_code, so no day is usable.
        #expect(report.days.isEmpty)
        #expect(report.todayHigh == nil)
        #expect(report.todayLow == nil)
    }

    @Test func twoDayResponseDecodes() throws {
        let report = try OpenMeteo.decode(Data(twoDayResponse.utf8))
        #expect(report.current.temperature == 9.2)
        #expect(report.current.condition == .clear)
        #expect(report.current.isDay == false)
        #expect(report.hours.count == 48)
        #expect(report.hours.first?.time == Date(timeIntervalSince1970: 1792706400))
        #expect(report.hours.last?.time == Date(timeIntervalSince1970: 1792875600))
        #expect(report.days.count == 2)
        let today = try #require(report.today)
        #expect(today.start == Date(timeIntervalSince1970: 1792706400))
        #expect(today.condition == .showers)
        #expect(today.high == 14.5)
        #expect(today.low == 6.8)
        #expect(today.precipitationChance == 53)
        let tomorrow = try #require(report.tomorrow)
        #expect(tomorrow.start == Date(timeIntervalSince1970: 1792792800))
        #expect(tomorrow.condition == .lightRain)
        #expect(tomorrow.high == 11.8)
        #expect(tomorrow.low == 6.6)
        #expect(tomorrow.precipitationChance == 55)
        #expect(report.todayHigh == 14.5)
        #expect(report.todayLow == 6.8)
    }

    @Test func daysMissingValuesAreSkipped() throws {
        let json = """
        {"current":{"time":100,"temperature_2m":1.5,"weather_code":0,"is_day":1},
         "daily":{"time":[1000,2000,3000],"weather_code":[1,null,61],"temperature_2m_max":[5.0,6.0,null],"temperature_2m_min":[1.0,2.0,3.0]}}
        """
        let report = try OpenMeteo.decode(Data(json.utf8))
        #expect(report.days.count == 1)
        #expect(report.today?.start == Date(timeIntervalSince1970: 1000))
        #expect(report.today?.precipitationChance == nil)
        #expect(report.tomorrow == nil)
    }

    @Test func sunTimesAreReadForEachDayThatHasBoth() throws {
        // The second day lacks a sunset; the third is a polar night, where the
        // sun "rises" and "sets" at the same moment. Neither has a forecast.
        let json = """
        {"current":{"time":100,"temperature_2m":1.5,"weather_code":0,"is_day":1},
         "daily":{"time":[0,86400,172800,259200],"weather_code":[1,2,null,3],
                  "temperature_2m_max":[5.0,6.0,7.0,8.0],"temperature_2m_min":[1.0,2.0,3.0,4.0],
                  "sunrise":[25000,111400,172800,284000],"sunset":[62000,null,172800,320000]}}
        """
        let report = try OpenMeteo.decode(Data(json.utf8))
        #expect(report.sunTimes.map(\.sunrise) == [25000, 284000].map { Date(timeIntervalSince1970: $0) })
        #expect(report.sunTimes.map(\.sunset) == [62000, 320000].map { Date(timeIntervalSince1970: $0) })
        #expect(report.days.count == 3)
    }

    @Test func aResponseWithoutSunTimesHasNone() throws {
        #expect(try OpenMeteo.decode(Data(twoDayResponse.utf8)).sunTimes.isEmpty)
    }

    @Test func nullPrecipitationChanceIsNil() throws {
        let json = """
        {"current":{"time":100,"temperature_2m":1.5,"weather_code":0,"is_day":1},
         "daily":{"time":[1000,2000],"weather_code":[1,2],"temperature_2m_max":[5.0,6.0],"temperature_2m_min":[1.0,2.0],"precipitation_probability_max":[null,40]}}
        """
        let report = try OpenMeteo.decode(Data(json.utf8))
        #expect(report.days.map(\.precipitationChance) == [nil, 40])
    }

    @Test func hoursOnADayPickTheNamedHours() throws {
        let report = try OpenMeteo.decode(Data(twoDayResponse.utf8))
        let today = try #require(report.today)
        let tomorrow = try #require(report.tomorrow)
        // Berlin is UTC+2, so 07:00 local is midnight + 7 hours.
        let todayReadings = report.hours(on: today, count: 3)
        #expect(todayReadings.map(\.time) == [7, 15, 22].map { today.start.addingTimeInterval(Double($0) * 3600) })
        #expect(todayReadings.map(\.temperature) == [7.5, 14.4, 11.1])
        let tomorrowReadings = report.hours(on: tomorrow, count: 4)
        #expect(tomorrowReadings.map(\.time) == [7, 12, 17, 22].map { tomorrow.start.addingTimeInterval(Double($0) * 3600) })
        #expect(tomorrowReadings.map(\.temperature) == [9.2, 8.8, 11.8, 8.7])
        #expect(report.hours(on: today, count: 0).isEmpty)
    }

    @Test func hoursOnADaySkipMissingReadingsAndAcceptHalfAnHourOff() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        func reading(_ offset: TimeInterval) -> WeatherReport.Reading {
            WeatherReport.Reading(
                time: start.addingTimeInterval(offset), temperature: offset, condition: .clear, isDay: true)
        }
        let day = WeatherReport.Day(
            start: start, condition: .clear, high: 1, low: 0, precipitationChance: nil)
        // 07:00 exact, 15:00 missing (the nearest is an hour away), 22:00 half an hour late.
        let report = WeatherReport(
            current: reading(0),
            hours: [reading(7 * 3600), reading(14 * 3600), reading(22 * 3600 + 1800)],
            days: [day]
        )
        let temperatures: [Double] = [25200, 81000]
        #expect(report.hours(on: day, count: 3).map(\.temperature) == temperatures)
    }

    @Test func upcomingHoursStartAfterNow() throws {
        let report = try OpenMeteo.decode(Data(sampleResponse.utf8))
        let upcoming = report.upcomingHours(after: Date(timeIntervalSince1970: 1792714199))
        #expect(upcoming.count == 3)
        #expect(upcoming.first?.time == Date(timeIntervalSince1970: 1792717200))
        #expect(upcoming.map(\.temperature) == [9.2, 8.7, 8.3])
    }

    @Test func hoursWithMissingValuesAreSkipped() throws {
        let json = """
        {"current":{"time":100,"temperature_2m":1.5,"weather_code":0,"is_day":1},
         "hourly":{"time":[100,200,300,400],"temperature_2m":[1.0,null,3.0,4.0],"weather_code":[0,1,null,61],"is_day":[1,1,1,0]}}
        """
        let report = try OpenMeteo.decode(Data(json.utf8))
        #expect(report.hours.map(\.time) == [Date(timeIntervalSince1970: 100), Date(timeIntervalSince1970: 400)])
        #expect(report.hours.last?.condition == .lightRain)
        #expect(report.hours.last?.isDay == false)
    }

    @Test func missingDailyDataGivesNoHighOrLow() throws {
        let json = """
        {"current":{"time":100,"temperature_2m":1.5,"weather_code":0,"is_day":1},
         "hourly":{"time":[100],"temperature_2m":[1.0],"weather_code":[0],"is_day":[1]}}
        """
        let report = try OpenMeteo.decode(Data(json.utf8))
        #expect(report.days.isEmpty)
        #expect(report.todayHigh == nil)
        #expect(report.todayLow == nil)
    }
}

struct OpenMeteoURLTests {
    @Test func queryHasEveryParameter() throws {
        let url = OpenMeteo.forecastURL(for: Coordinate(latitude: 52.5249, longitude: 13.4195))
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.scheme == "https")
        #expect(components.host == "api.open-meteo.com")
        #expect(components.path == "/v1/forecast")
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })
        #expect(items["latitude"] == "52.52")
        #expect(items["longitude"] == "13.42")
        #expect(items["current"] == "temperature_2m,weather_code,is_day")
        #expect(items["hourly"] == "temperature_2m,weather_code,is_day")
        #expect(items["daily"] == "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,sunrise,sunset")
        #expect(items["forecast_hours"] == nil)
        #expect(items["forecast_days"] == "2")
        #expect(items["timezone"] == "auto")
        #expect(items["timeformat"] == "unixtime")
    }
}

struct WeatherConditionTests {
    @Test func codesMapToSymbolsAndLabels() {
        let cases: [(Int, String, String, String, String)] = [
            (0, "sun.max.fill", "moon.stars.fill", "Clear", "晴"),
            (1, "sun.max.fill", "moon.stars.fill", "Mostly Clear", "大部晴朗"),
            (2, "cloud.sun.fill", "cloud.moon.fill", "Partly Cloudy", "局部多云"),
            (3, "cloud.fill", "cloud.fill", "Cloudy", "阴天"),
            (45, "cloud.fog.fill", "cloud.fog.fill", "Fog", "雾"),
            (48, "cloud.fog.fill", "cloud.fog.fill", "Fog", "雾"),
            (53, "cloud.drizzle.fill", "cloud.drizzle.fill", "Drizzle", "毛毛雨"),
            (57, "cloud.sleet.fill", "cloud.sleet.fill", "Freezing Drizzle", "冻毛毛雨"),
            (61, "cloud.rain.fill", "cloud.rain.fill", "Light Rain", "小雨"),
            (63, "cloud.rain.fill", "cloud.rain.fill", "Rain", "中雨"),
            (65, "cloud.heavyrain.fill", "cloud.heavyrain.fill", "Heavy Rain", "大雨"),
            (66, "cloud.sleet.fill", "cloud.sleet.fill", "Freezing Rain", "冻雨"),
            (71, "cloud.snow.fill", "cloud.snow.fill", "Light Snow", "小雪"),
            (73, "cloud.snow.fill", "cloud.snow.fill", "Snow", "中雪"),
            (75, "cloud.snow.fill", "cloud.snow.fill", "Heavy Snow", "大雪"),
            (77, "cloud.snow.fill", "cloud.snow.fill", "Snow Grains", "米雪"),
            (80, "cloud.sun.rain.fill", "cloud.moon.rain.fill", "Showers", "阵雨"),
            (81, "cloud.sun.rain.fill", "cloud.moon.rain.fill", "Showers", "阵雨"),
            (82, "cloud.heavyrain.fill", "cloud.heavyrain.fill", "Heavy Showers", "强阵雨"),
            (86, "cloud.snow.fill", "cloud.snow.fill", "Snow Showers", "阵雪"),
            (95, "cloud.bolt.rain.fill", "cloud.bolt.rain.fill", "Thunderstorms", "雷阵雨"),
            (99, "cloud.bolt.rain.fill", "cloud.bolt.rain.fill", "Thunderstorms with Hail", "雷阵雨伴冰雹"),
        ]
        for (code, day, night, english, chinese) in cases {
            let condition = WeatherCondition(code: code)
            #expect(condition.symbol(isDay: true) == day, "code \(code)")
            #expect(condition.symbol(isDay: false) == night, "code \(code)")
            #expect(condition.label(in: .english) == english, "code \(code)")
            #expect(condition.label(in: .simplifiedChinese) == chinese, "code \(code)")
        }
    }

    @Test func unknownCodesFallBackToCloud() {
        for code in [4, 50, 100, -1] {
            let condition = WeatherCondition(code: code)
            #expect(condition == .unknown)
            #expect(condition.symbol(isDay: true) == "cloud.fill")
            #expect(condition.label(in: .english) == "Unknown")
            #expect(condition.label(in: .simplifiedChinese) == "未知")
        }
    }
}

struct WeatherFormatTests {
    @Test func temperaturesRoundToWholeDegrees() {
        #expect(WeatherFormat.temperature(9.7, in: .celsius) == "10°")
        #expect(WeatherFormat.temperature(9.7, in: .fahrenheit) == "49°")
        #expect(WeatherFormat.temperature(-0.4, in: .celsius) == "0°")
        #expect(WeatherFormat.temperature(-12.2, in: .celsius) == "-12°")
    }

    @Test func hourLabelsUseTheTwentyFourHourClock() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Berlin"))
        // 1792713600 is midnight UTC; 14:00 UTC is 16:00 in Berlin (UTC+2).
        let afternoon = Date(timeIntervalSince1970: 1792713600 + 14 * 3600)
        let morning = Date(timeIntervalSince1970: 1792713600 + 7 * 3600)
        #expect(WeatherFormat.hourLabel(afternoon, calendar: calendar, language: .english) == "16:00")
        #expect(WeatherFormat.hourLabel(afternoon, calendar: calendar, language: .simplifiedChinese) == "16时")
        #expect(WeatherFormat.hourLabel(morning, calendar: calendar, language: .english) == "09:00")
        #expect(WeatherFormat.hourLabel(morning, calendar: calendar, language: .simplifiedChinese) == "9时")
    }
}

struct WeatherDayHoursTests {
    @Test func spreadsHoursEvenlyFromSevenToTen() {
        #expect(WeatherFormat.dayHours(count: 0).isEmpty)
        #expect(WeatherFormat.dayHours(count: -2).isEmpty)
        #expect(WeatherFormat.dayHours(count: 1) == [14])
        #expect(WeatherFormat.dayHours(count: 2) == [7, 22])
        #expect(WeatherFormat.dayHours(count: 3) == [7, 15, 22])
        #expect(WeatherFormat.dayHours(count: 4) == [7, 12, 17, 22])
        #expect(WeatherFormat.dayHours(count: 6) == [7, 10, 13, 16, 19, 22])
        #expect(WeatherFormat.dayHours(count: 8) == [7, 9, 11, 13, 16, 18, 20, 22])
    }
}

struct WeatherArrangementTests {
    @Test func widthPicksTheArrangement() {
        #expect(WeatherArrangement.forWidth(152) == .compact(hourCount: 3))
        #expect(WeatherArrangement.forWidth(247) == .compact(hourCount: 3))
        #expect(WeatherArrangement.forWidth(248) == .wide(hourCount: 3))
        #expect(WeatherArrangement.forWidth(262) == .wide(hourCount: 3))
        #expect(WeatherArrangement.forWidth(312) == .wide(hourCount: 4))
        #expect(WeatherArrangement.forWidth(456) == .wide(hourCount: 8))
    }
}

@MainActor
struct LocationProviderTests {
    @Test func reusesFixesUpToTenMinutesOld() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(LocationProvider.isRecent(now.addingTimeInterval(-599), now: now))
        #expect(!LocationProvider.isRecent(now.addingTimeInterval(-600), now: now))
    }
}

struct WeatherRefreshPolicyTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    @Test func refreshesWithoutAReport() {
        #expect(WeatherRefreshPolicy.shouldRefresh(now: now, lastSuccess: nil, lastFailure: nil, isInFlight: false))
    }

    @Test func neverWhileInFlight() {
        #expect(!WeatherRefreshPolicy.shouldRefresh(now: now, lastSuccess: nil, lastFailure: nil, isInFlight: true))
    }

    @Test func keepsReportsUpToTwoHoursOld() {
        #expect(WeatherRefreshPolicy.keepsReport(observedAt: now.addingTimeInterval(-119 * 60), now: now))
        #expect(!WeatherRefreshPolicy.keepsReport(observedAt: now.addingTimeInterval(-120 * 60), now: now))
    }

    @Test func refreshesOnceTheReportIsFifteenMinutesOld() {
        #expect(!WeatherRefreshPolicy.shouldRefresh(
            now: now, lastSuccess: now.addingTimeInterval(-14 * 60), lastFailure: nil, isInFlight: false))
        #expect(WeatherRefreshPolicy.shouldRefresh(
            now: now, lastSuccess: now.addingTimeInterval(-15 * 60), lastFailure: nil, isInFlight: false))
    }

    @Test func waitsTwoMinutesAfterAFailure() {
        #expect(!WeatherRefreshPolicy.shouldRefresh(
            now: now, lastSuccess: nil, lastFailure: now.addingTimeInterval(-119), isInFlight: false))
        #expect(WeatherRefreshPolicy.shouldRefresh(
            now: now, lastSuccess: nil, lastFailure: now.addingTimeInterval(-120), isInFlight: false))
        #expect(!WeatherRefreshPolicy.shouldRefresh(
            now: now,
            lastSuccess: now.addingTimeInterval(-30 * 60),
            lastFailure: now.addingTimeInterval(-60),
            isInFlight: false
        ))
    }
}

struct WeatherScheduleTests {
    private let standard = WeatherSchedule.standard

    @Test func standardScheduleIsFivePastTenNineteen() {
        #expect(standard.starts == [300, 600, 1140])
        #expect(standard.modes == [.today, .upcoming, .tomorrow])
        #expect([0, 1, 2].map { standard.length(of: $0) } == [300, 540, 600])
        #expect([0, 1, 2].map { standard.end(of: $0) } == [600, 1140, 300])
    }

    @Test func periodsContainTheirStartAndWrapPastMidnight() {
        #expect(standard.period(atMinute: 299) == 2)
        #expect(standard.period(atMinute: 300) == 0)
        #expect(standard.period(atMinute: 599) == 0)
        #expect(standard.period(atMinute: 600) == 1)
        #expect(standard.period(atMinute: 1139) == 1)
        #expect(standard.period(atMinute: 1140) == 2)
        #expect(standard.period(atMinute: 0) == 2)
        #expect(standard.period(atMinute: 1439) == 2)
        #expect(standard.period(atMinute: 1740) == 0)
        #expect(standard.period(atMinute: -60) == 2)
    }

    @Test func modeFollowsTheCalendarClock() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Berlin"))
        // 1792713600 is 02:00 in Berlin (UTC+2).
        let midnight = Date(timeIntervalSince1970: 1792713600 - 2 * 3600)
        #expect(standard.mode(at: midnight.addingTimeInterval(2 * 3600), calendar: calendar) == .tomorrow)
        #expect(standard.mode(at: midnight.addingTimeInterval(5 * 3600), calendar: calendar) == .today)
        #expect(standard.mode(at: midnight.addingTimeInterval(9 * 3600 + 59 * 60), calendar: calendar) == .today)
        #expect(standard.mode(at: midnight.addingTimeInterval(10 * 3600), calendar: calendar) == .upcoming)
        #expect(standard.mode(at: midnight.addingTimeInterval(19 * 3600), calendar: calendar) == .tomorrow)
    }

    @Test func initRejectsInvalidSchedules() {
        let modes: [WeatherDisplayMode] = [.today, .upcoming, .tomorrow]
        #expect(WeatherSchedule(starts: [300, 600], modes: modes) == nil)
        #expect(WeatherSchedule(starts: [300, 600, 1140], modes: [.today, .upcoming]) == nil)
        #expect(WeatherSchedule(starts: [300, 330, 1140], modes: modes) == nil)
        #expect(WeatherSchedule(starts: [300, 605, 1140], modes: modes) == nil)
        #expect(WeatherSchedule(starts: [300, 600, 1500], modes: modes) == nil)
        #expect(WeatherSchedule(starts: [300, 600, -60], modes: modes) == nil)
        #expect(WeatherSchedule(starts: [600, 300, 1140], modes: modes) == nil)
        #expect(WeatherSchedule(starts: [300, 300, 1140], modes: modes) == nil)
    }

    @Test func initAcceptsPeriodsThatWrapPastMidnight() throws {
        let schedule = try #require(WeatherSchedule(
            starts: [1410, 600, 1140], modes: [.today, .upcoming, .tomorrow]))
        #expect([0, 1, 2].map { schedule.length(of: $0) } == [630, 540, 270])
    }

    @Test func movingAStartSnapsToTheStep() {
        var schedule = standard
        schedule.moveStart(of: 0, to: 420)
        #expect(schedule.starts == [420, 600, 1140])
        schedule.moveStart(of: 0, to: 307)
        #expect(schedule.starts[0] == 300)
        schedule.moveStart(of: 0, to: 308)
        #expect(schedule.starts[0] == 315)
    }

    @Test func movingAStartStopsAMinimumLengthFromItsNeighbours() {
        var schedule = standard
        schedule.moveStart(of: 0, to: 560)
        #expect(schedule.starts[0] == 540)
        schedule = standard
        schedule.moveStart(of: 0, to: 1170)
        #expect(schedule.starts[0] == 1200)
        schedule = standard
        schedule.moveStart(of: 1, to: 1300)
        #expect(schedule.starts[1] == 1080)
    }

    @Test func aStartMayMovePastMidnight() {
        var schedule = standard
        schedule.moveStart(of: 0, to: 1410)
        #expect(schedule.starts == [1410, 600, 1140])
        #expect(schedule.period(atMinute: 0) == 0)
        #expect(WeatherSchedule(starts: schedule.starts, modes: schedule.modes) == schedule)
    }

    @Test func movedSchedulesStayValid() {
        var schedule = standard
        for target in stride(from: -100, to: 3000, by: 37) {
            for period in 0..<3 {
                schedule.moveStart(of: period, to: target)
                #expect(WeatherSchedule(starts: schedule.starts, modes: schedule.modes) == schedule)
            }
        }
    }

    @Test func anglesConvertToMinutes() {
        #expect(WeatherSchedule.minute(forAngle: 0) == 0)
        #expect(WeatherSchedule.minute(forAngle: .pi / 2) == 360)
        #expect(WeatherSchedule.minute(forAngle: .pi) == 720)
        #expect(WeatherSchedule.minute(forAngle: -.pi / 2) == 1080)
        #expect(WeatherSchedule.minute(forAngle: 2 * .pi + .pi / 2) == 360)
        #expect(WeatherSchedule.angle(forMinute: 0) == 0)
        #expect(WeatherSchedule.angle(forMinute: 720) == .pi)
        #expect(WeatherSchedule.angle(forMinute: 1440) == 0)
    }

    @Test func roundTripsThroughJSON() throws {
        let schedule = try #require(WeatherSchedule(
            starts: [1410, 600, 1140], modes: [.tomorrow, .today, .upcoming]))
        let data = try JSONEncoder().encode(schedule)
        #expect(try JSONDecoder().decode(WeatherSchedule.self, from: data) == schedule)
    }

    @Test func decodingAnInvalidScheduleThrows() {
        let json = #"{"starts":[300,330,1140],"modes":["today","upcoming","tomorrow"]}"#
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(WeatherSchedule.self, from: Data(json.utf8))
        }
    }

    @Test func modesHaveSymbols() {
        #expect(WeatherDisplayMode.allCases.map(\.symbol) == ["sun.max.fill", "clock.fill", "moon.stars.fill"])
    }
}

@MainActor
struct WeatherSettingsTests {
    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suite = "WeatherSettingsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }

    @Test func startsWithTheStandardSchedule() throws {
        try withDefaults { defaults in
            #expect(WeatherSettings(defaults: defaults).schedule == .standard)
        }
    }

    @Test func aChangePersistsAcrossInstances() throws {
        try withDefaults { defaults in
            let settings = WeatherSettings(defaults: defaults)
            settings.schedule.moveStart(of: 0, to: 420)
            settings.schedule.modes[1] = .tomorrow
            let reloaded = WeatherSettings(defaults: defaults)
            #expect(reloaded.schedule == settings.schedule)
            #expect(reloaded.schedule.starts == [420, 600, 1140])
            #expect(reloaded.schedule.modes == [.today, .tomorrow, .tomorrow])
        }
    }

    @Test func resettingRestoresAndSavesTheStandardSchedule() throws {
        try withDefaults { defaults in
            let settings = WeatherSettings(defaults: defaults)
            settings.schedule.moveStart(of: 0, to: 420)
            settings.resetSchedule()
            #expect(settings.schedule == .standard)
            #expect(WeatherSettings(defaults: defaults).schedule == .standard)
        }
    }

    @Test func garbageFallsBackToTheStandardSchedule() throws {
        try withDefaults { defaults in
            defaults.set(Data("not json".utf8), forKey: WeatherSettings.scheduleKey)
            #expect(WeatherSettings(defaults: defaults).schedule == .standard)
            let invalid = #"{"starts":[300,330,1140],"modes":["today","upcoming","tomorrow"]}"#
            defaults.set(Data(invalid.utf8), forKey: WeatherSettings.scheduleKey)
            #expect(WeatherSettings(defaults: defaults).schedule == .standard)
        }
    }
}

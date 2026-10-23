import Foundation
import NotchKit
import Testing
@testable import WeatherFeature

/// A real Open-Meteo response for Berlin, fetched when "now" was 1792714199.
private let sampleResponse = """
{"latitude":52.512604,"longitude":13.419517,"generationtime_ms":0.22101402282714844,"utc_offset_seconds":7200,"timezone":"Europe/Berlin","timezone_abbreviation":"GMT+2","elevation":38.0,"current_units":{"time":"unixtime","interval":"seconds","temperature_2m":"°C","weather_code":"wmo code","is_day":""},"current":{"time":1792713600,"interval":900,"temperature_2m":9.7,"weather_code":3,"is_day":0},"hourly_units":{"time":"unixtime","temperature_2m":"°C","weather_code":"wmo code","is_day":""},"hourly":{"time":[1792713600,1792717200,1792720800,1792724400],"temperature_2m":[9.7,9.2,8.7,8.3],"weather_code":[3,2,2,2],"is_day":[0,0,0,0]},"daily_units":{"time":"unixtime","temperature_2m_max":"°C","temperature_2m_min":"°C"},"daily":{"time":[1792706400,1792792800],"temperature_2m_max":[14.7,11.8],"temperature_2m_min":[6.9,6.6]}}
"""

struct OpenMeteoDecodingTests {
    @Test func sampleResponseDecodes() throws {
        let report = try OpenMeteo.decode(Data(sampleResponse.utf8))
        #expect(report.current.temperature == 9.7)
        #expect(report.current.condition == .cloudy)
        #expect(report.current.isDay == false)
        #expect(report.hours.count == 4)
        #expect(report.todayHigh == 14.7)
        #expect(report.todayLow == 6.9)
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
        #expect(items["daily"] == "temperature_2m_max,temperature_2m_min")
        #expect(items["forecast_hours"] == "12")
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

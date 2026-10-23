import Foundation
import NotchKit

/// A place on Earth, in degrees.
struct Coordinate: Equatable, Sendable {
    let latitude: Double
    let longitude: Double
}

/// The current conditions, the hours of today and tomorrow, and a summary of
/// each of those days at one place, in degrees Celsius.
struct WeatherReport: Equatable, Sendable {
    struct Reading: Equatable, Sendable {
        let time: Date
        let temperature: Double
        let condition: WeatherCondition
        let isDay: Bool
    }

    /// One day's forecast.
    struct Day: Equatable, Sendable {
        /// Local midnight.
        let start: Date
        let condition: WeatherCondition
        let high: Double
        let low: Double
        /// Percent; nil when the forecast gives none.
        let precipitationChance: Int?
    }

    let current: Reading
    /// Hourly forecast from today's local midnight to the end of tomorrow, in order.
    let hours: [Reading]
    /// Index 0 is today, 1 tomorrow. A day the response lacks a time, code, high
    /// or low for is left out.
    let days: [Day]
    /// Sunrise and sunset of each day the response has both for, in order. A
    /// polar day or night has none.
    var sunTimes: [SunTimes] = []

    var today: Day? { days.first }
    var tomorrow: Day? { days.count > 1 ? days[1] : nil }
    var todayHigh: Double? { today?.high }
    var todayLow: Double? { today?.low }

    /// The forecast hours that start strictly after `now`, in order.
    func upcomingHours(after now: Date) -> [Reading] {
        hours.filter { $0.time > now }
    }

    /// The readings at the hours `WeatherFormat.dayHours(count:)` names on `day`,
    /// in order. A reading within half an hour of the hour counts, since a day
    /// with a clock change is not 24 hours long; hours without one are skipped.
    func hours(on day: Day, count: Int) -> [Reading] {
        WeatherFormat.dayHours(count: count).compactMap { hour in
            let target = day.start.addingTimeInterval(TimeInterval(hour) * 3600)
            let nearest = hours.min {
                abs($0.time.timeIntervalSince(target)) < abs($1.time.timeIntervalSince(target))
            }
            guard let nearest, abs(nearest.time.timeIntervalSince(target)) <= 30 * 60 else { return nil }
            return nearest
        }
    }
}

/// The Open-Meteo forecast API (https://open-meteo.com), which needs no API key.
enum OpenMeteo {
    static func forecastURL(for coordinate: Coordinate) -> URL {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            // Two decimals (about a kilometre) is all the forecast needs, and keeps
            // the precise location out of the request.
            URLQueryItem(name: "latitude", value: rounded(coordinate.latitude)),
            URLQueryItem(name: "longitude", value: rounded(coordinate.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code,is_day"),
            URLQueryItem(name: "hourly", value: "temperature_2m,weather_code,is_day"),
            URLQueryItem(
                name: "daily",
                value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,sunrise,sunset"
            ),
            URLQueryItem(name: "forecast_days", value: "2"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "timeformat", value: "unixtime"),
        ]
        return components.url!
    }

    static func fetch(for coordinate: Coordinate) async throws -> WeatherReport {
        var request = URLRequest(url: forecastURL(for: coordinate))
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try decode(data)
    }

    /// Reads a forecast response. Hours missing a temperature or code are left
    /// out, and days missing a code, high or low are too; without daily data the
    /// report has no days, so no high or low. Sun times are read apart from the
    /// rest of a day, so a day without a forecast still has them.
    static func decode(_ data: Data) throws -> WeatherReport {
        let response = try JSONDecoder().decode(Response.self, from: data)
        let current = WeatherReport.Reading(
            time: Date(timeIntervalSince1970: response.current.time),
            temperature: response.current.temperature,
            condition: WeatherCondition(code: response.current.weatherCode),
            isDay: (response.current.isDay ?? 1) != 0
        )
        var hours: [WeatherReport.Reading] = []
        if let hourly = response.hourly {
            for (index, time) in hourly.time.enumerated() {
                guard let temperature = hourly.temperature.element(at: index) ?? nil,
                      let code = hourly.weatherCode.element(at: index) ?? nil
                else { continue }
                let isDay = hourly.isDay?.element(at: index) ?? nil
                hours.append(WeatherReport.Reading(
                    time: Date(timeIntervalSince1970: time),
                    temperature: temperature,
                    condition: WeatherCondition(code: code),
                    isDay: (isDay ?? 1) != 0
                ))
            }
        }
        var days: [WeatherReport.Day] = []
        if let daily = response.daily, let times = daily.time {
            for (index, time) in times.enumerated() {
                guard let time,
                      let code = daily.weatherCode?.element(at: index) ?? nil,
                      let high = daily.temperatureMax?.element(at: index) ?? nil,
                      let low = daily.temperatureMin?.element(at: index) ?? nil
                else { continue }
                let chance = daily.precipitationChance?.element(at: index) ?? nil
                days.append(WeatherReport.Day(
                    start: Date(timeIntervalSince1970: time),
                    condition: WeatherCondition(code: code),
                    high: high,
                    low: low,
                    precipitationChance: chance.map { Int($0.rounded()) }
                ))
            }
        }
        var sunTimes: [SunTimes] = []
        if let sunrises = response.daily?.sunrise, let sunsets = response.daily?.sunset {
            for (sunrise, sunset) in zip(sunrises, sunsets) {
                guard let sunrise, let sunset,
                      let times = SunTimes(
                          sunrise: Date(timeIntervalSince1970: sunrise),
                          sunset: Date(timeIntervalSince1970: sunset)
                      )
                else { continue }
                sunTimes.append(times)
            }
        }
        return WeatherReport(current: current, hours: hours, days: days, sunTimes: sunTimes)
    }

    private static func rounded(_ degrees: Double) -> String {
        String(format: "%.2f", (degrees * 100).rounded() / 100)
    }

    private struct Response: Decodable {
        struct Current: Decodable {
            let time: TimeInterval
            let temperature: Double
            let weatherCode: Int
            let isDay: Int?

            enum CodingKeys: String, CodingKey {
                case time
                case temperature = "temperature_2m"
                case weatherCode = "weather_code"
                case isDay = "is_day"
            }
        }

        struct Hourly: Decodable {
            let time: [TimeInterval]
            let temperature: [Double?]
            let weatherCode: [Int?]
            let isDay: [Int?]?

            enum CodingKeys: String, CodingKey {
                case time
                case temperature = "temperature_2m"
                case weatherCode = "weather_code"
                case isDay = "is_day"
            }
        }

        struct Daily: Decodable {
            let time: [TimeInterval?]?
            let weatherCode: [Int?]?
            let temperatureMax: [Double?]?
            let temperatureMin: [Double?]?
            let precipitationChance: [Double?]?
            let sunrise: [TimeInterval?]?
            let sunset: [TimeInterval?]?

            enum CodingKeys: String, CodingKey {
                case time
                case weatherCode = "weather_code"
                case temperatureMax = "temperature_2m_max"
                case temperatureMin = "temperature_2m_min"
                case precipitationChance = "precipitation_probability_max"
                case sunrise
                case sunset
            }
        }

        let current: Current
        let hourly: Hourly?
        let daily: Daily?
    }
}

private extension Array {
    func element(at index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

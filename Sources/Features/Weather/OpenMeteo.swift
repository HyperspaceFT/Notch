import Foundation

/// A place on Earth, in degrees.
struct Coordinate: Equatable, Sendable {
    let latitude: Double
    let longitude: Double
}

/// The current conditions and the next hours at one place, in degrees Celsius.
struct WeatherReport: Equatable, Sendable {
    struct Reading: Equatable, Sendable {
        let time: Date
        let temperature: Double
        let condition: WeatherCondition
        let isDay: Bool
    }

    let current: Reading
    /// Hourly forecast from the start of the current hour, in order.
    let hours: [Reading]
    let todayHigh: Double?
    let todayLow: Double?

    /// The forecast hours that start strictly after `now`, in order.
    func upcomingHours(after now: Date) -> [Reading] {
        hours.filter { $0.time > now }
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
            URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min"),
            URLQueryItem(name: "forecast_hours", value: "12"),
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
    /// out, and without daily data the report has no high or low.
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
        return WeatherReport(
            current: current,
            hours: hours,
            todayHigh: response.daily?.temperatureMax?.element(at: 0) ?? nil,
            todayLow: response.daily?.temperatureMin?.element(at: 0) ?? nil
        )
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
            let temperatureMax: [Double?]?
            let temperatureMin: [Double?]?

            enum CodingKeys: String, CodingKey {
                case temperatureMax = "temperature_2m_max"
                case temperatureMin = "temperature_2m_min"
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

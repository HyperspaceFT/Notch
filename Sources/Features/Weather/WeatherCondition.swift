import NotchKit

/// The sky and precipitation an Open-Meteo WMO `weather_code` describes.
enum WeatherCondition: Equatable, Sendable {
    case clear
    case mostlyClear
    case partlyCloudy
    case cloudy
    case fog
    case drizzle
    case freezingDrizzle
    case lightRain
    case rain
    case heavyRain
    case freezingRain
    case lightSnow
    case snow
    case heavySnow
    case snowGrains
    case showers
    case heavyShowers
    case snowShowers
    case thunderstorms
    case thunderstormsWithHail
    /// A code outside the WMO table Open-Meteo documents.
    case unknown

    init(code: Int) {
        switch code {
        case 0: self = .clear
        case 1: self = .mostlyClear
        case 2: self = .partlyCloudy
        case 3: self = .cloudy
        case 45, 48: self = .fog
        case 51, 53, 55: self = .drizzle
        case 56, 57: self = .freezingDrizzle
        case 61: self = .lightRain
        case 63: self = .rain
        case 65: self = .heavyRain
        case 66, 67: self = .freezingRain
        case 71: self = .lightSnow
        case 73: self = .snow
        case 75: self = .heavySnow
        case 77: self = .snowGrains
        case 80, 81: self = .showers
        case 82: self = .heavyShowers
        case 85, 86: self = .snowShowers
        case 95: self = .thunderstorms
        case 96, 99: self = .thunderstormsWithHail
        default: self = .unknown
        }
    }

    /// SF Symbol, drawn with the multicolor rendering mode.
    func symbol(isDay: Bool) -> String {
        switch self {
        case .clear, .mostlyClear: isDay ? "sun.max.fill" : "moon.stars.fill"
        case .partlyCloudy: isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case .cloudy, .unknown: "cloud.fill"
        case .fog: "cloud.fog.fill"
        case .drizzle: "cloud.drizzle.fill"
        case .freezingDrizzle, .freezingRain: "cloud.sleet.fill"
        case .lightRain, .rain: "cloud.rain.fill"
        case .heavyRain, .heavyShowers: "cloud.heavyrain.fill"
        case .lightSnow, .snow, .heavySnow, .snowGrains, .snowShowers: "cloud.snow.fill"
        case .showers: isDay ? "cloud.sun.rain.fill" : "cloud.moon.rain.fill"
        case .thunderstorms, .thunderstormsWithHail: "cloud.bolt.rain.fill"
        }
    }

    func label(in language: AppLanguage) -> String {
        let (english, chinese) = labels
        switch language {
        case .english: return english
        case .simplifiedChinese: return chinese
        }
    }

    private var labels: (String, String) {
        switch self {
        case .clear: ("Clear", "晴")
        case .mostlyClear: ("Mostly Clear", "大部晴朗")
        case .partlyCloudy: ("Partly Cloudy", "局部多云")
        case .cloudy: ("Cloudy", "阴天")
        case .fog: ("Fog", "雾")
        case .drizzle: ("Drizzle", "毛毛雨")
        case .freezingDrizzle: ("Freezing Drizzle", "冻毛毛雨")
        case .lightRain: ("Light Rain", "小雨")
        case .rain: ("Rain", "中雨")
        case .heavyRain: ("Heavy Rain", "大雨")
        case .freezingRain: ("Freezing Rain", "冻雨")
        case .lightSnow: ("Light Snow", "小雪")
        case .snow: ("Snow", "中雪")
        case .heavySnow: ("Heavy Snow", "大雪")
        case .snowGrains: ("Snow Grains", "米雪")
        case .showers: ("Showers", "阵雨")
        case .heavyShowers: ("Heavy Showers", "强阵雨")
        case .snowShowers: ("Snow Showers", "阵雪")
        case .thunderstorms: ("Thunderstorms", "雷阵雨")
        case .thunderstormsWithHail: ("Thunderstorms with Hail", "雷阵雨伴冰雹")
        case .unknown: ("Unknown", "未知")
        }
    }
}

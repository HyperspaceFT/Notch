import Foundation
import NotchKit

/// Text and layout decisions for the weather module, kept free of views.
enum WeatherFormat {
    /// `celsius` in `unit`, rounded to a whole degree, as "18°". Never "-0°".
    static func temperature(_ celsius: Double, in unit: UnitTemperature) -> String {
        let value = Measurement(value: celsius, unit: UnitTemperature.celsius).converted(to: unit).value
        // Int has no negative zero, so -0.4 rounds to "0°".
        return "\(Int(value.rounded()))°"
    }

    /// The hour `date` starts, on the 24-hour clock the app uses: "16:00" or "16时".
    static func hourLabel(_ date: Date, calendar: Calendar, language: AppLanguage) -> String {
        let hour = calendar.component(.hour, from: date)
        switch language {
        case .english: return String(format: "%02d:00", hour)
        case .simplifiedChinese: return "\(hour)时"
        }
    }

    /// Hours of a day to show `count` of, spread evenly from 07:00 to 22:00 and rounded to whole hours.
    static func dayHours(count: Int) -> [Int] {
        guard count > 0 else { return [] }
        if count == 1 { return [14] }
        return (0..<count).map { index in
            Int((7 + 15 * Double(index) / Double(count - 1)).rounded(.toNearestOrAwayFromZero))
        }
    }
}

/// How the module arranges itself at a given outer width.
enum WeatherArrangement: Equatable {
    /// Current conditions on top, three upcoming hours below.
    case compact(hourCount: Int)
    /// Current conditions on the left, `hourCount` upcoming hours on the right.
    case wide(hourCount: Int)

    static let wideThreshold: CGFloat = 248
    static let cardPadding: CGFloat = 12
    static let currentPanelWidth: CGFloat = 96
    static let panelGap: CGFloat = 12
    static let minimumHourWidth: CGFloat = 36
    static let hourSpacing: CGFloat = 4

    /// The arrangement for a module `width` points wide, before capping the hour
    /// count by the hours the forecast has.
    static func forWidth(_ width: CGFloat) -> WeatherArrangement {
        guard width >= wideThreshold else { return .compact(hourCount: 3) }
        let hoursWidth = width - cardPadding * 2 - currentPanelWidth - panelGap
        let count = Int(((hoursWidth + hourSpacing) / (minimumHourWidth + hourSpacing)).rounded(.down))
        return .wide(hourCount: max(3, count))
    }

    var hourCount: Int {
        switch self {
        case .compact(let count), .wide(let count): count
        }
    }
}

/// When the module fetches the weather again.
enum WeatherRefreshPolicy {
    /// How long a report stays fresh.
    static let maximumAge: TimeInterval = 15 * 60
    /// How long to wait after a failed attempt before the next one.
    static let retryDelay: TimeInterval = 2 * 60
    /// How old a report's current conditions may be and still stay on screen
    /// after a failed refresh; older ones would pass for the weather now.
    static let maximumDisplayAge: TimeInterval = 2 * 60 * 60

    /// Whether a report whose current conditions are from `observedAt` may stay
    /// on screen at `now`.
    static func keepsReport(observedAt: Date, now: Date) -> Bool {
        now.timeIntervalSince(observedAt) < maximumDisplayAge
    }

    /// Whether to start a refresh at `now`: never while one is in flight, not
    /// within `retryDelay` of a failure newer than the last success, and otherwise
    /// when there is no report or it is `maximumAge` old.
    static func shouldRefresh(
        now: Date,
        lastSuccess: Date?,
        lastFailure: Date?,
        isInFlight: Bool
    ) -> Bool {
        if isInFlight { return false }
        if let lastFailure, lastSuccess.map({ lastFailure > $0 }) ?? true,
           now.timeIntervalSince(lastFailure) < retryDelay {
            return false
        }
        guard let lastSuccess else { return true }
        return now.timeIntervalSince(lastSuccess) >= maximumAge
    }
}

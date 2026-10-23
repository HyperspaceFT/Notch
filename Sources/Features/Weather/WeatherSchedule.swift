import Foundation
import NotchKit

/// What the Home weather module shows during one period of the day.
public enum WeatherDisplayMode: String, CaseIterable, Codable, Sendable {
    case today, upcoming, tomorrow

    @MainActor
    public var title: String {
        switch self {
        case .today: localized(en: "Today", zh: "今日天气")
        case .upcoming: localized(en: "Next Hours", zh: "未来几小时")
        case .tomorrow: localized(en: "Tomorrow", zh: "明日天气")
        }
    }

    public var symbol: String {
        switch self {
        case .today: "sun.max.fill"
        case .upcoming: "clock.fill"
        case .tomorrow: "moon.stars.fill"
        }
    }
}

/// The day split into three periods, each with the mode the weather module shows
/// during it. Times are minutes after midnight on the clock of whoever asks.
public struct WeatherSchedule: Equatable, Codable, Sendable {
    public static let periodCount = 3
    public static let minutesPerDay = 1440
    /// Boundaries snap to multiples of this many minutes.
    public static let step = 15
    /// The shortest period, in minutes.
    public static let minimumLength = 60

    /// 05:00 today's weather, 10:00 the next hours, 19:00 tomorrow's weather.
    public static let standard = WeatherSchedule(
        starts: [300, 600, 1140],
        modes: [.today, .upcoming, .tomorrow]
    )!

    /// Minute after midnight at which each period starts, in clockwise order
    /// around the day; period i lasts until the next one starts, wrapping past
    /// midnight. Not necessarily ascending: [1410, 600, 1140] is 23:30-10:00,
    /// 10:00-19:00 and 19:00-23:30.
    public private(set) var starts: [Int]
    public var modes: [WeatherDisplayMode]

    /// Nil unless there are exactly three starts and three modes, every start is
    /// in 0..<1440 and a multiple of `step`, and every period (cyclic) is at
    /// least `minimumLength` long with the three lengths adding up to exactly 1440.
    public init?(starts: [Int], modes: [WeatherDisplayMode]) {
        guard starts.count == Self.periodCount, modes.count == Self.periodCount,
              starts.allSatisfy({ (0..<Self.minutesPerDay).contains($0) && $0 % Self.step == 0 })
        else { return nil }
        let lengths = starts.indices.map { Self.wrap(starts[($0 + 1) % starts.count] - starts[$0]) }
        // Starts out of clockwise order wind around the day more than once.
        guard lengths.allSatisfy({ $0 >= Self.minimumLength }),
              lengths.reduce(0, +) == Self.minutesPerDay
        else { return nil }
        self.starts = starts
        self.modes = modes
    }

    private enum CodingKeys: String, CodingKey {
        case starts, modes
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let starts = try container.decode([Int].self, forKey: .starts)
        let modes = try container.decode([WeatherDisplayMode].self, forKey: .modes)
        guard let schedule = WeatherSchedule(starts: starts, modes: modes) else {
            throw DecodingError.dataCorruptedError(
                forKey: .starts, in: container, debugDescription: "Not a valid weather schedule")
        }
        self = schedule
    }

    /// Start of the next period.
    public func end(of period: Int) -> Int {
        starts[(period + 1) % Self.periodCount]
    }

    /// Minutes, around the circle.
    public func length(of period: Int) -> Int {
        Self.wrap(end(of: period) - starts[period])
    }

    /// The period containing `minute` (normalized mod 1440). A start belongs to
    /// the period it starts.
    public func period(atMinute minute: Int) -> Int {
        let minute = Self.wrap(minute)
        return (0..<Self.periodCount).first { Self.wrap(minute - starts[$0]) < length(of: $0) } ?? 0
    }

    public func mode(at date: Date, calendar: Calendar) -> WeatherDisplayMode {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let minute = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        return modes[period(atMinute: minute)]
    }

    /// Moves the start of `period` toward `minute` (normalized mod 1440 and
    /// snapped to the nearest multiple of `step`), keeping it at least
    /// `minimumLength` after the previous period's start and before the next
    /// period's start. A target outside that range stops at the nearer limit,
    /// measured around the circle.
    public mutating func moveStart(of period: Int, to minute: Int) {
        guard (0..<Self.periodCount).contains(period) else { return }
        let previous = starts[(period + Self.periodCount - 1) % Self.periodCount]
        let next = starts[(period + 1) % Self.periodCount]
        let snapped = Self.wrap(Int((Double(minute) / Double(Self.step)).rounded(.toNearestOrAwayFromZero)) * Self.step)
        // Offsets are measured from the previous period's start.
        let span = Self.wrap(next - previous)
        let low = Self.minimumLength
        let high = (span == 0 ? Self.minutesPerDay : span) - Self.minimumLength
        var offset = Self.wrap(snapped - previous)
        if !(low...high).contains(offset) {
            let distanceToHigh = Self.wrap(offset - high)
            let distanceToLow = Self.wrap(low - offset)
            offset = distanceToHigh <= distanceToLow ? high : low
        }
        starts[period] = Self.wrap(previous + offset)
    }

    /// Minute of day for an angle on a 24-hour dial: radians clockwise from the
    /// top (0 = midnight, pi/2 = 06:00, pi = 12:00), any value, normalized; not
    /// snapped.
    public static func minute(forAngle radians: Double) -> Int {
        let turns = radians / (2 * .pi)
        let fraction = turns - turns.rounded(.down)
        return wrap(Int((fraction * Double(minutesPerDay)).rounded()))
    }

    /// The inverse: radians clockwise from the top, in 0..<2pi.
    public static func angle(forMinute minute: Int) -> Double {
        Double(wrap(minute)) / Double(minutesPerDay) * 2 * .pi
    }

    private static func wrap(_ minute: Int) -> Int {
        ((minute % minutesPerDay) + minutesPerDay) % minutesPerDay
    }
}

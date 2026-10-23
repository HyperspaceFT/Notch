import Foundation
import Observation

/// One day's sunrise and sunset.
public struct SunTimes: Codable, Equatable, Sendable {
    public let sunrise: Date
    public let sunset: Date

    /// `nil` unless the sun sets less than a day after it rises, which leaves out
    /// polar days and nights.
    public init?(sunrise: Date, sunset: Date) {
        guard sunset > sunrise, sunset.timeIntervalSince(sunrise) < 24 * 3600 else { return nil }
        self.sunrise = sunrise
        self.sunset = sunset
    }
}

/// Sunrise and sunset at the user's location, as the weather feature last
/// learned them. The shell lights the expanded island's edge by them. Kept
/// across launches, so the light follows the sun before the next weather refresh.
@MainActor
@Observable
public final class Daylight {
    public static let shared = Daylight(defaults: .standard)

    static let sunTimesKey = "NotchSunTimes"

    /// The known days, earliest first; empty until a feature reports some.
    public private(set) var sunTimes: [SunTimes]

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
        sunTimes = defaults.data(forKey: Self.sunTimesKey)
            .flatMap { try? JSONDecoder().decode([SunTimes].self, from: $0) }?
            // Decoding skips the initializer's check.
            .compactMap { SunTimes(sunrise: $0.sunrise, sunset: $0.sunset) }
            ?? []
    }

    /// Replaces the known days. An empty list keeps the old ones, which still
    /// serve for a while: the sun rises and sets only a few minutes later or
    /// earlier from one day to the next.
    public func update(_ sunTimes: [SunTimes]) {
        let sorted = sunTimes.sorted { $0.sunrise < $1.sunrise }
        // Only a real change notifies observers.
        guard !sorted.isEmpty, sorted != self.sunTimes else { return }
        self.sunTimes = sorted
        if let data = try? JSONEncoder().encode(sorted) {
            defaults.set(data, forKey: Self.sunTimesKey)
        }
    }
}

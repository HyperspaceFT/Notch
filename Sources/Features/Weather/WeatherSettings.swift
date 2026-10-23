import Foundation
import Observation

/// When the Home weather module shows today's weather, the next hours, or
/// tomorrow's, as the settings window edits it.
@MainActor
@Observable
public final class WeatherSettings {
    public static let shared = WeatherSettings(defaults: .standard)

    static let scheduleKey = "NotchWeatherSchedule"

    /// Saved on every change; `WeatherSchedule.standard` until the user changes
    /// it or when the saved value does not decode.
    public var schedule: WeatherSchedule {
        didSet {
            if let data = try? JSONEncoder().encode(schedule) {
                defaults.set(data, forKey: Self.scheduleKey)
            }
        }
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
        schedule = defaults.data(forKey: Self.scheduleKey)
            .flatMap { try? JSONDecoder().decode(WeatherSchedule.self, from: $0) }
            ?? .standard
    }

    public func resetSchedule() {
        schedule = .standard
    }
}

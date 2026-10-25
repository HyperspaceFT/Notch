import Foundation
import Observation

/// Which providers the Usage tab and Home module show, as the settings window edits it.
@MainActor
@Observable
public final class UsageSettings {
    public static let shared = UsageSettings(defaults: .standard)

    static let providersKey = "NotchUsageProviders"

    /// In `UsageProvider.allCases` order; none until the user picks some.
    /// Saved as the providers' raw values; unknown saved values are ignored.
    public private(set) var shownProviders: [UsageProvider] {
        didSet { defaults.set(shownProviders.map(\.rawValue), forKey: Self.providersKey) }
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
        let saved = Set((defaults.array(forKey: Self.providersKey) ?? []).compactMap { $0 as? String })
        shownProviders = UsageProvider.allCases.filter { saved.contains($0.rawValue) }
    }

    public func isShown(_ provider: UsageProvider) -> Bool {
        shownProviders.contains(provider)
    }

    public func setProvider(_ provider: UsageProvider, shown: Bool) {
        guard shown != isShown(provider) else { return }
        shownProviders = UsageProvider.allCases.filter { $0 == provider ? shown : isShown($0) }
    }
}

import Foundation
import Observation

/// Whether the island draws its extra light and color: cards lit from above and
/// tinted by what they show, a sheen on large numbers, and an edge lit by the
/// sun and moon. Without it, cards are flat gray and the edge is unlit.
@MainActor
@Observable
public final class NotchAppearance {
    public static let shared = NotchAppearance(defaults: .standard)

    static let lightAndColorKey = "NotchLightAndColor"

    /// On by default.
    public var isLightAndColorEnabled: Bool {
        didSet { defaults.set(isLightAndColorEnabled, forKey: Self.lightAndColorKey) }
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
        isLightAndColorEnabled = defaults.object(forKey: Self.lightAndColorKey) as? Bool ?? true
    }
}

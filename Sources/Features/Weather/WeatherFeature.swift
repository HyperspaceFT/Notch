import NotchKit
import SwiftUI

/// Offers a Home module with the current weather and the next hours at the
/// user's approximate location, from Open-Meteo. Has no tab of its own. Each
/// report's sunrise and sunset go to `Daylight`, which lights the island's edge.
@MainActor
public final class WeatherFeature: NotchFeature {
    public let id = "weather"
    public var title: String { localized(en: "Weather", zh: "天气") }
    public let symbol = "cloud.sun"

    private let model = WeatherModel()

    public init() {}

    public func deactivate() {
        model.stop()
    }

    public func makeHomeModules() -> [NotchHomeModule] {
        [
            NotchHomeModule(
                id: "weather",
                title: { localized(en: "Weather", zh: "天气") },
                symbol: "cloud.sun.fill",
                detail: {
                    localized(
                        en: "Uses your approximate location. Weather data by Open-Meteo.com.",
                        zh: "使用你的大致位置，天气数据来自 Open-Meteo.com。"
                    )
                },
                sizing: .resizable(minimum: .fraction(1.0 / 3), maximum: nil),
                content: { [model] size in
                    AnyView(WeatherModuleView(model: model, size: size))
                }
            ),
        ]
    }
}

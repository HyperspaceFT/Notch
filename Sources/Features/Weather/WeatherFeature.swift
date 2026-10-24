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

    /// Sample reports and states for the Home module, which shows them while it is
    /// on Home and the panel is open, until "Use Real Weather" or the next normal
    /// refresh after fifteen minutes.
    public var debugItems: [NotchMenuItem] {
        let language = Localization.shared.language
        func conditions(isDay: Bool) -> [NotchMenuItem] {
            WeatherCondition.allCases.map { condition in
                .button(condition.label(in: language), symbol: condition.symbol(isDay: isDay)) { [model] in
                    model.showSample(WeatherSample.report(for: condition, isDay: isDay, now: Date()))
                }
            }
        }
        return [
            .submenu(localized(en: "Condition (Day)", zh: "天气状况（白天）"), symbol: "sun.max", items: conditions(isDay: true)),
            .submenu(localized(en: "Condition (Night)", zh: "天气状况（夜间）"), symbol: "moon.stars", items: conditions(isDay: false)),
            .submenu(localized(en: "Status", zh: "状态"), symbol: "exclamationmark.circle", items: [
                .button(localized(en: "Loading", zh: "加载中"), symbol: "hourglass") { [model] in
                    model.showStatus(.loading)
                },
                .button(localized(en: "Location Not Allowed", zh: "未允许定位"), symbol: "location.slash") { [model] in
                    model.showStatus(.locationNotAllowed)
                },
                .button(localized(en: "Failed to Load", zh: "加载失败"), symbol: "icloud.slash") { [model] in
                    model.showStatus(.failed)
                },
            ]),
            .divider,
            .button(localized(en: "Use Real Weather", zh: "恢复真实天气"), symbol: "arrow.clockwise") { [model] in
                model.useRealWeather()
            },
        ]
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

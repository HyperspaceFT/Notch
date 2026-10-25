import AirPodsFeature
import BatteryFeature
import CalendarFeature
import ClockFeature
import FilesFeature
import HomeFeature
import NotchKit
import NotesFeature
import NotificationsFeature
import NowPlayingFeature
import RemindersFeature
import SystemHUDFeature
import UsageFeature
import WeatherFeature

/// The one place that lists enabled features. Order = tab order in the expanded
/// panel, on each side of the notch (see `NotchFeature.tabPlacement`); a tab whose
/// feature reports `isTabAvailable == false` is skipped while it does.
///
/// Adding a feature:
/// 1. Create Sources/Features/<Name>/ with a type conforming to `NotchFeature`.
/// 2. Add "<Name>" to `featureNames` in Package.swift.
/// 3. Import `<Name>Feature` above and add an instance below.
///
/// Home comes first and is handed every other feature, so the modules any of them
/// offers through `makeHomeModules()` can be placed on the Home tab.
@MainActor
enum FeatureCatalog {
    static func makeFeatures() -> [any NotchFeature] {
        let features: [any NotchFeature] = [
            // First, so its clock is the first module Home registers and leads Home's standard layout.
            ClockFeature(),
            FilesFeature(),
            NowPlayingFeature(),
            AirPodsFeature(),
            BatteryFeature(),
            SystemHUDFeature(),
            WeatherFeature(),
            CalendarFeature(),
            NotesFeature(),
            UsageFeature(),
            RemindersFeature(),
            NotificationsFeature(),
        ]
        return [HomeFeature(moduleSources: features)] + features
    }
}

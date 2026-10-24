import AirPodsFeature
import BatteryFeature
import CalendarFeature
import FilesFeature
import HomeFeature
import NotchKit
import NotesFeature
import NowPlayingFeature
import RemindersFeature
import SystemHUDFeature
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
            FilesFeature(),
            NowPlayingFeature(),
            AirPodsFeature(),
            BatteryFeature(),
            SystemHUDFeature(),
            WeatherFeature(),
            CalendarFeature(),
            NotesFeature(),
            RemindersFeature(),
        ]
        return [HomeFeature(moduleSources: features)] + features
    }
}

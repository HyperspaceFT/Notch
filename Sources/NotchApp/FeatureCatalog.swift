import AirPodsFeature
import BatteryFeature
import FilesFeature
import HomeFeature
import NotchKit
import SystemHUDFeature

/// The one place that lists enabled features. Order = tab order in the expanded
/// panel, on each side of the notch (see `NotchFeature.tabPlacement`); a tab whose
/// feature reports `isTabAvailable == false` is skipped while it does.
///
/// Adding a feature:
/// 1. Create Sources/Features/<Name>/ with a type conforming to `NotchFeature`.
/// 2. Add "<Name>" to `featureNames` in Package.swift.
/// 3. Import `<Name>Feature` above and add an instance below.
@MainActor
enum FeatureCatalog {
    static func makeFeatures() -> [any NotchFeature] {
        [
            AirPodsFeature(),
            HomeFeature(),
            FilesFeature(),
            BatteryFeature(),
            SystemHUDFeature(),
        ]
    }
}

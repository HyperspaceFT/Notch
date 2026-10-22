import BatteryFeature
import FilesFeature
import HomeFeature
import NotchKit

/// The one place that lists enabled features. Order = tab order in the expanded
/// panel, on each side of the notch (see `NotchFeature.tabPlacement`).
///
/// Adding a feature:
/// 1. Create Sources/Features/<Name>/ with a type conforming to `NotchFeature`.
/// 2. Add "<Name>" to `featureNames` in Package.swift.
/// 3. Import `<Name>Feature` above and add an instance below.
@MainActor
enum FeatureCatalog {
    static func makeFeatures() -> [any NotchFeature] {
        [
            HomeFeature(),
            FilesFeature(),
            BatteryFeature(),
        ]
    }
}

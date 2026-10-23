// swift-tools-version: 6.2
import PackageDescription

// Enabled feature modules. Each name maps to the folder Sources/Features/<Name>
// and produces a target called "<Name>Feature" that may depend only on
// NotchKit and NotchUI. To add a feature: create the folder, add its name here,
// and list an instance in Sources/NotchApp/FeatureCatalog.swift.
let featureNames = [
    "AirPods",
    "Battery",
    "Calendar",
    "Files",
    "Home",
    "SystemHUD",
    "Weather",
]

let featureTargets: [Target] = featureNames.map { name in
    .target(
        name: "\(name)Feature",
        dependencies: ["NotchKit", "NotchUI"],
        path: "Sources/Features/\(name)"
    )
}

let package = Package(
    name: "Notch",
    platforms: [.macOS(.v26)],
    products: [
        // The product name determines the binary name inside Notch.app.
        .executable(name: "Notch", targets: ["NotchApp"]),
    ],
    targets: [
        // Public contract that features depend on. No window code.
        .target(name: "NotchKit"),
        // Design system: shape, theme, reusable controls.
        .target(name: "NotchUI"),
        // Window, hover, state machine, and feature hosting.
        .target(name: "NotchShell", dependencies: ["NotchKit", "NotchUI"]),
        .executableTarget(
            name: "NotchApp",
            dependencies: ["NotchKit", "NotchShell"]
                + featureNames.map { .target(name: "\($0)Feature") }
        ),
        .testTarget(name: "NotchKitTests", dependencies: ["NotchKit"]),
        .testTarget(name: "NotchShellTests", dependencies: ["NotchShell", "NotchKit"]),
        .testTarget(name: "SystemHUDFeatureTests", dependencies: ["SystemHUDFeature"]),
        .testTarget(name: "AirPodsFeatureTests", dependencies: ["AirPodsFeature"]),
        .testTarget(name: "WeatherFeatureTests", dependencies: ["WeatherFeature"]),
        .testTarget(name: "HomeFeatureTests", dependencies: ["HomeFeature"]),
        .testTarget(name: "CalendarFeatureTests", dependencies: ["CalendarFeature"]),
    ] + featureTargets,
    swiftLanguageModes: [.v6]
)

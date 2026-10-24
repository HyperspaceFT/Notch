import Foundation

/// A pair of AirPods the Debug pane connects (`AirPodsModel.showSample`): what
/// the wings and the tab show about it, with no device behind it.
struct AirPodsSample: Equatable, Sendable {
    var connection: AirPodsModel.Connection
    var battery: AirPodsBattery
    var volume: Float?
    var supportedModes: [ListeningMode]
    var listeningMode: ListeningMode?

    /// Both buds and the case, at different levels.
    static let pro = AirPodsSample(
        connection: AirPodsModel.Connection(address: nil, name: "AirPods Pro", product: proProduct),
        battery: AirPodsBattery(left: 86, right: 74, chargingCase: 58),
        volume: 0.6,
        supportedModes: ListeningMode.allCases,
        listeningMode: .noiseCancellation
    )

    /// One battery and no case.
    static let max = AirPodsSample(
        connection: AirPodsModel.Connection(
            address: nil,
            name: "AirPods Max",
            product: AirPodsProduct(symbol: "airpods.max", hasSingleBattery: true)
        ),
        battery: AirPodsBattery(single: 67),
        volume: 0.45,
        supportedModes: [.noiseCancellation, .transparency],
        listeningMode: .transparency
    )

    /// Buds and case at or below the 20 % the views mark in red.
    static let lowBattery = AirPodsSample(
        connection: AirPodsModel.Connection(address: nil, name: "AirPods Pro", product: proProduct),
        battery: AirPodsBattery(left: 12, right: 18, chargingCase: 9),
        volume: 0.6,
        supportedModes: ListeningMode.allCases,
        listeningMode: .adaptive
    )

    private static let proProduct = AirPodsProduct(symbol: "airpods.pro", hasSingleBattery: false)
}

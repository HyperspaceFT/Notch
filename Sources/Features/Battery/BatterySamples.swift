import Foundation

/// Statuses the Debug pane shows (`BatteryFeature.debugItems`) in place of what
/// macOS reports.
extension PowerStatus {
    /// The adapter just plugged in, charging.
    static let samplePluggedIn = PowerStatus(
        percent: 64,
        isOnACPower: true,
        isCharging: true,
        isCharged: false,
        minutesToEmpty: nil,
        minutesToFull: 48
    )

    /// The adapter just removed, with hours left.
    static let sampleUnplugged = PowerStatus(
        percent: 64,
        isOnACPower: false,
        isCharging: false,
        isCharged: false,
        minutesToEmpty: 312,
        minutesToFull: nil
    )

    /// On battery at or below the 20 % the card marks in red.
    static let sampleLow = PowerStatus(
        percent: 12,
        isOnACPower: false,
        isCharging: false,
        isCharged: false,
        minutesToEmpty: 38,
        minutesToFull: nil
    )
}

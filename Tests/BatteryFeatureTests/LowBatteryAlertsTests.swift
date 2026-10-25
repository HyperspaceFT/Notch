import Testing
@testable import BatteryFeature

struct LowBatteryAlertsTests {
    private func battery(_ percent: Int, onPower: Bool = false) -> PowerStatus {
        PowerStatus(
            percent: percent,
            isOnACPower: onPower,
            isCharging: onPower && percent < 100,
            isCharged: onPower && percent == 100,
            minutesToEmpty: nil,
            minutesToFull: nil
        )
    }

    /// The levels `alerts` reports while the charge on battery steps through `percents`.
    private func alerts(_ alerts: inout LowBatteryAlerts, discharging percents: [Int]) -> [Int] {
        percents.compactMap { alerts.update(with: battery($0)) }
    }

    @Test func eachLevelAlertsOnceOnTheWayDown() {
        var alerts = LowBatteryAlerts(status: battery(25))
        #expect(self.alerts(&alerts, discharging: Array((2...24).reversed())) == [20, 10, 5])
    }

    @Test func aReadingThatWaversAroundALevelAlertsOnce() {
        var alerts = LowBatteryAlerts(status: battery(22))
        #expect(self.alerts(&alerts, discharging: [21, 20, 21, 20, 19, 20]) == [20])
    }

    @Test func aDropPastSeveralLevelsAlertsForTheLowest() {
        var alerts = LowBatteryAlerts(status: battery(22))
        // Across a sleep, say.
        #expect(alerts.update(with: battery(8)) == 10)
        #expect(self.alerts(&alerts, discharging: [7, 6, 5, 4]) == [5])
    }

    @Test func levelsAlreadyPassedAtLaunchStayQuiet() {
        var alerts = LowBatteryAlerts(status: battery(15))
        #expect(self.alerts(&alerts, discharging: [15, 14, 12, 11, 10, 9]) == [10])

        var low = LowBatteryAlerts(status: battery(4))
        #expect(self.alerts(&low, discharging: [4, 3, 2]).isEmpty)
    }

    @Test func chargingAboveALevelOnPowerAlertsForItAgain() {
        var alerts = LowBatteryAlerts(status: battery(22))
        #expect(alerts.update(with: battery(18)) == 20)

        // Plugged in at 18% and charged only to 19%: 20% stays passed.
        #expect(alerts.update(with: battery(18, onPower: true)) == nil)
        #expect(alerts.update(with: battery(19, onPower: true)) == nil)
        #expect(self.alerts(&alerts, discharging: [19, 18]).isEmpty)

        // Charged past it, then unplugged.
        #expect(alerts.update(with: battery(25, onPower: true)) == nil)
        #expect(self.alerts(&alerts, discharging: [25, 21, 20]) == [20])
    }

    @Test func itNeverAlertsOnPower() {
        var alerts = LowBatteryAlerts(status: battery(30, onPower: true))
        // Plugged in but not charging enough to keep up.
        for percent in (3...29).reversed() {
            #expect(alerts.update(with: battery(percent, onPower: true)) == nil)
        }
    }

    @Test func aMacWithoutABatteryNeverAlerts() {
        var alerts = LowBatteryAlerts(status: nil)
        #expect(alerts.passed.isEmpty)
        #expect(alerts.update(with: nil) == nil)
    }
}

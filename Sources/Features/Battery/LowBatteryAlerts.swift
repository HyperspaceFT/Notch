/// Which low-charge alerts are due: one each time the charge on battery falls to
/// 20, 10, and 5 percent. A level that alerted, or that the charge was already
/// at or below when watching began, stays quiet until the Mac charges above it
/// on power, so a reading that wavers around a level on battery alerts once.
struct LowBatteryAlerts {
    /// Charge levels, in percent, that each alert once on the way down.
    static let levels = [20, 10, 5]

    /// Levels that alerted or were passed before watching began, and have not
    /// been charged above since.
    private(set) var passed: Set<Int>

    /// Starts from `status` without alerting: the levels it is already at or
    /// below count as passed, so launching on a low battery stays quiet until the
    /// next level down.
    init(status: PowerStatus?) {
        passed = Set(Self.levels.filter { level in status.map { $0.percent <= level } ?? false })
    }

    /// Takes a new reading. Returns the level to alert for, or `nil`: when the
    /// charge fell past several levels since the last reading (say, across a
    /// sleep), only the lowest of them alerts.
    mutating func update(with status: PowerStatus?) -> Int? {
        guard let status else { return nil }
        if status.isOnACPower {
            passed = passed.filter { status.percent <= $0 }
            return nil
        }
        let reached = Self.levels.filter { status.percent <= $0 && !passed.contains($0) }
        passed.formUnion(reached)
        return reached.min()
    }
}

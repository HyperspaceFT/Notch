import NotchKit
import NotchUI
import Observation
import SwiftUI

/// Shows a short activity when the power adapter is plugged in or removed, and a
/// battery button right of the notch in the expanded panel whose tab shows the
/// remaining time and the battery health.
@MainActor
public final class BatteryFeature: NotchFeature {
    public let id = "battery"
    public var title: String { localized(en: "Battery", zh: "电池") }
    /// Follows the charge level, so the header button doubles as a battery gauge.
    public var symbol: String { model.status?.symbolName ?? "battery.75percent" }
    public let tabPlacement = NotchTabPlacement.trailing

    /// How long the plug/unplug activity stays visible.
    static let activityDuration: TimeInterval = 3

    private let model = BatteryModel()
    private var monitor: PowerSourceMonitor?
    private weak var context: (any NotchContext)?

    public init() {}

    public func activate(context: any NotchContext) {
        self.context = context
        model.status = PowerStatus.read()
        if model.status != nil {
            model.refreshHealth()
        }

        let monitor = PowerSourceMonitor { [weak self] in
            self?.powerSourcesChanged()
        }
        monitor.start()
        self.monitor = monitor
    }

    public func deactivate() {
        monitor?.stop()
        monitor = nil
        context = nil
    }

    public func makeExpandedView() -> AnyView? {
        AnyView(BatteryExpandedView(model: model))
    }

    private func powerSourcesChanged() {
        let previous = model.status
        let current = PowerStatus.read()
        model.status = current

        // Only the adapter being connected or removed is worth an activity;
        // routine percentage updates just refresh the expanded card.
        guard let previous, let current, previous.isOnACPower != current.isOnACPower else { return }
        context?.present(NotchActivity(
            id: "power-adapter",
            priority: .high,
            duration: Self.activityDuration
        ) {
            BatteryActivityLeading(status: current)
        } trailing: {
            BatteryActivityTrailing(status: current)
        })
    }
}

@MainActor
@Observable
final class BatteryModel {
    /// How long a health reading stays current; battery wear changes over weeks.
    static let healthMaxAge: TimeInterval = 60 * 60

    var status: PowerStatus?
    /// `nil` until the first reading finishes, and when every reading failed.
    private(set) var health: BatteryHealth?
    private(set) var isReadingHealth = false
    @ObservationIgnored private var healthReadAt: Date?

    /// Reads the battery health again unless a reading is underway or still current.
    func refreshHealth() {
        guard !isReadingHealth else { return }
        if let healthReadAt, Date().timeIntervalSince(healthReadAt) < Self.healthMaxAge { return }
        isReadingHealth = true
        Task {
            // A failed reading keeps the previous one and is retried on the next refresh.
            if let reading = await BatteryHealth.read() {
                health = reading
                healthReadAt = Date()
            }
            isReadingHealth = false
        }
    }
}

// Main actor: the strings follow the interface language.
@MainActor
extension PowerStatus {
    /// SF Symbol matching the charge level (bolt variant while on AC power).
    var symbolName: String {
        if isOnACPower { return "battery.100percent.bolt" }
        switch percent {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    var tint: Color {
        if isCharging || isOnACPower { return NotchTheme.chargingColor }
        return percent <= 20 ? .red : NotchTheme.primaryText
    }

    /// Title of the remaining-time card; its headline counts down to full while charging.
    var remainingTitle: String {
        isCharging ? localized(en: "Until Full", zh: "充满还需") : localized(en: "Time Remaining", zh: "剩余时间")
    }

    /// The time left, or the power state when there is no time to show.
    var remainingHeadline: String {
        let estimating = localized(en: "Estimating…", zh: "正在估算…")
        if isCharging { return minutesToFull.map(Self.format) ?? estimating }
        if isOnACPower { return localized(en: "Plugged In", zh: "已接通电源") }
        return minutesToEmpty.map(Self.format) ?? estimating
    }

    var remainingCaption: String {
        let level = localized(en: "\(percent)% charged", zh: "电量 \(percent)%")
        if isCharging { return "\(localized(en: "Charging", zh: "正在充电")) · \(level)" }
        if isOnACPower {
            let state = isCharged
                ? localized(en: "Fully Charged", zh: "已充满")
                : localized(en: "Not Charging", zh: "未在充电")
            return "\(state) · \(level)"
        }
        return "\(localized(en: "On Battery", zh: "使用电池")) · \(level)"
    }

    private static func format(minutes: Int) -> String {
        let hours = minutes / 60
        let rest = minutes % 60
        return hours > 0
            ? localized(en: "\(hours) hr \(rest) min", zh: "\(hours) 小时 \(rest) 分钟")
            : localized(en: "\(rest) min", zh: "\(rest) 分钟")
    }
}

@MainActor
extension BatteryHealth {
    var summary: String {
        var parts: [String] = []
        if let isNormal {
            parts.append(isNormal
                ? localized(en: "Normal", zh: "状态正常")
                : localized(en: "Service Recommended", zh: "建议维修"))
        }
        if let cycleCount {
            parts.append(localized(en: "\(cycleCount) cycles", zh: "循环 \(cycleCount) 次"))
        }
        return parts.joined(separator: " · ")
    }
}

private struct BatteryActivityLeading: View {
    let status: PowerStatus

    var body: some View {
        Image(systemName: status.isOnACPower ? "bolt.fill" : "battery.75percent")
            .foregroundStyle(status.isOnACPower ? NotchTheme.chargingColor : NotchTheme.primaryText)
            .symbolEffect(.bounce, options: .nonRepeating)
    }
}

private struct BatteryActivityTrailing: View {
    let status: PowerStatus

    var body: some View {
        Text("\(status.percent)%")
            .monospacedDigit()
            .foregroundStyle(status.isOnACPower ? NotchTheme.chargingColor : NotchTheme.primaryText)
    }
}

private struct BatteryExpandedView: View {
    let model: BatteryModel

    var body: some View {
        if let status = model.status {
            HStack(spacing: 10) {
                NotchCard(title: status.remainingTitle) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(status.remainingHeadline)
                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(status.tint)
                            .contentTransition(.numericText())
                        Text(status.remainingCaption)
                            .font(.system(size: 12))
                            .foregroundStyle(NotchTheme.secondaryText)
                    }
                    .animation(.smooth, value: status)
                }
                NotchCard(title: localized(en: "Battery Health", zh: "电池健康")) {
                    BatteryHealthView(health: model.health, isReading: model.isReadingHealth)
                }
            }
            .onAppear { model.refreshHealth() }
        } else {
            NotchCard(title: localized(en: "Battery", zh: "电池")) {
                Text(localized(en: "This Mac has no built-in battery", zh: "这台 Mac 没有内置电池"))
                    .font(.system(size: 12))
                    .foregroundStyle(NotchTheme.secondaryText)
            }
        }
    }
}

private struct BatteryHealthView: View {
    let health: BatteryHealth?
    let isReading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let health {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(health.maximumCapacity.map { "\($0)%" } ?? "—")
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text(localized(en: "Maximum Capacity", zh: "最大容量"))
                        .font(.system(size: 12))
                        .foregroundStyle(NotchTheme.secondaryText)
                }
                Text(health.summary)
                    .font(.system(size: 12))
                    .foregroundStyle(NotchTheme.secondaryText)
            } else {
                Text(isReading ? localized(en: "Reading…", zh: "正在读取…") : localized(en: "Unavailable", zh: "无法读取"))
                    .font(.system(size: 12))
                    .foregroundStyle(NotchTheme.secondaryText)
            }
        }
    }
}

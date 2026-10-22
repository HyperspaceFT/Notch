import NotchKit
import NotchUI
import Observation
import SwiftUI

/// Shows a short activity when the power adapter is plugged in or removed, and a
/// battery card in the expanded panel.
@MainActor
public final class BatteryFeature: NotchFeature {
    public let id = "battery"
    public let title = "电池"
    public let symbol = "battery.75percent"

    /// How long the plug/unplug activity stays visible.
    static let activityDuration: TimeInterval = 3

    private let model = BatteryModel()
    private var monitor: PowerSourceMonitor?
    private weak var context: (any NotchContext)?

    public init() {}

    public func activate(context: any NotchContext) {
        self.context = context
        model.status = PowerStatus.read()

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
    var status: PowerStatus?
}

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

    var stateDescription: String {
        if isCharged { return "已充满" }
        if isCharging { return "正在充电" }
        if isOnACPower { return "已接通电源" }
        return "使用电池"
    }

    var remainingDescription: String? {
        if isCharging, let minutes = minutesToFull {
            return "充满还需 \(Self.format(minutes: minutes))"
        }
        if !isOnACPower, let minutes = minutesToEmpty {
            return "剩余 \(Self.format(minutes: minutes))"
        }
        return nil
    }

    private static func format(minutes: Int) -> String {
        let hours = minutes / 60
        let rest = minutes % 60
        return hours > 0 ? "\(hours) 小时 \(rest) 分钟" : "\(rest) 分钟"
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
        NotchCard(title: "电池") {
            if let status = model.status {
                HStack(spacing: 14) {
                    Image(systemName: status.symbolName)
                        .font(.system(size: 34, weight: .regular))
                        .foregroundStyle(status.tint)
                        .contentTransition(.symbolEffect(.replace))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(status.percent)%")
                            .font(.system(size: 26, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                        Text(status.stateDescription)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(NotchTheme.secondaryText)
                        if let remaining = status.remainingDescription {
                            Text(remaining)
                                .font(.system(size: 12))
                                .foregroundStyle(NotchTheme.secondaryText)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .animation(.smooth, value: status)
            } else {
                Text("这台 Mac 没有内置电池")
                    .font(.system(size: 12))
                    .foregroundStyle(NotchTheme.secondaryText)
            }
        }
    }
}

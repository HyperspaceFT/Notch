import NotchKit
import NotchUI
import SwiftUI

/// The Usage tab's icon: a gauge whose arc and needle show the highest percent
/// among the displayed providers, yellow from 70% and red from 90%.
struct UsageTabIcon: View {
    let model: UsageModel
    @Environment(\.notchTabIsSelected) private var isSelected

    var body: some View {
        let percent = model.highestPercent
        UsageGauge(
            fraction: min(max((percent ?? 0) / 100, 0), 1),
            color: isSelected ? NotchTheme.primaryText : NotchTheme.secondaryText,
            fill: percent.flatMap { UsageLevel(percent: $0).color }
        )
        .frame(width: 18, height: 18)
        .animation(.smooth, value: percent)
    }
}

/// A 270° arc open at the bottom, filled clockwise from its lower-left end,
/// with a needle from the center to where the fill ends.
private struct UsageGauge: View {
    let fraction: Double
    let color: Color
    /// The fill's color past 70%; `nil` uses `color`.
    let fill: Color?

    /// The arc starts at the lower left (135° clockwise from 3 o'clock) and spans 270°.
    static let startAngle: Double = 135
    static let sweep: Double = 270
    static let lineWidth: CGFloat = 2

    var body: some View {
        ZStack {
            arc(to: 1)
                .stroke(color.opacity(0.3), style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round))
            if fraction > 0 {
                arc(to: fraction)
                    .stroke(fill ?? color, style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round))
            }
            Needle(angle: .degrees(Self.startAngle + Self.sweep * fraction))
                .stroke(fill ?? color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            Circle()
                .fill(fill ?? color)
                .frame(width: 2, height: 2)
        }
    }

    private func arc(to fraction: Double) -> some Shape {
        Circle()
            .inset(by: Self.lineWidth / 2)
            .trim(from: 0, to: Self.sweep / 360 * fraction)
            .rotation(.degrees(Self.startAngle))
    }
}

/// A short line from the center toward `angle` (clockwise from 3 o'clock).
private struct Needle: Shape {
    var angle: Angle

    var animatableData: Double {
        get { angle.radians }
        set { angle = .radians(newValue) }
    }

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let length = min(rect.width, rect.height) / 2 - 4
        var path = Path()
        path.move(to: center)
        path.addLine(to: CGPoint(
            x: center.x + length * cos(angle.radians),
            y: center.y + length * sin(angle.radians)
        ))
        return path
    }
}

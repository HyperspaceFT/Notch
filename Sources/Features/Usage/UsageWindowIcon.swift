import SwiftUI

/// A limit window's icon, drawn by Notch: a clock whose wedge covers the
/// window's hours on the dial for one shorter than a day (the 5-hour session),
/// a small calendar showing its number of days for a day or longer ("7" for
/// weekly), and a gauge when the length is unknown.
struct UsageWindowIcon: View {
    let duration: TimeInterval?
    let size: CGFloat
    let color: Color

    /// The share of the twelve-hour dial a window covers: 5 hours → 5/12, at
    /// most the whole dial.
    static func wedgeFraction(duration: TimeInterval) -> Double {
        min(max(duration / (12 * 3600), 0), 1)
    }

    var body: some View {
        Group {
            if let duration, duration > 0, duration < 86400 {
                clock(fraction: Self.wedgeFraction(duration: duration))
            } else if let duration, duration >= 86400 {
                calendar(days: Int((duration / 86400).rounded()))
            } else {
                Image(systemName: "gauge.with.needle")
                    .font(.system(size: size * 0.9))
                    .foregroundStyle(color)
            }
        }
        .frame(width: size, height: size)
    }

    private func clock(fraction: Double) -> some View {
        let lineWidth = size * 0.11
        return ZStack {
            Circle()
                .strokeBorder(color, lineWidth: lineWidth)
            Wedge(fraction: fraction)
                .fill(color.opacity(0.6))
                .padding(lineWidth * 1.6)
            Circle()
                .fill(color)
                .frame(width: size * 0.16, height: size * 0.16)
        }
    }

    private func calendar(days: Int) -> some View {
        let lineWidth = size * 0.09
        let shape = RoundedRectangle(cornerRadius: size * 0.2, style: .continuous)
        return ZStack(alignment: .top) {
            shape.strokeBorder(color, lineWidth: lineWidth)
            Rectangle()
                .fill(color)
                .frame(height: size * 0.26)
                .clipShape(shape)
            Text("\(days)")
                .font(.system(size: size * 0.5, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, size * 0.22)
        }
    }
}

/// A pie slice from 12 o'clock clockwise over `fraction` of the circle.
private struct Wedge: Shape {
    var fraction: Double

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        var path = Path()
        guard fraction > 0 else { return path }
        path.move(to: center)
        // Screen coordinates: clockwise on screen is the increasing angle.
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(-90),
            endAngle: .degrees(-90 + 360 * fraction),
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}

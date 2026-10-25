import SwiftUI

/// A battery drawn in the foreground style, sized like the SF Symbols battery at
/// the 13-point font of the tab buttons and wings: an outline whose fill is
/// `percent` of it, with a bolt cut into it while on power. The symbols only come
/// in quarters, and their bolt variant always shows a full battery.
struct BatteryIcon: View {
    let percent: Int
    let showsBolt: Bool

    static let size = CGSize(width: 20, height: 10)

    var body: some View {
        Canvas { context, size in
            // A layer of its own, so the bolt's cut clears only the battery.
            context.drawLayer { layer in
                let lineWidth: CGFloat = 1.4
                let nubSize = CGSize(width: 1.5, height: 3.5)
                let outline = CGRect(x: 0, y: 0, width: size.width - nubSize.width - 1, height: size.height)
                    .insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
                layer.stroke(Path(roundedRect: outline, cornerRadius: 3), with: .foreground, lineWidth: lineWidth)
                let nub = CGRect(
                    x: size.width - nubSize.width,
                    y: (size.height - nubSize.height) / 2,
                    width: nubSize.width,
                    height: nubSize.height
                )
                layer.fill(Path(roundedRect: nub, cornerRadius: nubSize.width / 2), with: .foreground)

                let inner = outline.insetBy(dx: lineWidth / 2 + 1.1, dy: lineWidth / 2 + 1.1)
                let fraction = Self.fillFraction(percent: percent)
                if fraction > 0 {
                    var level = inner
                    // A sliver stays visible down to 1 %.
                    level.size.width = max(inner.width * fraction, 1.5)
                    layer.fill(Path(roundedRect: level, cornerRadius: 1.2), with: .foreground)
                }

                if showsBolt {
                    let bolt = Self.bolt(in: CGRect(x: outline.midX - 2.5, y: outline.midY - 3.75, width: 5, height: 7.5))
                    var cut = layer
                    cut.blendMode = .destinationOut
                    cut.stroke(bolt, with: .color(.black), style: StrokeStyle(lineWidth: 1.6, lineJoin: .round))
                    layer.fill(bolt, with: .foreground)
                }
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .accessibilityElement()
        .accessibilityLabel(Text("\(percent)%"))
    }

    /// The share of the battery the fill covers.
    static func fillFraction(percent: Int) -> CGFloat {
        CGFloat(min(max(percent, 0), 100)) / 100
    }

    /// A lightning bolt filling `rect`.
    private static func bolt(in rect: CGRect) -> Path {
        let points: [(x: CGFloat, y: CGFloat)] = [
            (0.60, 0), (0.05, 0.56), (0.45, 0.56), (0.38, 1), (0.95, 0.42), (0.55, 0.42),
        ]
        var path = Path()
        path.addLines(points.map { CGPoint(x: rect.minX + $0.x * rect.width, y: rect.minY + $0.y * rect.height) })
        path.closeSubpath()
        return path
    }
}

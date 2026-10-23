import SwiftUI

/// The island outline.
///
/// The top edge is flush with the top of the screen. At the two top corners the
/// outline flares outward with small concave "ears" (radius `topCornerRadius`),
/// so the island looks like it grows out of the menu bar. The bottom corners are
/// convex and rounded with `bottomCornerRadius`.
///
/// The ears sit inside the shape's rect: the island body is the rect inset
/// horizontally by `topCornerRadius` on each side. Use
/// `NotchShape.frameWidth(bodyWidth:topCornerRadius:)` to size the frame.
///
/// Both radii are animatable so the outline morphs smoothly between states.
public struct NotchShape: Shape {
    public var topCornerRadius: CGFloat
    public var bottomCornerRadius: CGFloat

    public init(topCornerRadius: CGFloat, bottomCornerRadius: CGFloat) {
        self.topCornerRadius = topCornerRadius
        self.bottomCornerRadius = bottomCornerRadius
    }

    public var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topCornerRadius, bottomCornerRadius) }
        set {
            topCornerRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    /// Width of the shape's frame for a given body width (body plus both ears).
    public static func frameWidth(bodyWidth: CGFloat, topCornerRadius: CGFloat) -> CGFloat {
        bodyWidth + topCornerRadius * 2
    }

    /// The radii as drawn in `rect`. Clamped so extreme sizes during a morph never
    /// produce a self-intersecting path.
    static func clampedRadii(top: CGFloat, bottom: CGFloat, in rect: CGRect) -> (top: CGFloat, bottom: CGFloat) {
        let top = max(0, min(top, rect.width / 4, rect.height / 2))
        let bottom = max(0, min(bottom, (rect.width - top * 2) / 2, rect.height - top))
        return (top, bottom)
    }

    public func path(in rect: CGRect) -> Path {
        let (top, bottom) = Self.clampedRadii(top: topCornerRadius, bottom: bottomCornerRadius, in: rect)

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        // Left ear: concave curve from the top edge down into the body's left side.
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + top, y: rect.minY + top),
            control: CGPoint(x: rect.minX + top, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.minX + top, y: rect.maxY - bottom))
        // Bottom-left convex corner.
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + top + bottom, y: rect.maxY),
            control: CGPoint(x: rect.minX + top, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - top - bottom, y: rect.maxY))
        // Bottom-right convex corner.
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - top, y: rect.maxY - bottom),
            control: CGPoint(x: rect.maxX - top, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - top, y: rect.minY + top))
        // Right ear.
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - top, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}

/// The sides and bottom of the island outline (`NotchShape`) as an open path:
/// from the left side at `horizon`, a share of the height from the top, down
/// around the bottom and up the right side to the same height. It leaves out
/// the ears and the top edge, so a stroke trimmed along it lights only the
/// lower edge.
public struct NotchEdge: Shape {
    public var topCornerRadius: CGFloat
    public var bottomCornerRadius: CGFloat
    public var horizon: CGFloat

    public init(topCornerRadius: CGFloat, bottomCornerRadius: CGFloat, horizon: CGFloat) {
        self.topCornerRadius = topCornerRadius
        self.bottomCornerRadius = bottomCornerRadius
        self.horizon = horizon
    }

    public var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topCornerRadius, bottomCornerRadius) }
        set {
            topCornerRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    public func path(in rect: CGRect) -> Path {
        let (top, bottom) = NotchShape.clampedRadii(top: topCornerRadius, bottom: bottomCornerRadius, in: rect)
        // Below the ears, and above the bottom corners.
        let start = min(max(rect.minY + rect.height * horizon, rect.minY + top), rect.maxY - bottom)

        var path = Path()
        path.move(to: CGPoint(x: rect.minX + top, y: start))
        path.addLine(to: CGPoint(x: rect.minX + top, y: rect.maxY - bottom))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + top + bottom, y: rect.maxY),
            control: CGPoint(x: rect.minX + top, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - top - bottom, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - top, y: rect.maxY - bottom),
            control: CGPoint(x: rect.maxX - top, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - top, y: start))
        return path
    }
}

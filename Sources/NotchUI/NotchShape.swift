import SwiftUI

/// The island outline.
///
/// The top edge is flush with the top of the screen. At the two top corners the
/// outline flares outward with small concave "ears" (radius `topCornerRadius`),
/// so the island looks like it grows out of the menu bar. The bottom corners are
/// convex and rounded with `bottomCornerRadii`.
///
/// The ears sit inside the shape's rect: the island body is the rect inset
/// horizontally by `topCornerRadius` on each side. Use
/// `NotchShape.frameWidth(bodyWidth:topCornerRadius:)` to size the frame.
///
/// All radii are animatable so the outline morphs smoothly between states.
public struct NotchShape: Shape {
    public var topCornerRadius: CGFloat
    /// How far each bottom corner reaches along the bottom edge (`width`) and up
    /// the side (`height`); equal for a round corner. The hovered island grows
    /// more to the sides than down and stretches its corners by the same amounts,
    /// so they keep the center of the corners they grew from.
    public var bottomCornerRadii: CGSize

    public init(topCornerRadius: CGFloat, bottomCornerRadius: CGFloat) {
        self.init(
            topCornerRadius: topCornerRadius,
            bottomCornerRadii: CGSize(width: bottomCornerRadius, height: bottomCornerRadius)
        )
    }

    public init(topCornerRadius: CGFloat, bottomCornerRadii: CGSize) {
        self.topCornerRadius = topCornerRadius
        self.bottomCornerRadii = bottomCornerRadii
    }

    public var animatableData: AnimatablePair<CGFloat, CGSize.AnimatableData> {
        get { AnimatablePair(topCornerRadius, bottomCornerRadii.animatableData) }
        set {
            topCornerRadius = newValue.first
            bottomCornerRadii.animatableData = newValue.second
        }
    }

    /// Width of the shape's frame for a given body width (body plus both ears).
    public static func frameWidth(bodyWidth: CGFloat, topCornerRadius: CGFloat) -> CGFloat {
        bodyWidth + topCornerRadius * 2
    }

    /// The radii as drawn in `rect`. Clamped so extreme sizes during a morph never
    /// produce a self-intersecting path; the bottom corners shrink in proportion,
    /// so a round one stays round.
    static func clampedRadii(top: CGFloat, bottom: CGSize, in rect: CGRect) -> (top: CGFloat, bottom: CGSize) {
        let top = max(0, min(top, rect.width / 4, rect.height / 2))
        let room = CGSize(width: (rect.width - top * 2) / 2, height: rect.height - top)
        let scale = min(
            1,
            bottom.width > 0 ? room.width / bottom.width : 1,
            bottom.height > 0 ? room.height / bottom.height : 1
        )
        return (top, CGSize(width: max(0, bottom.width * scale), height: max(0, bottom.height * scale)))
    }

    public func path(in rect: CGRect) -> Path {
        let (top, bottom) = Self.clampedRadii(top: topCornerRadius, bottom: bottomCornerRadii, in: rect)

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        // Left ear: concave curve from the top edge down into the body's left side.
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + top, y: rect.minY + top),
            control: CGPoint(x: rect.minX + top, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.minX + top, y: rect.maxY - bottom.height))
        // Bottom-left convex corner.
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + top + bottom.width, y: rect.maxY),
            control: CGPoint(x: rect.minX + top, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - top - bottom.width, y: rect.maxY))
        // Bottom-right convex corner.
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - top, y: rect.maxY - bottom.height),
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

/// Part of the island outline (`NotchShape`, with round bottom corners as the
/// expanded island has) as an open path, split where the sides reach `horizon`,
/// a share of the height from the top. The lower arc runs left to right around
/// the bottom and the upper arc right to left across the top, so the two
/// together go once around the island.
public struct NotchEdge: Shape {
    public enum Arc: Sendable {
        /// From the left side at `horizon` down around the bottom and up the
        /// right side to the same height.
        case lower
        /// From the right side at `horizon` up over the right ear, along the top
        /// edge, and over the left ear down to the same height on the left side.
        case upper
    }

    public var arc: Arc
    public var topCornerRadius: CGFloat
    public var bottomCornerRadius: CGFloat
    public var horizon: CGFloat

    public init(arc: Arc, topCornerRadius: CGFloat, bottomCornerRadius: CGFloat, horizon: CGFloat) {
        self.arc = arc
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
        let (top, bottom) = NotchShape.clampedRadii(
            top: topCornerRadius,
            bottom: CGSize(width: bottomCornerRadius, height: bottomCornerRadius),
            in: rect
        )
        // Below the ears, and above the bottom corners.
        let split = min(max(rect.minY + rect.height * horizon, rect.minY + top), rect.maxY - bottom.height)

        var path = Path()
        switch arc {
        case .lower:
            path.move(to: CGPoint(x: rect.minX + top, y: split))
            path.addLine(to: CGPoint(x: rect.minX + top, y: rect.maxY - bottom.height))
            path.addQuadCurve(
                to: CGPoint(x: rect.minX + top + bottom.width, y: rect.maxY),
                control: CGPoint(x: rect.minX + top, y: rect.maxY)
            )
            path.addLine(to: CGPoint(x: rect.maxX - top - bottom.width, y: rect.maxY))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX - top, y: rect.maxY - bottom.height),
                control: CGPoint(x: rect.maxX - top, y: rect.maxY)
            )
            path.addLine(to: CGPoint(x: rect.maxX - top, y: split))
        case .upper:
            path.move(to: CGPoint(x: rect.maxX - top, y: split))
            path.addLine(to: CGPoint(x: rect.maxX - top, y: rect.minY + top))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: rect.minY),
                control: CGPoint(x: rect.maxX - top, y: rect.minY)
            )
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addQuadCurve(
                to: CGPoint(x: rect.minX + top, y: rect.minY + top),
                control: CGPoint(x: rect.minX + top, y: rect.minY)
            )
            path.addLine(to: CGPoint(x: rect.minX + top, y: split))
        }
        return path
    }
}

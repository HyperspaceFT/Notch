import SwiftUI

/// Shared sizes, radii, colors, and animations for the island and its content.
public enum NotchTheme {
    // MARK: Island geometry

    /// Width of each wing beside the hardware notch while an activity is shown.
    public static let activityWingWidth: CGFloat = 72
    /// Body size of the expanded island (excluding the ears).
    public static let expandedSize = CGSize(width: 520, height: 190)

    public static let collapsedTopRadius: CGFloat = 6
    public static let collapsedBottomRadius: CGFloat = 10
    public static let activityTopRadius: CGFloat = 8
    public static let activityBottomRadius: CGFloat = 13
    public static let expandedTopRadius: CGFloat = 14
    public static let expandedBottomRadius: CGFloat = 32

    /// How much the collapsed or activity island grows while the pointer rests on
    /// it: `width` on each side, `height` at the bottom. The top stays at the screen edge.
    public static let hoverGrowth = CGSize(width: 11, height: 8)

    /// Blur radius and downward offset of the expanded island's drop shadow.
    public static let expandedShadowRadius: CGFloat = 14
    public static let expandedShadowOffset: CGFloat = 6

    /// Transparent room around the expanded island so its shadow is not clipped.
    /// The blur fades out completely only about three radii past the edge; less
    /// room cuts it off at the panel edge.
    public static let shadowPadding: CGFloat = expandedShadowRadius * 3

    /// Fixed size of the window hosting the island. Large enough for the expanded
    /// island including ears and shadow; the window never resizes.
    public static var panelSize: CGSize {
        CGSize(
            width: NotchShape.frameWidth(bodyWidth: expandedSize.width, topCornerRadius: expandedTopRadius)
                + shadowPadding * 2,
            // The shadow is shifted down, so the bottom needs its offset on top.
            height: expandedSize.height + shadowPadding + expandedShadowOffset
        )
    }

    /// Horizontal padding between the island body edge and expanded content.
    public static let contentPadding: CGFloat = 18

    // MARK: Colors

    /// Island fill. Must stay pure black to blend with the hardware notch.
    public static let islandColor = Color.black
    public static let primaryText = Color.white
    public static let secondaryText = Color.white.opacity(0.6)
    public static let cardFill = Color.white.opacity(0.07)
    public static let chargingColor = Color.green

    // MARK: Animations

    /// Opening the island: slightly bouncy, like Dynamic Island.
    public static let expandAnimation = Animation.bouncy(duration: 0.42, extraBounce: 0.08)
    /// Closing the island: no overshoot so it settles cleanly into the notch.
    public static let collapseAnimation = Animation.smooth(duration: 0.34)
    /// Activities appearing or disappearing in collapsed mode.
    public static let activityAnimation = Animation.snappy(duration: 0.36)
    /// Pointer arriving on the island: overshoots the hover ring by about a
    /// quarter, then springs back. Leaving uses `collapseAnimation`.
    public static let hoverAnimation = Animation.bouncy(duration: 0.4, extraBounce: 0.3)
}

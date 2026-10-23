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
    /// Card background without light and color (`NotchAppearance`).
    public static let cardFill = Color.white.opacity(0.07)
    /// Card background with light and color: lit from above, lighter at the top
    /// than at the bottom, about as bright overall as `cardFill`.
    public static var litCardFill: LinearGradient {
        LinearGradient(colors: [.white.opacity(0.1), .white.opacity(0.045)], startPoint: .top, endPoint: .bottom)
    }
    /// Hairline around a lit card, brightest where the light catches its top edge.
    public static var cardRim: LinearGradient {
        LinearGradient(colors: [.white.opacity(0.18), .white.opacity(0.04)], startPoint: .top, endPoint: .bottom)
    }
    /// How strongly a card's tint washes it, at its top-leading corner.
    public static let cardTintOpacity: Double = 0.24
    public static let chargingColor = Color.green

    /// Large numbers such as the clock. With light and color, `color` fades
    /// slightly toward the bottom, for a soft sheen; without, it is flat.
    @MainActor
    public static func headline(_ color: Color = primaryText) -> LinearGradient {
        let bottom = NotchAppearance.shared.isLightAndColorEnabled ? color.opacity(0.72) : color
        return LinearGradient(colors: [color, bottom], startPoint: .top, endPoint: .bottom)
    }

    /// A symbol in its own color, such as AirDrop's blue, with light and color;
    /// primary text without.
    @MainActor
    public static func accent(_ color: Color) -> AnyShapeStyle {
        NotchAppearance.shared.isLightAndColorEnabled ? AnyShapeStyle(color.gradient) : AnyShapeStyle(primaryText)
    }

    // MARK: Animations

    /// Opening the island: slightly bouncy, like Dynamic Island.
    public static let expandAnimation = Animation.bouncy(duration: 0.52, extraBounce: 0.08)
    /// The expanded content dropping out of the notch. It sets off
    /// `expandDropDelay` after the outline and takes a little longer, so it
    /// trails the outline and lands just after it.
    public static let expandDropAnimation = Animation.bouncy(duration: 0.56, extraBounce: 0.1)
    public static let expandDropDelay: TimeInterval = 0.1
    /// How far above its place the expanded content starts its drop.
    public static let expandDropDistance: CGFloat = 32
    /// Closing the island: no overshoot so it settles cleanly into the notch.
    public static let collapseAnimation = Animation.smooth(duration: 0.34)
    /// Activities appearing or disappearing in collapsed mode.
    public static let activityAnimation = Animation.snappy(duration: 0.36)
    /// Pointer arriving on the island: overshoots the hover ring by about a
    /// quarter, then springs back. Leaving uses `collapseAnimation`.
    public static let hoverAnimation = Animation.bouncy(duration: 0.4, extraBounce: 0.3)
    /// Switching tabs: the selection highlight slides to the new tab button while
    /// the old content slides out and the new content slides in.
    public static let tabSwitchAnimation = Animation.smooth(duration: 0.38)
    /// How far tab content travels sideways while it fades in or out.
    public static let tabSwitchOffset: CGFloat = 28
}

import CoreGraphics

/// Pure screen math for locating the hardware notch. Has no AppKit dependency so
/// it can be unit-tested with plain rects.
///
/// All rects use AppKit's global screen coordinates (origin bottom-left, y up).
struct NotchGeometry: Equatable, Sendable {
    /// Notch used on screens without a hardware notch (external displays, older Macs).
    static let simulatedNotchSize = CGSize(width: 185, height: 32)

    let screenFrame: CGRect
    /// The hardware notch (or the simulated one), its top edge at `screenFrame.maxY`.
    let notchRect: CGRect
    let hasHardwareNotch: Bool

    /// - Parameters:
    ///   - safeAreaTop: `NSScreen.safeAreaInsets.top`; non-zero only on notched screens.
    ///   - auxiliaryTopLeftArea / auxiliaryTopRightArea: the unobscured menu bar areas
    ///     left and right of the notch (`NSScreen.auxiliaryTopLeftArea` etc.); empty
    ///     when the screen has no notch.
    init(
        screenFrame: CGRect,
        safeAreaTop: CGFloat,
        auxiliaryTopLeftArea: CGRect,
        auxiliaryTopRightArea: CGRect
    ) {
        self.screenFrame = screenFrame

        let leftWidth = auxiliaryTopLeftArea.isNull ? 0 : auxiliaryTopLeftArea.width
        let rightWidth = auxiliaryTopRightArea.isNull ? 0 : auxiliaryTopRightArea.width
        let notchWidth = screenFrame.width - leftWidth - rightWidth

        if safeAreaTop > 0, leftWidth > 0, rightWidth > 0, notchWidth > 0 {
            hasHardwareNotch = true
            notchRect = CGRect(
                x: screenFrame.minX + leftWidth,
                y: screenFrame.maxY - safeAreaTop,
                width: notchWidth,
                height: safeAreaTop
            )
        } else {
            hasHardwareNotch = false
            let size = Self.simulatedNotchSize
            notchRect = CGRect(
                x: screenFrame.midX - size.width / 2,
                y: screenFrame.maxY - size.height,
                width: size.width,
                height: size.height
            )
        }
    }

    /// A rect of `size` horizontally centered on the notch with its top edge at the
    /// top of the screen. Used for both the hosting panel and the island itself.
    func topCenteredRect(size: CGSize) -> CGRect {
        CGRect(
            x: notchRect.midX - size.width / 2,
            y: screenFrame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }
}

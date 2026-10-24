import CoreGraphics
import Testing
@testable import NotchShell

struct HoverControllerTests {
    /// A 760pt body plus two 14pt ears, and the 520pt tab it shrinks to, sharing a top edge and centre.
    private let wide = CGRect(x: 341, y: 700, width: 788, height: 256)
    private let narrow = CGRect(x: 461, y: 700, width: 548, height: 256)

    @Test func pointerOnWideTabButtonCountsAsInsideWhileWideFrameIsRemembered() {
        let tabButton = CGPoint(x: wide.minX + 30, y: wide.maxY - 20)
        #expect(!narrow.insetBy(dx: -8, dy: -8).contains(tabButton))
        #expect(HoverController.isInsideExpanded(tabButton, current: narrow, remembered: wide, margin: 8))
    }

    @Test func pointerOutsideBothFramesIsOutside() {
        let away = CGPoint(x: wide.minX - 100, y: wide.midY)
        #expect(!HoverController.isInsideExpanded(away, current: narrow, remembered: wide, margin: 8))
    }

    @Test func withoutRememberedFrameOnlyTheCurrentFrameCounts() {
        let tabButton = CGPoint(x: wide.minX + 30, y: wide.maxY - 20)
        let inside = CGPoint(x: narrow.midX, y: narrow.midY)
        #expect(!HoverController.isInsideExpanded(tabButton, current: narrow, remembered: nil, margin: 8))
        #expect(HoverController.isInsideExpanded(inside, current: narrow, remembered: nil, margin: 8))
    }

    @Test func marginExtendsBothFrames() {
        let justOutsideNarrow = CGPoint(x: narrow.minX - 6, y: narrow.midY)
        let justOutsideWide = CGPoint(x: wide.minX - 6, y: wide.midY)
        #expect(HoverController.isInsideExpanded(justOutsideNarrow, current: narrow, remembered: nil, margin: 8))
        #expect(HoverController.isInsideExpanded(justOutsideWide, current: narrow, remembered: wide, margin: 8))
        #expect(!HoverController.isInsideExpanded(justOutsideWide, current: narrow, remembered: nil, margin: 8))
    }

    /// The island a drag opens must cover the zone it opened from, or the pointer
    /// would be outside it and collapse it again.
    @MainActor
    @Test(arguments: [
        // A notched laptop screen.
        NotchGeometry(
            screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            safeAreaTop: 38,
            auxiliaryTopLeftArea: CGRect(x: 0, y: 944, width: 661, height: 38),
            auxiliaryTopRightArea: CGRect(x: 851, y: 944, width: 661, height: 38)
        ),
        // An external display with the simulated notch.
        NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080), safeAreaTop: 0, auxiliaryTopLeftArea: .null, auxiliaryTopRightArea: .null),
    ])
    func dragApproachZoneLiesInsideTheIslandItOpens(geometry: NotchGeometry) {
        let notch = geometry.notchRect
        let zone = HoverController.dragApproachZone(notch: notch)
        #expect(zone.minY < notch.minY && zone.minX < notch.minX && zone.maxX > notch.maxX)
        #expect(zone.contains(CGPoint(x: notch.midX, y: geometry.screenFrame.maxY)))

        let model = NotchViewModel(geometry: geometry)
        model.expandForDrop()
        let margin = HoverController.exitMargin
        #expect(model.islandScreenFrame.insetBy(dx: -margin, dy: -margin).contains(zone))
    }
}

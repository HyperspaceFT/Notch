import CoreGraphics
import Testing
@testable import NotchShell

struct NotchGeometryTests {
    /// 13" MacBook Air (M2/M3) at the default scaled resolution.
    private let airFrame = CGRect(x: 0, y: 0, width: 1470, height: 956)

    @Test func notchedScreenUsesAuxiliaryAreas() {
        let geometry = NotchGeometry(
            screenFrame: airFrame,
            safeAreaTop: 32,
            auxiliaryTopLeftArea: CGRect(x: 0, y: 924, width: 640, height: 32),
            auxiliaryTopRightArea: CGRect(x: 830, y: 924, width: 640, height: 32)
        )

        #expect(geometry.hasHardwareNotch)
        #expect(geometry.notchRect == CGRect(x: 640, y: 924, width: 190, height: 32))
    }

    @Test func notchOnSecondaryScreenUsesItsOrigin() {
        let frame = CGRect(x: -1470, y: 200, width: 1470, height: 956)
        let geometry = NotchGeometry(
            screenFrame: frame,
            safeAreaTop: 38,
            auxiliaryTopLeftArea: CGRect(x: -1470, y: 1118, width: 600, height: 38),
            auxiliaryTopRightArea: CGRect(x: -670, y: 1118, width: 670, height: 38)
        )

        #expect(geometry.notchRect == CGRect(x: -870, y: 1118, width: 200, height: 38))
        #expect(geometry.notchRect.maxY == frame.maxY)
    }

    @Test func screenWithoutNotchFallsBackToSimulatedNotch() {
        let frame = CGRect(x: 0, y: 0, width: 2560, height: 1440)
        let geometry = NotchGeometry(
            screenFrame: frame,
            safeAreaTop: 0,
            auxiliaryTopLeftArea: .zero,
            auxiliaryTopRightArea: .zero
        )

        #expect(!geometry.hasHardwareNotch)
        #expect(geometry.notchRect.size == NotchGeometry.simulatedNotchSize)
        #expect(geometry.notchRect.midX == frame.midX)
        #expect(geometry.notchRect.maxY == frame.maxY)
    }

    @Test func inconsistentInsetsFallBack() {
        // Safe-area inset without auxiliary areas (should not happen, but must not misplace the island).
        let geometry = NotchGeometry(
            screenFrame: airFrame,
            safeAreaTop: 32,
            auxiliaryTopLeftArea: .zero,
            auxiliaryTopRightArea: .zero
        )
        #expect(!geometry.hasHardwareNotch)
    }

    @Test func topCenteredRectHugsTopEdgeAndCentersOnNotch() {
        let geometry = NotchGeometry(
            screenFrame: airFrame,
            safeAreaTop: 32,
            auxiliaryTopLeftArea: CGRect(x: 0, y: 924, width: 640, height: 32),
            auxiliaryTopRightArea: CGRect(x: 830, y: 924, width: 640, height: 32)
        )

        let rect = geometry.topCenteredRect(size: CGSize(width: 596, height: 214))
        #expect(rect.maxY == airFrame.maxY)
        #expect(rect.midX == geometry.notchRect.midX)
        #expect(rect.size == CGSize(width: 596, height: 214))
    }
}

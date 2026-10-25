import CoreGraphics
import Foundation
import SwiftUI
import Testing
@testable import UsageFeature

/// Path data read as the SVG specification's path grammar and implementation
/// notes define it.
struct SVGPathTests {
    private func elements(_ data: String) throws -> [SVGPathElement] {
        try SVGPath.elements(data)
    }

    private func isClose(_ a: CGPoint, _ b: CGPoint, tolerance: CGFloat = 1e-9) -> Bool {
        abs(a.x - b.x) <= tolerance && abs(a.y - b.y) <= tolerance
    }

    /// The end point of each drawing step after the move.
    private func ends(_ elements: [SVGPathElement]) -> [CGPoint] {
        elements.compactMap { element in
            switch element {
            case .move: nil
            case .line(let point): point
            case .quadCurve(let to, _): to
            case .curve(let to, _, _): to
            case .close: nil
            }
        }
    }

    @Test func absoluteAndRelativeCommandsGiveTheSamePath() throws {
        let absolute = try elements("M1 2 L4 6 H10 V0 C11 1 12 1 13 0 Q14 2 15 0 Z")
        let relative = try elements("m1 2 l3 4 h6 v-6 c1 1 2 1 3 0 q1 2 2 0 z")
        #expect(absolute == relative)
        #expect(absolute == [
            .move(CGPoint(x: 1, y: 2)),
            .line(CGPoint(x: 4, y: 6)),
            .line(CGPoint(x: 10, y: 6)),
            .line(CGPoint(x: 10, y: 0)),
            .curve(to: CGPoint(x: 13, y: 0), control1: CGPoint(x: 11, y: 1), control2: CGPoint(x: 12, y: 1)),
            .quadCurve(to: CGPoint(x: 15, y: 0), control: CGPoint(x: 14, y: 2)),
            .close,
        ])
    }

    @Test func pairsAfterAMoveAreLines() throws {
        #expect(try elements("M0 0 1 1 2 2") == [.move(.zero), .line(CGPoint(x: 1, y: 1)), .line(CGPoint(x: 2, y: 2))])
        #expect(try elements("m1 1 1 1") == [.move(CGPoint(x: 1, y: 1)), .line(CGPoint(x: 2, y: 2))])
        // A relative move after a closed subpath starts from the subpath's start.
        #expect(try elements("M2 2 l1 0 z m1 1") == [
            .move(CGPoint(x: 2, y: 2)), .line(CGPoint(x: 3, y: 2)), .close, .move(CGPoint(x: 3, y: 3)),
        ])
    }

    @Test func minifiedNumbers() throws {
        #expect(try elements("M-.5.5L.23-.08 1e1-2E-1,3.5e+1+2") == [
            .move(CGPoint(x: -0.5, y: 0.5)),
            .line(CGPoint(x: 0.23, y: -0.08)),
            .line(CGPoint(x: 10, y: -0.2)),
            .line(CGPoint(x: 35, y: 2)),
        ])
    }

    @Test func compactArcFlagsAndExactEndpoint() throws {
        let arc = try elements("M0 0a2.97 2.97 0 01-.104-.729")
        #expect(arc.first == .move(.zero))
        #expect(ends(arc).last == CGPoint(x: -0.104, y: -0.729))

        // A half circle from (0, 0) to (2, 0): sweep 1 runs through (1, -1), sweep 0 through (1, 1).
        let sweep = try elements("M0 0A1 1 0 01 2 0")
        #expect(sweep.count == 3)
        #expect(isClose(ends(sweep)[0], CGPoint(x: 1, y: -1)))
        #expect(ends(sweep)[1] == CGPoint(x: 2, y: 0))
        let other = try elements("M0 0A1 1 0 0 0 2 0")
        #expect(isClose(ends(other)[0], CGPoint(x: 1, y: 1)))
    }

    @Test func tooSmallRadiiAreScaledUp() throws {
        let arc = try elements("M0 0A.5 .5 0 0 1 2 0")
        #expect(isClose(ends(arc)[0], CGPoint(x: 1, y: -1)))
        #expect(ends(arc).last == CGPoint(x: 2, y: 0))
    }

    @Test func zeroRadiusArcIsALine() throws {
        #expect(try elements("M0 0A0 5 0 0 1 3 4") == [.move(.zero), .line(CGPoint(x: 3, y: 4))])
        // An arc to its own start draws nothing.
        #expect(try elements("M1 1A2 2 0 0 1 1 1") == [.move(CGPoint(x: 1, y: 1))])
    }

    @Test func smoothCurvesReflectTheLastControlPoint() throws {
        let cubic = try elements("M0 0C1 1 2 1 3 0S5-1 6 0")
        #expect(cubic.last == .curve(to: CGPoint(x: 6, y: 0), control1: CGPoint(x: 4, y: -1), control2: CGPoint(x: 5, y: -1)))
        let quad = try elements("M0 0Q1 1 2 0T4 0")
        #expect(quad.last == .quadCurve(to: CGPoint(x: 4, y: 0), control: CGPoint(x: 3, y: -1)))
        // Without a curve of the same kind before, the control is the current point.
        let afterLine = try elements("M0 0L1 0S2 1 3 0")
        #expect(afterLine.last == .curve(to: CGPoint(x: 3, y: 0), control1: CGPoint(x: 1, y: 0), control2: CGPoint(x: 2, y: 1)))
        let afterCubic = try elements("M0 0C1 1 2 1 3 0T5 0")
        #expect(afterCubic.last == .quadCurve(to: CGPoint(x: 5, y: 0), control: CGPoint(x: 3, y: 0)))
    }

    @Test func malformedDataFails() throws {
        for data in ["M0 0 X1 1", "M0", "M0 0 L1", "1 2", "M0 0 Z 1 1", "M0 0 A1 1 0 2 0 3 3", "M0 0 L1 ."] {
            #expect(throws: SVGPathError.self) {
                try SVGPath.elements(data)
            }
        }
        #expect(try SVGPath.elements("") == [])
    }

    @Test func everyLogoParsesWithinItsViewBox() throws {
        for (provider, data) in [(UsageProvider.claude, UsageLogos.claudeData), (.codex, UsageLogos.codexData), (.grok, UsageLogos.grokData)] {
            let parsed = try SVGPath.elements(data)
            #expect(parsed.count > 10)
            let bounds = UsageLogos.path(for: provider).boundingRect
            #expect(!bounds.isEmpty)
            #expect(bounds.minX >= -0.1 && bounds.minY >= -0.1, "\(provider)")
            #expect(bounds.maxX <= 24.1 && bounds.maxY <= 24.1, "\(provider)")
        }
    }

    @Test func shapeScalesTheViewBoxIntoItsRectCentered() {
        let square = Path(CGRect(x: 0, y: 0, width: 24, height: 24))
        let drawn = SVGShape(path: square).path(in: CGRect(x: 0, y: 0, width: 48, height: 24)).boundingRect
        #expect(drawn == CGRect(x: 12, y: 0, width: 24, height: 24))
    }
}

struct UsageWindowIconTests {
    @Test func wedgeCoversTheWindowsHoursOfTheDial() {
        #expect(UsageWindowIcon.wedgeFraction(duration: 5 * 3600) == 5.0 / 12)
        #expect(UsageWindowIcon.wedgeFraction(duration: 3 * 3600) == 0.25)
        #expect(UsageWindowIcon.wedgeFraction(duration: 12 * 3600) == 1)
        #expect(UsageWindowIcon.wedgeFraction(duration: 20 * 3600) == 1)
    }
}

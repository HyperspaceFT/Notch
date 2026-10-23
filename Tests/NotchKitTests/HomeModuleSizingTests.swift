import CoreGraphics
import Testing
@testable import NotchKit

struct HomeModuleSizingTests {
    private let row = HomeRowMetrics(width: 456, height: 134, spacing: 10)

    @Test func thirdsFillTheRowWithTheirGaps() {
        let third = HomeModuleLength.fraction(1.0 / 3).width(in: row)
        #expect(abs(third * 3 + row.spacing * 2 - row.width) < 0.001)
        #expect(abs(HomeModuleLength.fraction(1).width(in: row) - row.width) < 0.001)
    }

    @Test func fractionsAndWidthsConvertBothWays() {
        for width: CGFloat in [0, 134, 184, 456] {
            #expect(abs(row.width(forFraction: row.fraction(forWidth: width)) - width) < 0.001)
        }
    }

    @Test func lengthsResolveAgainstTheRow() {
        #expect(HomeModuleLength.points(184).width(in: row) == 184)
        #expect(HomeModuleLength.height(1).width(in: row) == 134)
        #expect(HomeModuleLength.height(1.5).width(in: row) == 201)
    }

    @Test func boundsStayWithinTheRow() {
        let open = HomeModuleSizing.resizable(minimum: .points(100))
        #expect(open.isResizable)
        #expect(open.minimumWidth(in: row) == 100)
        #expect(open.maximumWidth(in: row) == 456)

        let inverted = HomeModuleSizing.resizable(minimum: .points(200), maximum: .points(150))
        #expect(inverted.maximumWidth(in: row) == 200)

        let tooWide = HomeModuleSizing.resizable(minimum: .points(600), maximum: .points(700))
        #expect(tooWide.minimumWidth(in: row) == 456)
        #expect(tooWide.maximumWidth(in: row) == 456)

        let fixed = HomeModuleSizing.fixed(.height(1))
        #expect(!fixed.isResizable)
        #expect(fixed.minimumWidth(in: row) == 134)
        #expect(fixed.maximumWidth(in: row) == 134)
    }
}

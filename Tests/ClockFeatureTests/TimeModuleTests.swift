import Foundation
import NotchKit
import Testing
@testable import ClockFeature

/// The panel's row under a 32-point notch: 456 × 134 points, 10-point gaps.
private let row = HomeRowMetrics(width: 456, height: 134, spacing: 10)

struct TimeModuleTests {
    @Test func isASquareAtItsNarrowestAndFitsTheSecondsAtItsWidest() {
        #expect(TimeModule.sizing.minimumWidth(in: row) == 134)
        #expect(TimeModule.sizing.maximumWidth(in: row) == 184)
        #expect(TimeModule.sizing.minimumWidth(in: HomeRowMetrics(width: 456, height: 128, spacing: 10)) == 128)
    }

    @Test func showsSecondsFromTheThreshold() {
        #expect(!TimeModule.showsSeconds(width: 134))
        #expect(!TimeModule.showsSeconds(width: 159.9))
        #expect(TimeModule.showsSeconds(width: 160))
        #expect(TimeModule.showsSeconds(width: 184))
    }
}

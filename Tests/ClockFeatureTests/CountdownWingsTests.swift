import Foundation
import Testing
@testable import ClockFeature

struct CountdownWingsTests {
    @Test func underAnHourTheWingsFitMinutesAndSeconds() {
        let short = CountdownWings.width(remaining: 300)
        #expect(CountdownWings.width(remaining: 60) == short)
        // "59:59", the longest time under an hour.
        #expect(CountdownWings.width(remaining: 3599) == short)
        #expect(CountdownWings.width(remaining: 0) == short)
    }

    @Test func fromAnHourTheWingsWidenForTheHours() {
        let short = CountdownWings.width(remaining: 3599)
        let long = CountdownWings.width(remaining: 3600)
        #expect(long > short)
        #expect(CountdownWings.width(remaining: 180 * 60) == long)
        // Shown rounded up: half a second short of an hour already reads "1:00:00".
        #expect(CountdownWings.width(remaining: 3599.5) == long)
    }

    @Test func theLeftWingFitsTheRingWithTheSameClearances() {
        // Narrower than the right wing at any time left, so the island's left edge
        // comes in to the ring.
        let clearances = CountdownWings.width(remaining: 300) - CountdownWings.timeWidth(remaining: 300)
        #expect(CountdownWings.leadingWidth == CountdownWings.ringSide + clearances)
        #expect(CountdownWings.leadingWidth < CountdownWings.width(remaining: 0))
    }

    @Test func theWingsAreNarrowerThanTheStandardOnes() {
        // Only as wide as the content needs, which the shell's standard wing exceeds.
        #expect(CountdownWings.width(remaining: 3600) < 72)
    }

    @Test func theWingIsTheTimesRoomPlusClearances() {
        // The same clearances around either room, so the time's room grows with the wing.
        let shortExtra = CountdownWings.width(remaining: 300) - CountdownWings.timeWidth(remaining: 300)
        let longExtra = CountdownWings.width(remaining: 3600) - CountdownWings.timeWidth(remaining: 3600)
        #expect(shortExtra == longExtra)
        #expect(shortExtra > 0)
        #expect(CountdownWings.timeWidth(remaining: 3599) < CountdownWings.timeWidth(remaining: 3599.5))
    }
}

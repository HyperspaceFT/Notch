import Foundation
import Testing
@testable import NotchKit

struct SunTimesTests {
    private let sunrise = Date(timeIntervalSince1970: 1_792_733_400)

    @Test func acceptsAnOrdinaryDay() {
        #expect(SunTimes(sunrise: sunrise, sunset: sunrise.addingTimeInterval(10 * 3600)) != nil)
    }

    @Test func rejectsPolarDaysAndNights() {
        #expect(SunTimes(sunrise: sunrise, sunset: sunrise) == nil)
        #expect(SunTimes(sunrise: sunrise, sunset: sunrise.addingTimeInterval(-3600)) == nil)
        #expect(SunTimes(sunrise: sunrise, sunset: sunrise.addingTimeInterval(24 * 3600)) == nil)
    }
}

@MainActor
struct DaylightTests {
    private let suiteName = "DaylightTests.\(UUID().uuidString)"
    private var defaults: UserDefaults { UserDefaults(suiteName: suiteName)! }

    /// Day `index` after an arbitrary start, sunrise to sunset ten hours later.
    private func day(_ index: Int) -> SunTimes {
        let sunrise = Date(timeIntervalSince1970: 1_792_733_400 + Double(index) * 24 * 3600)
        return SunTimes(sunrise: sunrise, sunset: sunrise.addingTimeInterval(10 * 3600))!
    }

    @Test func startsWithoutDays() {
        #expect(Daylight(defaults: defaults).sunTimes.isEmpty)
    }

    @Test func keepsDaysInOrderAcrossLaunches() {
        let daylight = Daylight(defaults: defaults)
        daylight.update([day(1), day(0)])
        #expect(daylight.sunTimes == [day(0), day(1)])

        let relaunched = Daylight(defaults: defaults)
        #expect(relaunched.sunTimes == [day(0), day(1)])
    }

    @Test func anEmptyUpdateKeepsTheKnownDays() {
        let daylight = Daylight(defaults: defaults)
        daylight.update([day(0)])
        daylight.update([])
        #expect(daylight.sunTimes == [day(0)])
    }

    @Test func dropsStoredDaysThatAreNotValid() {
        // Dates encode as seconds since 2001; the first day sets before it rises.
        let json = #"[{"sunrise":100,"sunset":50},{"sunrise":100,"sunset":200}]"#
        defaults.set(Data(json.utf8), forKey: Daylight.sunTimesKey)
        #expect(Daylight(defaults: defaults).sunTimes.map(\.sunset) == [Date(timeIntervalSinceReferenceDate: 200)])
    }

    @Test func aNewReportReplacesTheKnownDays() {
        let daylight = Daylight(defaults: defaults)
        daylight.update([day(0), day(1)])
        daylight.update([day(1), day(2)])
        #expect(daylight.sunTimes == [day(1), day(2)])
    }
}

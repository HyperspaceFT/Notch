import Foundation
import Testing
@testable import CalendarFeature

struct BackgroundRefreshTests {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let maximumAge: TimeInterval = 30 * 60

    @Test func neverDownloadedIsStale() {
        #expect(CalendarRefreshPolicy.isStale(lastSuccess: nil, hasFailed: false, maximumAge: maximumAge, now: now))
    }

    @Test func staleOnceMaximumAgeOld() {
        let fresh = now.addingTimeInterval(-29 * 60)
        let old = now.addingTimeInterval(-30 * 60)
        #expect(!CalendarRefreshPolicy.isStale(lastSuccess: fresh, hasFailed: false, maximumAge: maximumAge, now: now))
        #expect(CalendarRefreshPolicy.isStale(lastSuccess: old, hasFailed: false, maximumAge: maximumAge, now: now))
    }

    @Test func aFailedLatestDownloadIsStaleEvenWhenRecent() {
        let fresh = now.addingTimeInterval(-60)
        #expect(CalendarRefreshPolicy.isStale(lastSuccess: fresh, hasFailed: true, maximumAge: maximumAge, now: now))
    }
}

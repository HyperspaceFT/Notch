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

struct FeedBodyLimitTests {
    @Test func theDefaultMaximumIsThePolicys() {
        #expect(FeedBodyLimit().maximum == CalendarRefreshPolicy.maximumBodySize)
    }

    @Test func aBodyUpToTheMaximumIsAccepted() {
        var limit = FeedBodyLimit(maximum: 10)
        let first = limit.accept(4)
        let second = limit.accept(6)
        #expect(first)
        #expect(second)
        #expect(limit.received == 10)
    }

    @Test func oneByteOverTheMaximumIsRejected() {
        var limit = FeedBodyLimit(maximum: 10)
        let upToMaximum = limit.accept(10)
        let oneOver = limit.accept(1)
        #expect(upToMaximum)
        #expect(!oneOver)
    }

    @Test func aSingleChunkOverTheMaximumIsRejected() {
        var limit = FeedBodyLimit(maximum: 10)
        let accepted = limit.accept(11)
        #expect(!accepted)
    }

    @Test func anAnnouncedLengthOverTheMaximumIsRejected() {
        let limit = FeedBodyLimit(maximum: 10)
        #expect(limit.allows(expectedLength: 10))
        #expect(!limit.allows(expectedLength: 11))
        #expect(!limit.allows(expectedLength: Int64.max))
    }

    @Test func anUnknownOrEmptyLengthIsAllowed() {
        let limit = FeedBodyLimit(maximum: 10)
        #expect(limit.allows(expectedLength: -1))
        #expect(limit.allows(expectedLength: 0))
    }
}

@MainActor
struct FeedFailureTextTests {
    @Test func tooLargeHasItsOwnText() {
        let text = FeedFailure.tooLarge.text
        #expect(text == "calendar file too large" || text == "日历文件过大")
        #expect(text != FeedFailure.other.text)
        #expect(text != FeedFailure.notACalendar.text)
    }

    @Test func tooLargeIsNotMappedFromAURLError() {
        #expect(FeedFailure(URLError(.dataLengthExceedsMaximum)) == .other)
    }
}

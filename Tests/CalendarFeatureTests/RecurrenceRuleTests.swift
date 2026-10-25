import Foundation
import Testing
@testable import CalendarFeature

private let newYork = TimeZone(identifier: "America/New_York")!

private var newYorkCalendar: Foundation.Calendar {
    var calendar = Foundation.Calendar(identifier: .gregorian)
    calendar.timeZone = newYork
    return calendar
}

/// `dates` as "yyyy-MM-dd HH:mm" on New York's wall clock.
private func wallClock(_ dates: [Date]) -> [String] {
    dates.map { date in
        let parts = newYorkCalendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return String(format: "%04d-%02d-%02d %02d:%02d", parts.year!, parts.month!, parts.day!, parts.hour!, parts.minute!)
    }
}

/// "yyyy-MM-dd 09:00" for each of `days` in one month.
private func at9(_ year: Int, _ month: Int, _ days: [Int]) -> [String] {
    days.map { String(format: "%04d-%02d-%02d 09:00", year, month, $0) }
}

/// Expands `rule` from DTSTART at 09:00 New York time on the given day through
/// the end of `throughYear`.
private func expand(_ rule: String, from year: Int, _ month: Int, _ day: Int, throughYear: Int = 2040) throws -> [String] {
    let recurrence = try #require(RecurrenceRule(rule, timeZone: newYork))
    let start = instant(year, month, day, 9, in: newYork)
    let limit = instant(throughYear, 12, 31, 23, 59, in: newYork)
    return wallClock(recurrence.starts(from: start, calendar: newYorkCalendar, through: limit))
}

/// The RFC 5545 §3.8.5.3 examples, all with DTSTART at 09:00 America/New_York.
struct RecurrenceRuleExampleTests {
    @Test func dailyForTenOccurrences() throws {
        #expect(try expand("FREQ=DAILY;COUNT=10", from: 1997, 9, 2) == at9(1997, 9, Array(2...11)))
    }

    @Test func dailyUntilDecember24() throws {
        let result = try expand("FREQ=DAILY;UNTIL=19971224T000000Z", from: 1997, 9, 2)
        let expected = at9(1997, 9, Array(2...30)) + at9(1997, 10, Array(1...31))
            + at9(1997, 11, Array(1...30)) + at9(1997, 12, Array(1...23))
        #expect(result == expected)
        #expect(result.count == 113)
    }

    @Test func everyOtherDay() throws {
        let result = try expand("FREQ=DAILY;INTERVAL=2", from: 1997, 9, 2, throughYear: 1997)
        #expect(Array(result.prefix(5)) == at9(1997, 9, [2, 4, 6, 8, 10]))
        #expect(result.last == "1997-12-31 09:00")
    }

    @Test func everyTenDaysFiveOccurrences() throws {
        #expect(try expand("FREQ=DAILY;INTERVAL=10;COUNT=5", from: 1997, 9, 2)
            == at9(1997, 9, [2, 12, 22]) + at9(1997, 10, [2, 12]))
    }

    @Test func weeklyOnTuesdayAndThursdayForFiveWeeks() throws {
        let expected = at9(1997, 9, [2, 4, 9, 11, 16, 18, 23, 25, 30]) + at9(1997, 10, [2])
        #expect(try expand("FREQ=WEEKLY;UNTIL=19971007T000000Z;WKST=SU;BYDAY=TU,TH", from: 1997, 9, 2) == expected)
        #expect(try expand("FREQ=WEEKLY;COUNT=10;WKST=SU;BYDAY=TU,TH", from: 1997, 9, 2) == expected)
    }

    @Test func everyOtherWeekOnMondayWednesdayFridayUntil() throws {
        let result = try expand(
            "FREQ=WEEKLY;INTERVAL=2;UNTIL=19971224T000000Z;WKST=SU;BYDAY=MO,WE,FR", from: 1997, 9, 1)
        let expected = at9(1997, 9, [1, 3, 5, 15, 17, 19, 29]) + at9(1997, 10, [1, 3, 13, 15, 17, 27, 29, 31])
            + at9(1997, 11, [10, 12, 14, 24, 26, 28]) + at9(1997, 12, [8, 10, 12, 22])
        #expect(result == expected)
        #expect(result.count == 25)
    }

    @Test func weekStartChangesBiweeklyResults() throws {
        #expect(try expand("FREQ=WEEKLY;INTERVAL=2;COUNT=4;BYDAY=TU,SU;WKST=MO", from: 1997, 8, 5)
            == at9(1997, 8, [5, 10, 19, 24]))
        #expect(try expand("FREQ=WEEKLY;INTERVAL=2;COUNT=4;BYDAY=TU,SU;WKST=SU", from: 1997, 8, 5)
            == at9(1997, 8, [5, 17, 19, 31]))
    }

    @Test func monthlyOnFirstFridayForTen() throws {
        #expect(try expand("FREQ=MONTHLY;COUNT=10;BYDAY=1FR", from: 1997, 9, 5)
            == at9(1997, 9, [5]) + at9(1997, 10, [3]) + at9(1997, 11, [7]) + at9(1997, 12, [5])
            + at9(1998, 1, [2]) + at9(1998, 2, [6]) + at9(1998, 3, [6]) + at9(1998, 4, [3])
            + at9(1998, 5, [1]) + at9(1998, 6, [5]))
    }

    @Test func everyOtherMonthOnFirstAndLastSunday() throws {
        #expect(try expand("FREQ=MONTHLY;INTERVAL=2;COUNT=10;BYDAY=1SU,-1SU", from: 1997, 9, 7)
            == at9(1997, 9, [7, 28]) + at9(1997, 11, [2, 30]) + at9(1998, 1, [4, 25])
            + at9(1998, 3, [1, 29]) + at9(1998, 5, [3, 31]))
    }

    @Test func monthlyOnSecondToLastMonday() throws {
        #expect(try expand("FREQ=MONTHLY;COUNT=6;BYDAY=-2MO", from: 1997, 9, 22)
            == at9(1997, 9, [22]) + at9(1997, 10, [20]) + at9(1997, 11, [17]) + at9(1997, 12, [22])
            + at9(1998, 1, [19]) + at9(1998, 2, [16]))
    }

    @Test func monthlyOnFirstAndLastDay() throws {
        #expect(try expand("FREQ=MONTHLY;COUNT=10;BYMONTHDAY=1,-1", from: 1997, 9, 30)
            == at9(1997, 9, [30]) + at9(1997, 10, [1, 31]) + at9(1997, 11, [1, 30])
            + at9(1997, 12, [1, 31]) + at9(1998, 1, [1, 31]) + at9(1998, 2, [1]))
    }

    @Test func yearlyInJuneAndJuly() throws {
        let expected = (1997...2001).flatMap { at9($0, 6, [10]) + at9($0, 7, [10]) }
        #expect(try expand("FREQ=YEARLY;COUNT=10;BYMONTH=6,7", from: 1997, 6, 10) == expected)
    }

    @Test func everyThursdayInMarch() throws {
        #expect(try expand("FREQ=YEARLY;BYMONTH=3;BYDAY=TH", from: 1997, 3, 13, throughYear: 1999)
            == at9(1997, 3, [13, 20, 27]) + at9(1998, 3, [5, 12, 19, 26]) + at9(1999, 3, [4, 11, 18, 25]))
    }

    @Test func everyTwentiethMondayOfTheYear() throws {
        #expect(try expand("FREQ=YEARLY;BYDAY=20MO", from: 1997, 5, 19, throughYear: 1999)
            == at9(1997, 5, [19]) + at9(1998, 5, [18]) + at9(1999, 5, [17]))
    }

    @Test func thirdMondayOfJanuary() throws {
        // Martin Luther King Jr. Day.
        #expect(try expand("FREQ=YEARLY;BYMONTH=1;BYDAY=3MO;COUNT=4", from: 2024, 1, 15)
            == at9(2024, 1, [15]) + at9(2025, 1, [20]) + at9(2026, 1, [19]) + at9(2027, 1, [18]))
    }

    @Test func usPresidentialElectionDay() throws {
        #expect(try expand(
            "FREQ=YEARLY;INTERVAL=4;BYMONTH=11;BYDAY=TU;BYMONTHDAY=2,3,4,5,6,7,8", from: 1996, 11, 5, throughYear: 2004)
            == at9(1996, 11, [5]) + at9(2000, 11, [7]) + at9(2004, 11, [2]))
    }

    @Test func thirdTuesdayWednesdayOrThursdayOfTheMonth() throws {
        #expect(try expand("FREQ=MONTHLY;COUNT=3;BYDAY=TU,WE,TH;BYSETPOS=3", from: 1997, 9, 4)
            == at9(1997, 9, [4]) + at9(1997, 10, [7]) + at9(1997, 11, [6]))
    }

    @Test func secondToLastWeekdayOfTheMonth() throws {
        let result = try expand("FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-2", from: 1997, 9, 29, throughYear: 1998)
        #expect(Array(result.prefix(7)) == at9(1997, 9, [29]) + at9(1997, 10, [30]) + at9(1997, 11, [27])
            + at9(1997, 12, [30]) + at9(1998, 1, [29]) + at9(1998, 2, [26]) + at9(1998, 3, [30]))
    }

    @Test func lastWeekdayOfTheMonth() throws {
        #expect(try expand("FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1;COUNT=4", from: 1997, 9, 30)
            == at9(1997, 9, [30]) + at9(1997, 10, [31]) + at9(1997, 11, [28]) + at9(1997, 12, [31]))
    }

    @Test func fridayThe13thNeedsBothParts() throws {
        // With DTSTART itself (a Tuesday) counting as the first occurrence.
        #expect(try expand("FREQ=MONTHLY;BYDAY=FR;BYMONTHDAY=13", from: 1997, 9, 2, throughYear: 2000)
            == at9(1997, 9, [2]) + at9(1998, 2, [13]) + at9(1998, 3, [13]) + at9(1998, 11, [13])
            + at9(1999, 8, [13]) + at9(2000, 10, [13]))
    }
}

struct RecurrenceRuleBehaviorTests {
    @Test func monthlyOnThe31stSkipsShortMonths() throws {
        #expect(try expand("FREQ=MONTHLY;COUNT=5", from: 2025, 1, 31)
            == at9(2025, 1, [31]) + at9(2025, 3, [31]) + at9(2025, 5, [31]) + at9(2025, 7, [31]) + at9(2025, 8, [31]))
    }

    @Test func february29thOnlyInLeapYears() throws {
        #expect(try expand("FREQ=YEARLY;COUNT=3", from: 2024, 2, 29)
            == at9(2024, 2, [29]) + at9(2028, 2, [29]) + at9(2032, 2, [29]))
    }

    @Test func weeklyKeepsWallClockAcrossDST() throws {
        // New York leaves DST on Sunday 1 November 2026.
        let rule = try #require(RecurrenceRule("FREQ=WEEKLY;COUNT=3", timeZone: newYork))
        let starts = rule.starts(
            from: instant(2026, 10, 20, 9, in: newYork),
            calendar: newYorkCalendar,
            through: instant(2027, 1, 1, in: newYork)
        )
        #expect(wallClock(starts) == at9(2026, 10, [20, 27]) + at9(2026, 11, [3]))
        #expect(starts == [
            instant(2026, 10, 20, 13, in: .gmt), instant(2026, 10, 27, 13, in: .gmt), instant(2026, 11, 3, 14, in: .gmt),
        ])
    }

    @Test func countIncludesDTStartEvenWhenItDoesNotMatch() throws {
        // 3 September 1997 is a Wednesday.
        #expect(try expand("FREQ=WEEKLY;BYDAY=MO;COUNT=3", from: 1997, 9, 3) == at9(1997, 9, [3, 8, 15]))
    }

    @Test func dateUntilIncludesThatDay() throws {
        #expect(try expand("FREQ=DAILY;UNTIL=19970905", from: 1997, 9, 2) == at9(1997, 9, [2, 3, 4, 5]))
    }

    @Test func dailyWithByDayAndByMonthFilters() throws {
        // Every weekday in January 1998 (which began on a Thursday), from 1 January.
        let result = try expand("FREQ=DAILY;BYDAY=MO,TU,WE,TH,FR;BYMONTH=1", from: 1998, 1, 1, throughYear: 1998)
        #expect(result == at9(1998, 1, [1, 2, 5, 6, 7, 8, 9, 12, 13, 14, 15, 16, 19, 20, 21, 22, 23, 26, 27, 28, 29, 30]))
    }

    @Test func limitIsInclusiveAndStartAfterLimitYieldsNothing() throws {
        let rule = try #require(RecurrenceRule("FREQ=DAILY", timeZone: newYork))
        let start = instant(2026, 10, 20, 9, in: newYork)
        #expect(rule.starts(from: start, calendar: newYorkCalendar, through: instant(2026, 10, 22, 9, in: newYork)).count == 3)
        #expect(rule.starts(from: start, calendar: newYorkCalendar, through: instant(2026, 10, 19, in: newYork)).isEmpty)
    }

    @Test func unsupportedOrMissingFrequency() {
        #expect(RecurrenceRule("FREQ=HOURLY;COUNT=3", timeZone: newYork) == nil)
        #expect(RecurrenceRule("FREQ=SECONDLY", timeZone: newYork) == nil)
        #expect(RecurrenceRule("COUNT=3;BYDAY=MO", timeZone: newYork) == nil)
        #expect(RecurrenceRule("", timeZone: newYork) == nil)
        #expect(RecurrenceRule("freq=weekly;byday=mo,-1fr", timeZone: newYork)?.byDay == [
            .init(ordinal: nil, weekday: 2), .init(ordinal: -1, weekday: 6),
        ])
    }

    @Test func runawayRulesStop() throws {
        // February 30th never exists; the expansion must still end.
        let rule = try #require(RecurrenceRule("FREQ=YEARLY;BYMONTH=2;BYMONTHDAY=30", timeZone: newYork))
        let start = instant(2026, 1, 1, 9, in: newYork)
        #expect(rule.starts(from: start, calendar: newYorkCalendar, through: .distantFuture) == [start])
    }
}

/// Occurrence expansion of whole feeds, in a window.
struct FeedOccurrenceTests {
    private func occurrences(_ lines: [String], from start: Date, to end: Date) -> [ICalendarOccurrence] {
        ICalendar.parse(feedText(lines), defaultTimeZone: newYork)
            .occurrences(overlapping: DateInterval(start: start, end: end))
    }

    private let october = (
        start: instant(2026, 10, 1, in: newYork),
        end: instant(2026, 11, 1, in: newYork)
    )

    @Test func singleEvent() {
        let result = occurrences(
            vevent("UID:a", "SUMMARY:Lunch", "LOCATION:Cafe", "DTSTART;TZID=America/New_York:20261022T120000",
                   "DTEND;TZID=America/New_York:20261022T130000"),
            from: october.start, to: october.end)
        #expect(result == [ICalendarOccurrence(
            uid: "a", title: "Lunch", location: "Cafe",
            start: instant(2026, 10, 22, 12, in: newYork), end: instant(2026, 10, 22, 13, in: newYork), isAllDay: false)])
    }

    @Test func exceptionDatesAreRemoved() {
        let result = occurrences(vevent(
            "UID:a", "SUMMARY:Standup",
            "DTSTART;TZID=America/New_York:20261019T090000", "DTEND;TZID=America/New_York:20261019T091500",
            "RRULE:FREQ=DAILY;COUNT=5",
            "EXDATE;TZID=America/New_York:20261020T090000,20261022T090000"
        ), from: october.start, to: october.end)
        #expect(wallClock(result.map(\.start)) == at9(2026, 10, [19, 21, 23]))
        #expect(result.allSatisfy { $0.end.timeIntervalSince($0.start) == 15 * 60 })
    }

    @Test func fridayThe13thWithDTStartExcluded() {
        // RFC 5545 §3.8.5.3: the EXDATE removes DTSTART, which is no Friday the 13th.
        let result = occurrences(vevent(
            "UID:f13", "SUMMARY:Unlucky",
            "DTSTART;TZID=America/New_York:19970902T090000",
            "EXDATE;TZID=America/New_York:19970902T090000",
            "RRULE:FREQ=MONTHLY;BYDAY=FR;BYMONTHDAY=13"
        ), from: instant(1997, 1, 1, in: newYork), to: instant(2001, 1, 1, in: newYork))
        #expect(wallClock(result.map(\.start)) == at9(1998, 2, [13]) + at9(1998, 3, [13]) + at9(1998, 11, [13])
            + at9(1999, 8, [13]) + at9(2000, 10, [13]))
    }

    @Test func recurrenceDatesAreAdded() {
        let result = occurrences(vevent(
            "UID:a", "SUMMARY:Review",
            "DTSTART;TZID=America/New_York:20261005T090000",
            "RDATE;TZID=America/New_York:20261007T090000,20261009T090000",
            "RDATE;TZID=America/New_York:20261005T090000"
        ), from: october.start, to: october.end)
        #expect(wallClock(result.map(\.start)) == at9(2026, 10, [5, 7, 9]))
    }

    @Test func overrideMovesAnOccurrence() {
        let result = occurrences(
            vevent("UID:a", "SUMMARY:Sync", "DTSTART;TZID=America/New_York:20261019T090000",
                   "DTEND;TZID=America/New_York:20261019T100000", "RRULE:FREQ=DAILY;COUNT=3")
            + vevent("UID:a", "SUMMARY:Sync (moved)", "RECURRENCE-ID;TZID=America/New_York:20261020T090000",
                     "DTSTART;TZID=America/New_York:20261020T150000", "DTEND;TZID=America/New_York:20261020T160000"),
            from: october.start, to: october.end)
        #expect(result.map(\.title) == ["Sync", "Sync (moved)", "Sync"])
        #expect(result.map(\.start) == [
            instant(2026, 10, 19, 9, in: newYork), instant(2026, 10, 20, 15, in: newYork),
            instant(2026, 10, 21, 9, in: newYork),
        ])
        #expect(result[1].end == instant(2026, 10, 20, 16, in: newYork))
    }

    @Test func overrideMovedIntoTheWindowFromOutsideIt() {
        let result = occurrences(
            vevent("UID:a", "SUMMARY:Sync", "DTSTART;TZID=America/New_York:20261019T090000",
                   "RRULE:FREQ=DAILY;COUNT=3")
            + vevent("UID:a", "SUMMARY:Moved", "RECURRENCE-ID;TZID=America/New_York:20261019T090000",
                     "DTSTART;TZID=America/New_York:20261021T120000"),
            from: instant(2026, 10, 21, in: newYork), to: instant(2026, 10, 22, in: newYork))
        #expect(result.map(\.title) == ["Sync", "Moved"])
        #expect(result.map(\.start) == [instant(2026, 10, 21, 9, in: newYork), instant(2026, 10, 21, 12, in: newYork)])
    }

    @Test func cancelledOverrideRemovesTheOccurrence() {
        let result = occurrences(
            vevent("UID:a", "SUMMARY:Sync", "DTSTART;TZID=America/New_York:20261019T090000", "RRULE:FREQ=DAILY;COUNT=3")
            + vevent("UID:a", "SUMMARY:Sync", "RECURRENCE-ID;TZID=America/New_York:20261020T090000",
                     "DTSTART;TZID=America/New_York:20261020T090000", "STATUS:CANCELLED"),
            from: october.start, to: october.end)
        #expect(wallClock(result.map(\.start)) == at9(2026, 10, [19, 21]))
    }

    @Test func cancelledMasterYieldsNothing() {
        let result = occurrences(
            vevent("UID:a", "SUMMARY:Gone", "DTSTART;TZID=America/New_York:20261019T090000",
                   "RRULE:FREQ=DAILY;COUNT=3", "STATUS:CANCELLED")
            + vevent("UID:b", "SUMMARY:Also gone", "DTSTART;TZID=America/New_York:20261019T090000", "STATUS:CANCELLED"),
            from: october.start, to: october.end)
        #expect(result.isEmpty)
    }

    @Test func allDaySeriesExcludesByDayAndKeepsWholeDays() {
        // Two-day all-day events every week; New York leaves DST on 1 November 2026.
        let result = occurrences(vevent(
            "UID:a", "SUMMARY:Trip",
            "DTSTART;VALUE=DATE:20261024", "DTEND;VALUE=DATE:20261026",
            "RRULE:FREQ=WEEKLY;COUNT=4",
            "EXDATE;VALUE=DATE:20261107"
        ), from: october.start, to: instant(2026, 12, 1, in: newYork))
        #expect(result.map(\.start) == [
            instant(2026, 10, 24, in: newYork), instant(2026, 10, 31, in: newYork), instant(2026, 11, 14, in: newYork),
        ])
        #expect(result.map(\.end) == [
            instant(2026, 10, 26, in: newYork), instant(2026, 11, 2, in: newYork), instant(2026, 11, 16, in: newYork),
        ])
        #expect(result.allSatisfy { $0.isAllDay })
    }

    @Test func windowKeepsOverlapsOnly() {
        let windowStart = instant(2026, 10, 22, in: newYork)
        let windowEnd = instant(2026, 10, 23, in: newYork)
        let result = occurrences(
            vevent("UID:before", "SUMMARY:Before", "DTSTART;TZID=America/New_York:20261021T200000",
                   "DTEND;TZID=America/New_York:20261022T000000")
            + vevent("UID:ongoing", "SUMMARY:Ongoing", "DTSTART;TZID=America/New_York:20261021T220000",
                     "DTEND;TZID=America/New_York:20261022T020000")
            + vevent("UID:point", "SUMMARY:Point", "DTSTART;TZID=America/New_York:20261022T000000")
            + vevent("UID:b", "SUMMARY:B", "DTSTART;TZID=America/New_York:20261022T090000")
            + vevent("UID:a", "SUMMARY:A", "DTSTART;TZID=America/New_York:20261022T090000")
            + vevent("UID:after", "SUMMARY:After", "DTSTART;TZID=America/New_York:20261023T000000",
                     "DTEND;TZID=America/New_York:20261023T010000"),
            from: windowStart, to: windowEnd)
        #expect(result.map(\.title) == ["Ongoing", "Point", "A", "B"])
    }

    @Test func oldDailySeriesReachesTheWindow() {
        // Without skipping ahead this would hit the expansion limit long before 2026.
        let result = occurrences(vevent(
            "UID:a", "SUMMARY:Pills", "DTSTART;TZID=America/New_York:19000101T090000", "RRULE:FREQ=DAILY"
        ), from: instant(2026, 10, 22, in: newYork), to: instant(2026, 10, 24, in: newYork))
        #expect(wallClock(result.map(\.start)) == at9(2026, 10, [22, 23]))
    }

    @Test func unsupportedRuleIsASingleOccurrence() {
        let result = occurrences(vevent(
            "UID:a", "SUMMARY:Hourly", "DTSTART;TZID=America/New_York:20261019T090000", "RRULE:FREQ=HOURLY;COUNT=5"
        ), from: october.start, to: october.end)
        #expect(result.count == 1)
    }
}

/// Feeds built to make expansion expensive must still finish promptly.
struct FeedWorkBoundTests {
    private let window = DateInterval(start: instant(2026, 10, 1, in: newYork), end: instant(2026, 11, 1, in: newYork))

    @Test(.timeLimit(.minutes(1)))
    func mastersSharingAUIDAddTheirOverridesOnce() {
        let masterStart = instant(2026, 9, 1, 9, in: newYork)
        let master = ICalendarEvent(
            uid: "shared", summary: "Master", location: nil,
            start: masterStart, end: masterStart.addingTimeInterval(3600), isAllDay: false, timeZone: newYork)
        // One override a minute from 30 September 23:00, so the first hour's fall before the window.
        let firstOverride = instant(2026, 9, 30, 23, in: newYork)
        let overrides = (0..<10_000).map { index in
            let start = firstOverride.addingTimeInterval(TimeInterval(index * 60))
            var event = master
            event.summary = "Override \(index)"
            event.start = start
            event.end = start
            event.recurrenceID = instant(2025, 1, 1, in: newYork).addingTimeInterval(TimeInterval(index * 86_400))
            return event
        }
        let feed = ICalendarFeed(name: nil, events: Array(repeating: master, count: 10_000) + overrides)
        let result = feed.occurrences(overlapping: window)
        #expect(result.map(\.title) == (60..<10_000).map { "Override \($0)" })
    }

    @Test(.timeLimit(.minutes(1)))
    func mastersThatNeverMatchRunOutOfBudgetAndStillReturn() {
        // February 30th never exists, so each rule visits periods until it is stopped.
        let hopeless = (0..<200).flatMap { index in
            vevent("UID:never-\(index)", "SUMMARY:Never", "DTSTART;TZID=America/New_York:20261015T090000",
                   "RRULE:FREQ=YEARLY;BYMONTH=2;BYMONTHDAY=30;COUNT=5")
        }
        let last = vevent("UID:last", "SUMMARY:Last", "DTSTART;TZID=America/New_York:20261020T090000")
        let feed = ICalendar.parse(feedText(hopeless + last), defaultTimeZone: newYork)
        #expect(feed.events.count == 201)
        let result = feed.occurrences(overlapping: window)
        // DTSTART always counts, so the masters reached before the budget ran out each show once.
        #expect(!result.isEmpty)
        #expect(result.count < 201)
        #expect(result.allSatisfy { $0.title == "Never" && $0.start == instant(2026, 10, 15, 9, in: newYork) })
    }

    @Test(.timeLimit(.minutes(1)))
    func aWeekdayListedOverAndOverCostsNoMoreThanOnce() {
        // Every week since 1990 is visited (COUNT), each against the BYDAY list.
        let byDay = Array(repeating: "MO", count: 100_000).joined(separator: ",")
        let text = feedText(vevent(
            "UID:mondays", "SUMMARY:Monday", "DTSTART;TZID=America/New_York:19900101T090000",
            "RRULE:FREQ=WEEKLY;COUNT=1000000;BYDAY=\(byDay)"
        ))
        let result = ICalendar.parse(text, defaultTimeZone: newYork).occurrences(overlapping: window)
        #expect(result.map(\.start) == [5, 12, 19, 26].map { instant(2026, 10, $0, 9, in: newYork) })
    }
}

/// Feed values that would overflow Int arithmetic must not trap.
struct RecurrenceRuleHostileValueTests {
    private func starts(_ rule: String) -> [Date]? {
        guard let recurrence = RecurrenceRule(rule, timeZone: newYork) else { return nil }
        let start = instant(2026, 10, 22, 9, in: newYork)
        return recurrence.starts(
            from: start, calendar: newYorkCalendar, notBefore: instant(2027, 1, 1, in: newYork),
            through: instant(2027, 12, 31, in: newYork))
    }

    @Test func intervalAboveTenThousandIsUnsupported() {
        #expect(RecurrenceRule("FREQ=DAILY;INTERVAL=9223372036854775807", timeZone: newYork) == nil)
        #expect(RecurrenceRule("FREQ=YEARLY;INTERVAL=10001", timeZone: newYork) == nil)
        #expect(RecurrenceRule("FREQ=YEARLY;INTERVAL=10000", timeZone: newYork)?.interval == 10_000)
    }

    @Test func largestAllowedIntervalDoesNotTrapForAnyFrequency() {
        for frequency in ["DAILY", "WEEKLY", "MONTHLY", "YEARLY"] {
            #expect(starts("FREQ=\(frequency);INTERVAL=10000") != nil)
            #expect(starts("FREQ=\(frequency);INTERVAL=10000;COUNT=3") != nil)
        }
    }

    @Test func extremeCountAndPositionsDoNotTrap() {
        let rule = "FREQ=MONTHLY;COUNT=9223372036854775807;BYSETPOS=9223372036854775807;BYMONTHDAY=-9223372036854775808"
        let recurrence = RecurrenceRule(rule, timeZone: newYork)
        #expect(recurrence?.count == Int.max)
        #expect(recurrence?.bySetPos.isEmpty == true)
        #expect(recurrence?.byMonthDay.isEmpty == true)
        #expect(starts(rule)?.isEmpty == false)
        #expect(starts("FREQ=DAILY;COUNT=9223372036854775807;BYMONTH=9223372036854775807;BYDAY=9223372036854775807MO") != nil)
        #expect(RecurrenceRule("FREQ=MONTHLY;BYDAY=-9223372036854775808MO", timeZone: newYork)?.byDay.isEmpty == true)
    }

    @Test func repeatedListEntriesAreKeptOnce() {
        let recurrence = RecurrenceRule(
            "FREQ=MONTHLY;BYDAY=MO,MO,-1FR,MO;BYMONTHDAY=1,1,15;BYMONTH=1,1;BYSETPOS=1,1", timeZone: newYork)
        #expect(recurrence?.byDay == [.init(ordinal: nil, weekday: 2), .init(ordinal: -1, weekday: 6)])
        #expect(recurrence?.byMonthDay == [1, 15])
        #expect(recurrence?.byMonth == [1])
        #expect(recurrence?.bySetPos == [1])
        #expect(starts("FREQ=WEEKLY;BYDAY=MO,MO,TU,MO") == starts("FREQ=WEEKLY;BYDAY=MO,TU"))
    }
}

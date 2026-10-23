import Foundation
import Testing
@testable import CalendarFeature

private let zone = TimeZone(secondsFromGMT: 8 * 3600)!

private var calendar: Foundation.Calendar {
    var calendar = Foundation.Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    return calendar
}

/// October 2026 in the test zone.
private func oct(_ day: Int, _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0) -> Date {
    instant(2026, 10, day, hour, minute, second, in: zone)
}

/// Thursday 22 October 2026, 10:00.
private let now = oct(22, 10)

private func event(
    _ title: String, _ start: Date, _ end: Date, allDay: Bool = false, id: String? = nil
) -> AgendaEvent {
    AgendaEvent(
        id: id ?? title, title: title, location: nil, start: start, end: end, isAllDay: allDay,
        color: CalendarColor(red: 0.2, green: 0.4, blue: 0.6), calendarTitle: "Test"
    )
}

private func titles(_ days: [AgendaDay]) -> [[String]] {
    days.map { $0.entries.map(\.event.title) }
}

struct AgendaWindowTests {
    @Test func windowRunsFromTodaysMidnight() {
        #expect(Agenda.window(now: now, dayCount: 3, calendar: calendar) == DateInterval(start: oct(22), end: oct(25)))
    }

    @Test func dayCountIsClamped() {
        #expect(Agenda.window(now: now, dayCount: 0, calendar: calendar) == DateInterval(start: oct(22), end: oct(23)))
        #expect(Agenda.window(now: now, dayCount: -4, calendar: calendar).end == oct(23))
        #expect(Agenda.window(now: now, dayCount: 99, calendar: calendar).end == instant(2026, 11, 5, in: zone))
        #expect(Agenda.dayCountRange == 1...14)
    }
}

struct AgendaGroupingTests {
    @Test func endedEventsAreDroppedAndOngoingKept() {
        let days = Agenda.days(for: [
            event("Ended", oct(22, 8), oct(22, 9)),
            event("Ends now", oct(22, 9), now),
            event("Ongoing", oct(22, 9, 30), oct(22, 10, 30)),
            event("Past point", oct(22, 9), oct(22, 9)),
            event("Point now", now, now),
            event("Later point", oct(22, 11), oct(22, 11)),
        ], now: now, dayCount: 1, calendar: calendar)
        #expect(titles(days) == [["Ongoing", "Point now", "Later point"]])
    }

    @Test func multiDayAllDayEventIsListedOnEachDay() {
        // A feed's all-day trip ends at the following midnight; EventKit's at
        // 23:59:59 of the last day. Both cover 22-24 October.
        for end in [oct(25), oct(24, 23, 59, 59)] {
            let days = Agenda.days(
                for: [event("Trip", oct(22), end, allDay: true)], now: now, dayCount: 5, calendar: calendar)
            #expect(days.map(\.start) == [oct(22), oct(23), oct(24)])
            let entries = days.flatMap(\.entries)
            #expect(entries.map(\.day) == [oct(22), oct(23), oct(24)])
            #expect(entries.map(\.startsBeforeDay) == [false, true, true])
            #expect(entries.map(\.endsAfterDay) == [true, true, false])
        }
    }

    @Test func singleAllDayEventsAgreeAcrossSources() {
        let feed = event("Feed", oct(23), oct(24), allDay: true)
        let eventKit = event("EventKit", oct(23), oct(23, 23, 59, 59), allDay: true)
        let days = Agenda.days(for: [feed, eventKit], now: now, dayCount: 5, calendar: calendar)
        #expect(days.map(\.start) == [oct(23)])
        #expect(titles(days) == [["EventKit", "Feed"]])
        #expect(days[0].entries.allSatisfy { !$0.startsBeforeDay && !$0.endsAfterDay })
    }

    @Test func overnightEventIsListedOnBothDays() {
        let days = Agenda.days(
            for: [event("Late", oct(22, 22), oct(23, 2))], now: now, dayCount: 3, calendar: calendar)
        #expect(days.map(\.start) == [oct(22), oct(23)])
        #expect(days[0].entries[0].endsAfterDay && !days[0].entries[0].startsBeforeDay)
        #expect(days[1].entries[0].startsBeforeDay && !days[1].entries[0].endsAfterDay)
    }

    @Test func entriesAreSorted() {
        let days = Agenda.days(for: [
            event("Alpha", oct(22, 14), oct(22, 15)),
            event("Zoo", oct(22), oct(23), allDay: true),
            event("Beta", oct(22, 11), oct(22, 12)),
            event("Gamma", oct(22, 11), oct(22, 11, 30)),
            event("Apple", oct(22), oct(23), allDay: true),
            event("Delta", oct(22, 11), oct(22, 11, 30)),
        ], now: now, dayCount: 1, calendar: calendar)
        #expect(titles(days) == [["Apple", "Zoo", "Delta", "Gamma", "Beta", "Alpha"]])
    }

    @Test func emptyDaysAreOmittedAndWindowIsRespected() {
        let days = Agenda.days(for: [
            event("Saturday", oct(24, 9), oct(24, 10)),
            event("Too late", oct(27, 9), oct(27, 10)),
            event("Last day", oct(26, 23), oct(27, 1)),
        ], now: now, dayCount: 5, calendar: calendar)
        #expect(days.map(\.start) == [oct(24), oct(26)])
        #expect(titles(days) == [["Saturday"], ["Last day"]])
        #expect(days[1].entries[0].endsAfterDay)
    }

    @Test func entryIDsAreUnique() {
        let days = Agenda.days(for: [
            event("Trip", oct(22), oct(25), allDay: true),
            event("Same title", oct(23, 9), oct(23, 10), id: "x"),
            event("Same title", oct(23, 9), oct(23, 10), id: "y"),
        ], now: now, dayCount: 7, calendar: calendar)
        let ids = days.flatMap(\.entries).map(\.id)
        #expect(ids.count == 5)
        #expect(Set(ids).count == ids.count)
    }
}

struct SubscriptionAddressTests {
    @Test func webcalBecomesHTTPS() {
        #expect(SubscriptionAddress.url(from: "  webcal://example.com/calendar.ics \n")?.absoluteString
            == "https://example.com/calendar.ics")
        #expect(SubscriptionAddress.url(from: "webcals://example.com/a.ics")?.absoluteString
            == "https://example.com/a.ics")
        #expect(SubscriptionAddress.url(from: "WEBCAL://example.com/a.ics")?.absoluteString
            == "https://example.com/a.ics")
    }

    @Test func googleAndOutlookAddressesAreAccepted() throws {
        let google = try #require(SubscriptionAddress.url(from:
            "https://calendar.google.com/calendar/ical/someone%40gmail.com/private-0123456789abcdef0123456789abcdef/basic.ics"))
        #expect(SubscriptionAddress.displayHost(of: google) == "calendar.google.com")
        let outlook = try #require(SubscriptionAddress.url(from:
            "https://outlook.live.com/owa/calendar/00000000-0000-0000-0000-000000000000/1a2b3c4d-0000-0000-0000-000000000000/cid-0123456789ABCDEF/calendar.ics"))
        #expect(SubscriptionAddress.displayHost(of: outlook) == "outlook.live.com")
        #expect(SubscriptionAddress.url(from: "http://example.org/feed.ics")?.absoluteString
            == "https://example.org/feed.ics")
        #expect(SubscriptionAddress.url(from: " HTTP://example.org/feed.ics ")?.absoluteString
            == "https://example.org/feed.ics")
    }

    @Test func otherInputIsRejected() {
        for text in ["", "   ", "garbage", "not a url", "ftp://example.com/calendar.ics", "https://", "mailto:a@b.c",
                     "file:///Users/me/calendar.ics", "example.com/calendar.ics"] {
            #expect(SubscriptionAddress.url(from: text) == nil, "\(text)")
        }
    }
}

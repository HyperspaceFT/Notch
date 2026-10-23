import Foundation
import NotchKit
import Testing
@testable import CalendarFeature

/// A settings object on its own defaults domain, removed after `body`.
@MainActor
private func withSettings(_ body: (UserDefaults, () -> CalendarSettings) throws -> Void) rethrows {
    let suite = "CalendarSettingsTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    try body(defaults) { CalendarSettings(defaults: defaults) }
}

@MainActor
struct CalendarSettingsTests {
    @Test func defaultsWithoutSavedValues() {
        withSettings { _, make in
            let settings = make()
            #expect(settings.dayCount == 3)
            #expect(settings.hiddenCalendarIDs.isEmpty)
            #expect(settings.subscriptions.isEmpty)
            #expect(CalendarSettings.dayCountRange == 1...14)
        }
    }

    @Test func valuesSurviveARelaunch() {
        withSettings { _, make in
            let settings = make()
            settings.dayCount = 7
            settings.setCalendar("work", shown: false)
            #expect(settings.addSubscription(name: "  Team  ", address: "webcal://example.com/team.ics"))
            let reloaded = make()
            #expect(reloaded.dayCount == 7)
            #expect(reloaded.hiddenCalendarIDs == ["work"])
            #expect(reloaded.subscriptions == settings.subscriptions)
            #expect(reloaded.subscriptions.first?.name == "Team")
        }
    }

    @Test func dayCountStaysInRange() {
        withSettings { defaults, make in
            let settings = make()
            settings.dayCount = 0
            #expect(settings.dayCount == 1)
            settings.dayCount = 30
            #expect(settings.dayCount == 14)
            defaults.set(99, forKey: CalendarSettings.dayCountKey)
            #expect(make().dayCount == 14)
            defaults.set(-2, forKey: CalendarSettings.dayCountKey)
            #expect(make().dayCount == 1)
        }
    }

    @Test func calendarsShowUntilHidden() {
        withSettings { _, make in
            let settings = make()
            #expect(settings.isCalendarShown("home"))
            settings.setCalendar("home", shown: false)
            #expect(!settings.isCalendarShown("home"))
            #expect(settings.isCalendarShown("work"))
            settings.setCalendar("home", shown: true)
            #expect(settings.isCalendarShown("home"))
            #expect(settings.hiddenCalendarIDs.isEmpty)
        }
    }

    @Test func webcalAddressesBecomeHTTPS() {
        withSettings { _, make in
            let settings = make()
            #expect(settings.addSubscription(name: "", address: " webcal://calendar.google.com/calendar/ical/x/private-abc/basic.ics "))
            let subscription = settings.subscriptions[0]
            #expect(subscription.address == "https://calendar.google.com/calendar/ical/x/private-abc/basic.ics")
            #expect(subscription.isEnabled)
            #expect(subscription.displayHost == "calendar.google.com")
        }
    }

    @Test func invalidAndDuplicateAddressesAreRejected() {
        withSettings { _, make in
            let settings = make()
            #expect(!settings.canAddSubscription(address: ""))
            #expect(!settings.addSubscription(name: "", address: "not a url"))
            #expect(!settings.addSubscription(name: "", address: "ftp://example.com/a.ics"))
            #expect(!settings.addSubscription(name: "", address: "https://"))
            #expect(settings.addSubscription(name: "", address: "https://example.com/a.ics"))
            // The same feed pasted as webcal:// is the same subscription.
            #expect(!settings.canAddSubscription(address: "webcal://example.com/a.ics"))
            #expect(!settings.addSubscription(name: "Again", address: "webcal://example.com/a.ics"))
            #expect(settings.subscriptions.count == 1)
        }
    }

    @Test func colorsReuseFreedSlots() {
        withSettings { _, make in
            let settings = make()
            for index in 0..<3 {
                settings.addSubscription(name: "", address: "https://example.com/\(index).ics")
            }
            #expect(settings.subscriptions.map(\.colorIndex) == [0, 1, 2])
            settings.removeSubscription(id: settings.subscriptions[1].id)
            #expect(settings.subscriptions.map(\.colorIndex) == [0, 2])
            settings.addSubscription(name: "", address: "https://example.com/new.ics")
            #expect(settings.subscriptions.map(\.colorIndex) == [0, 2, 1])
        }
    }

    @Test func subscriptionsCanBeDisabledRenamedAndRemoved() {
        withSettings { _, make in
            let settings = make()
            settings.addSubscription(name: "", address: "https://example.com/a.ics")
            let id = settings.subscriptions[0].id
            settings.setSubscription(id: id, enabled: false)
            #expect(make().subscriptions[0].isEnabled == false)
            settings.renameSubscription(id: id, to: " Family ")
            #expect(make().subscriptions[0].name == "Family")
            settings.removeSubscription(id: id)
            #expect(settings.subscriptions.isEmpty)
            #expect(make().subscriptions.isEmpty)
        }
    }

    @Test func undecodableSavedValuesFallBack() {
        withSettings { defaults, make in
            defaults.set(Data("nonsense".utf8), forKey: CalendarSettings.subscriptionsKey)
            defaults.set("seven", forKey: CalendarSettings.dayCountKey)
            defaults.set(42, forKey: CalendarSettings.hiddenCalendarsKey)
            let settings = make()
            #expect(settings.subscriptions.isEmpty)
            #expect(settings.dayCount == 3)
            #expect(settings.hiddenCalendarIDs.isEmpty)
        }
    }
}

@MainActor
struct CalendarSubscriptionTests {
    private func subscription(name: String = "") -> CalendarSubscription {
        CalendarSubscription(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            name: name,
            address: "https://outlook.office365.com/owa/calendar/abc/def/calendar.ics",
            isEnabled: true,
            colorIndex: 2
        )
    }

    @Test func displayNameFallsBackToTheFeedThenTheHost() {
        #expect(subscription(name: "Work").displayName(feedName: "Feed") == "Work")
        #expect(subscription().displayName(feedName: " Feed ") == "Feed")
        #expect(subscription().displayName(feedName: nil) == "outlook.office365.com")
        #expect(subscription().displayName(feedName: "  ") == "outlook.office365.com")
    }

    @Test func occurrencesBecomeAgendaEvents() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let occurrences = [
            ICalendarOccurrence(uid: "a", title: "Standup", location: "Room 1", start: start,
                                end: start.addingTimeInterval(900), isAllDay: false),
            ICalendarOccurrence(uid: "a", title: "Standup", location: nil, start: start.addingTimeInterval(86_400),
                                end: start.addingTimeInterval(87_300), isAllDay: false),
        ]
        let events = subscription().agendaEvents(from: occurrences, feedName: "Team")
        #expect(events.count == 2)
        #expect(events[0].id == "sub:00000000-0000-0000-0000-000000000001:a:1800000000.0")
        #expect(events[1].id == "sub:00000000-0000-0000-0000-000000000001:a:1800086400.0")
        #expect(events[0].title == "Standup")
        #expect(events[0].location == "Room 1")
        #expect(events[0].start == start)
        #expect(events[0].end == start.addingTimeInterval(900))
        #expect(events[0].calendarTitle == "Team")
        #expect(events[0].color == CalendarSubscription.palette[2])
    }

    @Test func repeatedOccurrencesKeepUniqueIDs() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let occurrences = [
            ICalendarOccurrence(uid: "a", title: "One", location: nil, start: start, end: start, isAllDay: false),
            ICalendarOccurrence(uid: "a", title: "Two", location: nil, start: start, end: start, isAllDay: false),
        ]
        let ids = subscription().agendaEvents(from: occurrences, feedName: nil).map(\.id)
        #expect(Set(ids).count == 2)
    }
}

struct CalendarRefreshPolicyTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func refreshesWithoutADownload() {
        #expect(CalendarRefreshPolicy.shouldRefresh(now: now, lastSuccess: nil, lastFailure: nil, isInFlight: false))
    }

    @Test func neverTwiceAtOnce() {
        #expect(!CalendarRefreshPolicy.shouldRefresh(now: now, lastSuccess: nil, lastFailure: nil, isInFlight: true))
        #expect(!CalendarRefreshPolicy.shouldRefresh(
            now: now, lastSuccess: now.addingTimeInterval(-3600), lastFailure: nil, isInFlight: true))
    }

    @Test func freshForFifteenMinutes() {
        #expect(!CalendarRefreshPolicy.shouldRefresh(
            now: now, lastSuccess: now.addingTimeInterval(-14 * 60), lastFailure: nil, isInFlight: false))
        #expect(CalendarRefreshPolicy.shouldRefresh(
            now: now, lastSuccess: now.addingTimeInterval(-15 * 60), lastFailure: nil, isInFlight: false))
    }

    @Test func retriesTwoMinutesAfterAFailure() {
        #expect(!CalendarRefreshPolicy.shouldRefresh(
            now: now, lastSuccess: nil, lastFailure: now.addingTimeInterval(-60), isInFlight: false))
        #expect(CalendarRefreshPolicy.shouldRefresh(
            now: now, lastSuccess: nil, lastFailure: now.addingTimeInterval(-120), isInFlight: false))
        // A failure after an old success waits as well.
        #expect(!CalendarRefreshPolicy.shouldRefresh(
            now: now, lastSuccess: now.addingTimeInterval(-3600), lastFailure: now.addingTimeInterval(-60),
            isInFlight: false))
    }

    @Test func coverageRunsFromYesterdayToFifteenDaysAhead() {
        let zone = TimeZone(secondsFromGMT: 8 * 3600)!
        var calendar = Foundation.Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let coverage = CalendarRefreshPolicy.coverage(now: instant(2026, 10, 22, 10, in: zone), calendar: calendar)
        #expect(coverage.start == instant(2026, 10, 21, in: zone))
        #expect(coverage.end == instant(2026, 11, 6, in: zone))
    }
}

struct CalendarFormatTests {
    private let zone = TimeZone(secondsFromGMT: 8 * 3600)!
    private var calendar: Foundation.Calendar {
        var calendar = Foundation.Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar
    }

    private func oct(_ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        instant(2026, 10, day, hour, minute, in: zone)
    }

    /// Thursday 22 October 2026, 10:00.
    private var now: Date { oct(22, 10) }

    private func entry(_ start: Date, _ end: Date, allDay: Bool = false, on day: Date) -> AgendaEntry {
        let event = AgendaEvent(
            id: "e", title: "E", location: nil, start: start, end: end, isAllDay: allDay,
            color: CalendarColor(red: 0, green: 0, blue: 0), calendarTitle: "Test"
        )
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: day)!
        return AgendaEntry(event: event, day: day, startsBeforeDay: start < day, endsAfterDay: end > dayEnd)
    }

    private func time(_ entry: AgendaEntry, _ language: AppLanguage = .english) -> String {
        CalendarFormat.timeText(entry, now: now, language: language, calendar: calendar)
    }

    @Test func timedEventShowsItsRange() {
        #expect(time(entry(oct(22, 13), oct(22, 14, 30), on: oct(22))) == "13:00–14:30")
        #expect(time(entry(oct(23, 9), oct(23, 10, 30), on: oct(23))) == "09:00–10:30")
    }

    @Test func allDay() {
        #expect(time(entry(oct(23), oct(24), allDay: true, on: oct(23))) == "All day")
        #expect(time(entry(oct(23), oct(24), allDay: true, on: oct(23)), .simplifiedChinese) == "全天")
    }

    @Test func eventFromAnEarlierDay() {
        #expect(time(entry(oct(22, 22), oct(23, 2), on: oct(23))) == "Until 02:00")
        #expect(time(entry(oct(22, 22), oct(23, 2), on: oct(23)), .simplifiedChinese) == "至 02:00")
    }

    @Test func eventIntoALaterDay() {
        #expect(time(entry(oct(23, 22), oct(24, 2), on: oct(23))) == "From 22:00")
        #expect(time(entry(oct(23, 22), oct(24, 2), on: oct(23)), .simplifiedChinese) == "22:00 起")
    }

    @Test func ongoingEvent() {
        #expect(time(entry(oct(22, 9), oct(22, 10, 30), on: oct(22))) == "Now · until 10:30")
        #expect(time(entry(oct(22, 9), oct(22, 10, 30), on: oct(22)), .simplifiedChinese) == "进行中 · 至 10:30")
    }

    @Test func dayTitles() {
        #expect(CalendarFormat.dayTitle(oct(22), now: now, language: .english, calendar: calendar) == "Today")
        #expect(CalendarFormat.dayTitle(oct(23), now: now, language: .english, calendar: calendar) == "Tomorrow")
        #expect(CalendarFormat.dayTitle(oct(22), now: now, language: .simplifiedChinese, calendar: calendar) == "今天")
        #expect(CalendarFormat.dayTitle(oct(23), now: now, language: .simplifiedChinese, calendar: calendar) == "明天")
    }
}

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
            #expect(settings.source == .all)
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

    @Test func sourceSurvivesARelaunch() {
        withSettings { _, make in
            let settings = make()
            settings.source = .cloud
            #expect(make().source == .cloud)
            settings.source = .local
            #expect(make().source == .local)
            settings.source = .all
            #expect(make().source == .all)
        }
    }

    @Test func unknownSavedSourceFallsBackToAll() {
        withSettings { defaults, make in
            defaults.set("icloud", forKey: CalendarSettings.sourceKey)
            #expect(make().source == .all)
            defaults.set(3, forKey: CalendarSettings.sourceKey)
            #expect(make().source == .all)
        }
    }

    @Test func sourceSaysWhichKindsItIncludes() {
        #expect(CalendarSource.allCases == [.all, .local, .cloud])
        #expect(CalendarSource.all.includesLocal && CalendarSource.all.includesCloud)
        #expect(CalendarSource.local.includesLocal && !CalendarSource.local.includesCloud)
        #expect(!CalendarSource.cloud.includesLocal && CalendarSource.cloud.includesCloud)
    }

    @Test func localSourceNeedsOnlyAccessToEmptyTheCard() {
        func state(
            _ source: CalendarSource,
            _ access: LocalCalendars.Access,
            subscriptions: Bool = false,
            fetching: Bool = false,
            failed: Bool = false
        ) -> CalendarCardState {
            CalendarCardState.state(
                source: source,
                access: access,
                hasEnabledSubscriptions: subscriptions,
                isFetchingFirstTime: fetching,
                hasFailedWithoutData: failed
            )
        }
        // This Mac: subscriptions and their feeds never matter.
        #expect(state(.local, .notDetermined, subscriptions: true) == .allowAccess)
        #expect(state(.local, .denied, subscriptions: true, fetching: true) == .accessNeeded)
        #expect(state(.local, .granted, subscriptions: true, fetching: true, failed: true) == .empty)
        // Cloud: the Calendar app's access never matters.
        #expect(state(.cloud, .notDetermined) == .addLinks)
        #expect(state(.cloud, .denied) == .addLinks)
        #expect(state(.cloud, .notDetermined, subscriptions: true) == .empty)
        #expect(state(.cloud, .denied, subscriptions: true, fetching: true) == .loading)
        #expect(state(.cloud, .granted, subscriptions: true, failed: true) == .failed)
        // All: as before the switch existed.
        #expect(state(.all, .notDetermined) == .allowAccess)
        #expect(state(.all, .denied) == .accessNeeded)
        #expect(state(.all, .notDetermined, subscriptions: true) == .empty)
        #expect(state(.all, .denied, subscriptions: true, fetching: true) == .loading)
        #expect(state(.all, .granted, subscriptions: true, failed: true) == .failed)
        #expect(state(.all, .granted) == .empty)
    }

    @Test func accessIsRequestedOnlyWhereTheSourceNeedsIt() {
        func requests(_ source: CalendarSource, _ access: LocalCalendars.Access, subscriptions: Bool = false) -> Bool {
            CalendarCardState.shouldRequestAccess(source: source, access: access, hasEnabledSubscriptions: subscriptions)
        }
        #expect(requests(.all, .notDetermined))
        #expect(!requests(.all, .notDetermined, subscriptions: true))
        #expect(requests(.local, .notDetermined, subscriptions: true))
        #expect(!requests(.cloud, .notDetermined))
        #expect(!requests(.local, .granted))
        #expect(!requests(.all, .denied))
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

    private func event(
        _ start: Date, _ end: Date, allDay: Bool = false, title: String = "Review",
        location: String? = nil, calendarTitle: String = "Work", meetingURL: URL? = nil
    ) -> AgendaEvent {
        AgendaEvent(
            id: "e", title: title, location: location, start: start, end: end, isAllDay: allDay,
            color: CalendarColor(red: 0, green: 0, blue: 0), calendarTitle: calendarTitle, meetingURL: meetingURL
        )
    }

    private func date(_ day: Date, _ language: AppLanguage = .english) -> String {
        CalendarFormat.date(day, language: language, calendar: calendar)
    }

    private func span(_ event: AgendaEvent, _ language: AppLanguage = .english) -> String {
        CalendarFormat.spanText(event, language: language, calendar: calendar)
    }

    @Test func cappedTrimsAndCutsAbsurdLengths() {
        #expect(CalendarFormat.capped("  Standup \n") == "Standup")
        #expect(CalendarFormat.capped(" \n\t ") == "")
        let limit = CalendarFormat.maxTextLength
        let exact = String(repeating: "a", count: limit)
        #expect(CalendarFormat.capped(exact) == exact)
        let long = String(repeating: "b", count: 2_000_000)
        #expect(CalendarFormat.capped(long) == String(repeating: "b", count: limit) + "…")
        // Leading whitespace does not count toward the limit.
        #expect(CalendarFormat.capped(String(repeating: " ", count: limit) + "x") == "x")
    }

    @Test func titleFallsBackWhenEmpty() {
        #expect(CalendarFormat.title(event(oct(22, 13), oct(22, 14), title: " Plan "), language: .english) == "Plan")
        #expect(CalendarFormat.title(event(oct(22, 13), oct(22, 14), title: "  "), language: .english) == "No Title")
        #expect(CalendarFormat.title(event(oct(22, 13), oct(22, 14), title: ""), language: .simplifiedChinese) == "无标题")
    }

    @Test func spanOnOneDay() {
        #expect(span(event(oct(24, 13), oct(24, 14, 30))) == "\(date(oct(24))) · 13:00–14:30")
        #expect(span(event(oct(24, 9), oct(24, 9))) == "\(date(oct(24))) · 09:00")
        // A feed's all-day event ends at the next midnight, EventKit's at 23:59:59.
        #expect(span(event(oct(24), oct(25), allDay: true)) == "\(date(oct(24))) · All day")
        #expect(span(event(oct(24), oct(24, 23, 59), allDay: true)) == "\(date(oct(24))) · All day")
        #expect(span(event(oct(24), oct(25), allDay: true), .simplifiedChinese)
            == "\(date(oct(24), .simplifiedChinese)) · 全天")
    }

    @Test func spanOverSeveralDays() {
        #expect(span(event(oct(24), oct(27), allDay: true)) == "\(date(oct(24))) – \(date(oct(26)))")
        #expect(span(event(oct(24, 22), oct(25, 2))) == "\(date(oct(24))) 22:00 – \(date(oct(25))) 02:00")
    }

    @Test func copyTextListsWhatTheEventHas() {
        let link = URL(string: "https://meet.google.com/abc-defg-hij")!
        let full = event(
            oct(24, 13), oct(24, 14), title: " Design review ", location: "Room 4\nLevel 2",
            meetingURL: link
        )
        #expect(CalendarFormat.copyText(full, language: .english, calendar: calendar) == """
            Design review
            \(date(oct(24))) · 13:00–14:00
            Room 4
            Level 2
            Work
            https://meet.google.com/abc-defg-hij
            """)
        let bare = event(oct(24, 13), oct(24, 14), title: "", calendarTitle: "")
        #expect(CalendarFormat.copyText(bare, language: .english, calendar: calendar)
            == "No Title\n\(date(oct(24))) · 13:00–14:00")
    }
}

@MainActor
struct AgendaCardStateTests {
    @Test func oneEntryExpandsAtATime() {
        let state = AgendaCardState()
        #expect(state.expandedID == nil)
        state.toggle("a")
        #expect(state.expandedID == "a")
        state.toggle("b")
        #expect(state.expandedID == "b")
        state.toggle("b")
        #expect(state.expandedID == nil)
    }

    @Test func copiedReadsForAMoment() async throws {
        let state = AgendaCardState()
        state.copied("a", for: .milliseconds(50))
        #expect(state.copiedID == "a")
        // Another copy takes over and starts the time over.
        state.copied("b", for: .milliseconds(50))
        #expect(state.copiedID == "b")
        let deadline = ContinuousClock.now + .seconds(5)
        while state.copiedID != nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(state.copiedID == nil)
    }
}

@MainActor
struct EventReminderLeadSettingsTests {
    @Test func defaultsToFiveMinutes() {
        withSettings { _, make in
            #expect(make().reminderLead == .fiveMinutes)
            #expect(make().reminderLead.minutes == 5)
        }
    }

    @Test func offersTheChoicesInOrder() {
        #expect(EventReminderLead.allCases.map(\.minutes) == [nil, 0, 1, 5, 10, 15, 30, 60])
    }

    @Test func everyChoiceSurvivesARelaunch() {
        withSettings { _, make in
            let settings = make()
            for lead in [EventReminderLead.off, .atStart] + EventReminderLead.allCases {
                settings.reminderLead = lead
                #expect(make().reminderLead == lead)
            }
        }
    }

    @Test func unknownSavedLeadFallsBackToFiveMinutes() {
        withSettings { defaults, make in
            defaults.set(7, forKey: CalendarSettings.reminderLeadKey)
            #expect(make().reminderLead == .fiveMinutes)
            defaults.set("soon", forKey: CalendarSettings.reminderLeadKey)
            #expect(make().reminderLead == .fiveMinutes)
        }
    }
}

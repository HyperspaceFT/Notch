import Foundation
import Testing
@testable import CalendarFeature

/// Thursday 22 October 2026, 10:00 UTC: the start of the event under test.
private let start = instant(2026, 10, 22, 10, 0, in: .gmt)

private func event(
    _ title: String, start: Date = start, minutes: Double = 30, allDay: Bool = false, id: String? = nil
) -> AgendaEvent {
    AgendaEvent(
        id: id ?? title, title: title, location: nil, start: start,
        end: start.addingTimeInterval(minutes * 60), isAllDay: allDay,
        color: CalendarColor(red: 0.2, green: 0.4, blue: 0.6), calendarTitle: "Test"
    )
}

private func plan(
    _ events: [AgendaEvent], at now: Date, lead: Int?, fired: Set<EventReminderKey> = []
) -> EventReminderPlan {
    EventReminderPlanner.plan(events: events, now: now, leadMinutes: lead, fired: fired)
}

/// The kinds and minutes left of the notice's reminders.
private func due(_ plan: EventReminderPlan) -> [String] {
    (plan.notice?.reminders ?? []).map { reminder in
        switch reminder.kind {
        case .upcoming: "\(reminder.event.title) upcoming \(reminder.minutesLeft)"
        case .starting: "\(reminder.event.title) starting"
        }
    }
}

struct EventReminderPlannerTests {
    @Test func nothingBeforeTheLeadTimeAndNextCheckAtIt() {
        let result = plan([event("Standup")], at: start.addingTimeInterval(-6 * 60), lead: 5)
        #expect(result.notice == nil)
        #expect(result.nextCheck == start.addingTimeInterval(-5 * 60))
    }

    @Test func upcomingAtTheLeadTime() {
        let result = plan([event("Standup")], at: start.addingTimeInterval(-5 * 60), lead: 5)
        #expect(due(result) == ["Standup upcoming 5"])
        // The starting reminder is next.
        #expect(result.nextCheck == start)
    }

    @Test func firstSeenInsideTheLeadTimeRoundsMinutesUp() {
        let result = plan([event("Standup")], at: start.addingTimeInterval(-150), lead: 5)
        #expect(due(result) == ["Standup upcoming 3"])
    }

    @Test func startingAtTheStartAndShortlyAfter() {
        #expect(due(plan([event("Standup")], at: start, lead: 5)) == ["Standup starting"])
        #expect(due(plan([event("Standup")], at: start.addingTimeInterval(2 * 60), lead: 5)) == ["Standup starting"])
    }

    @Test func nothingLongAfterTheStart() {
        let result = plan([event("Standup")], at: start.addingTimeInterval(6 * 60), lead: 5)
        #expect(result.notice == nil)
        #expect(result.nextCheck == nil)
    }

    @Test func leadAtStartGivesOnlyTheStartingReminder() {
        let before = plan([event("Standup")], at: start.addingTimeInterval(-60), lead: 0)
        #expect(before.notice == nil)
        #expect(before.nextCheck == start)
        #expect(due(plan([event("Standup")], at: start, lead: 0)) == ["Standup starting"])
    }

    @Test func offGivesNothing() {
        for offset in [-5.0 * 60, -60, 0, 60] {
            let result = plan([event("Standup")], at: start.addingTimeInterval(offset), lead: nil)
            #expect(result.notice == nil)
            #expect(result.nextCheck == nil)
        }
    }

    @Test func allDayEventsAreSkipped() {
        let holiday = event("Holiday", minutes: 24 * 60, allDay: true)
        #expect(plan([holiday], at: start.addingTimeInterval(-60), lead: 5) == EventReminderPlan(notice: nil, nextCheck: nil))
        #expect(plan([holiday], at: start, lead: 5) == EventReminderPlan(notice: nil, nextCheck: nil))
    }

    @Test func firedRemindersAreNotRepeated() {
        let standup = event("Standup")
        let upcoming = EventReminderKey(eventID: standup.id, kind: .upcoming)
        let starting = EventReminderKey(eventID: standup.id, kind: .starting)
        let before = plan([standup], at: start.addingTimeInterval(-4 * 60), lead: 5, fired: [upcoming])
        #expect(before.notice == nil)
        #expect(before.nextCheck == start)
        let after = plan([standup], at: start.addingTimeInterval(60), lead: 5, fired: [upcoming, starting])
        #expect(after.notice == nil)
        #expect(after.nextCheck == nil)
    }

    @Test func remindersDueTogetherFormOneNotice() {
        let review = event("Review", start: start.addingTimeInterval(3 * 60))
        let standup = event("Standup")
        let result = plan([review, standup], at: start.addingTimeInterval(-60), lead: 5)
        #expect(due(result) == ["Standup upcoming 1", "Review upcoming 4"])
        #expect(result.notice?.first.event.title == "Standup")
        #expect(result.notice?.othersCount == 1)
    }

    @Test func noStartingReminderOnceTheEventEnded() {
        // 09:00–09:02, first seen at 09:04.
        let short = event("Call", start: start.addingTimeInterval(-60 * 60), minutes: 2)
        let result = plan([short], at: start.addingTimeInterval(-56 * 60), lead: 5)
        #expect(result.notice == nil)
        #expect(result.nextCheck == nil)
    }

    @Test func zeroLengthEventStillStartsAtItsStart() {
        #expect(due(plan([event("Deadline", minutes: 0)], at: start, lead: 5)) == ["Deadline starting"])
    }

    @Test func sameTitleAndStartAreRemindedOnce() {
        let local = event("Standup", id: "ek:1")
        let subscribed = event("Standup", id: "sub:1")
        let result = plan([subscribed, local], at: start.addingTimeInterval(-5 * 60), lead: 5)
        // The first by start, title, then id.
        #expect(result.notice?.reminders.map(\.event.id) == ["ek:1"])
        #expect(result.notice?.reminders.map(\.minutesLeft) == [5])
        // Titles are compared trimmed.
        let padded = event(" Standup ", id: "sub:3")
        #expect(plan([padded, local], at: start, lead: 5).notice?.reminders.count == 1)
        // A different start is a different event.
        let later = event("Standup", start: start.addingTimeInterval(60), id: "sub:2")
        #expect(plan([local, later], at: start.addingTimeInterval(-4 * 60), lead: 5).notice?.reminders.count == 2)
    }

    @Test func tiesAreOrderedByTitle() {
        let result = plan([event("Zeta"), event("Alpha")], at: start, lead: 5)
        #expect(due(result) == ["Alpha starting", "Zeta starting"])
    }
}

struct EventReminderPhaseTests {
    @Test func beforeTheStartCountsMinutesUp() {
        #expect(EventReminderPhase(start: start, now: start.addingTimeInterval(-5 * 60)) == .startsIn(minutes: 5))
        #expect(EventReminderPhase(start: start, now: start.addingTimeInterval(-150)) == .startsIn(minutes: 3))
        #expect(EventReminderPhase(start: start, now: start.addingTimeInterval(-1)) == .startsIn(minutes: 1))
    }

    @Test func startingNowForTheStartingWindow() {
        #expect(EventReminderPhase(start: start, now: start) == .startingNow)
        #expect(EventReminderPhase(start: start, now: start.addingTimeInterval(4 * 60 + 59)) == .startingNow)
    }

    @Test func laterCountsMinutesSinceTheStart() {
        #expect(EventReminderPhase(start: start, now: start.addingTimeInterval(5 * 60)) == .startedAgo(minutes: 5))
        #expect(EventReminderPhase(start: start, now: start.addingTimeInterval(7 * 60 + 30)) == .startedAgo(minutes: 7))
    }

    @Test func noticeEndsWithItsLastEvent() {
        let short = EventReminder(event: event("Call", minutes: 2), kind: .starting, minutesLeft: 0)
        let long = EventReminder(event: event("Review", minutes: 30), kind: .starting, minutesLeft: 0)
        #expect(EventReminderNotice(reminders: [short]).endsAt == start.addingTimeInterval(2 * 60))
        #expect(EventReminderNotice(reminders: [short, long]).endsAt == start.addingTimeInterval(30 * 60))
    }

    @Test func zeroLengthEventEndsFiveMinutesAfterItsStart() {
        let deadline = EventReminder(event: event("Deadline", minutes: 0), kind: .starting, minutesLeft: 0)
        #expect(EventReminderNotice(reminders: [deadline]).endsAt == start.addingTimeInterval(5 * 60))
    }
}

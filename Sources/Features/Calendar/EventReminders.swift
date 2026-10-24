import Foundation

/// Which reminder of an event is shown.
enum EventReminderKind: Sendable, Equatable, Hashable {
    /// Within the lead time before the event starts.
    case upcoming
    /// In the first minutes after it started (`EventReminderPlanner.startingWindow`).
    case starting
}

/// One event due for a reminder.
struct EventReminder: Sendable, Equatable {
    var event: AgendaEvent
    var kind: EventReminderKind
    /// Whole minutes until the start, rounded up; 0 for `.starting`.
    var minutesLeft: Int

    var key: EventReminderKey { EventReminderKey(eventID: event.id, kind: kind) }
}

/// Identifies a reminder already shown, so it is not shown again.
struct EventReminderKey: Sendable, Hashable {
    var eventID: String
    var kind: EventReminderKind
}

/// The reminders due together, shown as one activity: the wings show the
/// first, the detail lists them all.
struct EventReminderNotice: Sendable, Equatable {
    /// By start, then title; never empty.
    var reminders: [EventReminder]

    var first: EventReminder { reminders[0] }
    /// How many more there are than the one the wings show.
    var othersCount: Int { reminders.count - 1 }
}

/// What a check finds: the reminders due now, and when the next one becomes due.
struct EventReminderPlan: Sendable, Equatable {
    var notice: EventReminderNotice?
    /// The earliest moment after now at which a reminder not shown yet
    /// becomes due; nil when none will within the events given.
    var nextCheck: Date?
}

/// Decides which event reminders are due. Each timed event gets an upcoming
/// reminder from `lead` minutes before its start until the start, and a
/// starting reminder from its start for `startingWindow` (or until it ends,
/// when that is sooner); an event first seen inside a window is reminded at
/// once. All-day events get none, and events with the same title and start
/// (one calendar both in the Calendar app and subscribed) are reminded once.
enum EventReminderPlanner {
    /// How long after an event's start its starting reminder may still show.
    static let startingWindow: TimeInterval = 5 * 60

    /// The span whose events a check needs: from `startingWindow` ago to a
    /// minute past the lead time, so an event added within the next minute
    /// before the following check is seen in time.
    static func window(now: Date, leadMinutes: Int) -> DateInterval {
        DateInterval(
            start: now.addingTimeInterval(-startingWindow),
            end: now.addingTimeInterval(TimeInterval(max(leadMinutes, 0) + 1) * 60)
        )
    }

    /// The reminders due at `now` that are not in `fired`, as one notice, and
    /// the next moment another one becomes due. `leadMinutes` nil (reminders
    /// off) plans nothing; 0 gives only starting reminders.
    static func plan(
        events: [AgendaEvent],
        now: Date,
        leadMinutes: Int?,
        fired: Set<EventReminderKey>
    ) -> EventReminderPlan {
        guard let leadMinutes else { return EventReminderPlan(notice: nil, nextCheck: nil) }
        let lead = TimeInterval(max(leadMinutes, 0)) * 60
        var due: [EventReminder] = []
        var nextCheck: Date?
        func consider(_ date: Date) {
            if date > now, nextCheck.map({ date < $0 }) ?? true {
                nextCheck = date
            }
        }
        for event in distinctTimedEvents(events) {
            let start = event.start
            if lead > 0, !fired.contains(EventReminderKey(eventID: event.id, kind: .upcoming)) {
                let from = start.addingTimeInterval(-lead)
                if now >= from, now < start {
                    let minutes = Int((start.timeIntervalSince(now) / 60).rounded(.up))
                    due.append(EventReminder(event: event, kind: .upcoming, minutesLeft: minutes))
                } else {
                    consider(from)
                }
            }
            if !fired.contains(EventReminderKey(eventID: event.id, kind: .starting)) {
                // A zero-length event counts as going on at its start.
                let hasEnded = event.end > event.start && now >= event.end
                if now >= start, now < start.addingTimeInterval(startingWindow), !hasEnded {
                    due.append(EventReminder(event: event, kind: .starting, minutesLeft: 0))
                } else {
                    consider(start)
                }
            }
        }
        due.sort { remindsBefore($0.event, $1.event) }
        return EventReminderPlan(notice: due.isEmpty ? nil : EventReminderNotice(reminders: due), nextCheck: nextCheck)
    }

    /// The events that are not all-day, in reminder order, keeping only the
    /// first of those with the same trimmed title and start.
    private static func distinctTimedEvents(_ events: [AgendaEvent]) -> [AgendaEvent] {
        struct Identity: Hashable {
            var title: String
            var start: Date
        }
        var seen = Set<Identity>()
        return events
            .filter { !$0.isAllDay }
            .sorted(by: remindsBefore)
            .filter { event in
                seen.insert(Identity(
                    title: event.title.trimmingCharacters(in: .whitespacesAndNewlines),
                    start: event.start
                )).inserted
            }
    }

    /// By start, then title, then id.
    private static func remindsBefore(_ first: AgendaEvent, _ second: AgendaEvent) -> Bool {
        if first.start != second.start { return first.start < second.start }
        switch first.title.localizedStandardCompare(second.title) {
        case .orderedAscending: return true
        case .orderedDescending: return false
        case .orderedSame: return first.id < second.id
        }
    }
}

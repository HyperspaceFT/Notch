import Foundation
import NotchKit

/// Sample reminders for the Debug pane: built like the planner's, but from events
/// that exist nowhere, so showing one never touches a calendar, a feed, or the
/// reminders already fired. The events end well after the reminder's ten seconds,
/// so the reminder loop does not withdraw them early.
@MainActor
enum EventReminderSamples {
    /// One event with a location, five minutes before it starts.
    static func startsInFiveMinutes(now: Date) -> EventReminderNotice {
        let event = event(
            id: "design-review",
            title: localized(en: "Design Review", zh: "设计评审"),
            location: localized(en: "Room 4B", zh: "4B 会议室"),
            start: now.addingTimeInterval(5 * 60),
            color: CalendarColor(red: 0.04, green: 0.52, blue: 1.0),
            calendarTitle: localized(en: "Work", zh: "工作")
        )
        return EventReminderNotice(reminders: [
            EventReminder(event: event, kind: .upcoming, minutesLeft: 5),
        ])
    }

    /// One event that starts now and has a meeting link; the link is a placeholder
    /// the detail's Join button opens only when the user clicks it.
    static func startingNowWithMeetingLink(now: Date) -> EventReminderNotice {
        let event = event(
            id: "weekly-sync",
            title: localized(en: "Weekly Sync", zh: "每周例会"),
            location: nil,
            start: now,
            color: CalendarColor(red: 0.19, green: 0.82, blue: 0.35),
            calendarTitle: localized(en: "Work", zh: "工作"),
            meetingURL: URL(string: "https://meet.google.com/abc-defg-hij")
        )
        return EventReminderNotice(reminders: [
            EventReminder(event: event, kind: .starting, minutesLeft: 0),
        ])
    }

    /// Three events due together, in calendars of different colors: one starting
    /// now and two upcoming, so the wings show "+2" and the detail lists rows.
    static func threeAtOnce(now: Date) -> EventReminderNotice {
        let starting = event(
            id: "standup",
            title: localized(en: "Standup", zh: "站会"),
            location: nil,
            start: now,
            color: CalendarColor(red: 1.0, green: 0.62, blue: 0.04),
            calendarTitle: localized(en: "Work", zh: "工作")
        )
        let lunch = event(
            id: "lunch",
            title: localized(en: "Lunch with Sam", zh: "和小山吃午饭"),
            location: localized(en: "Corner Cafe", zh: "街角咖啡馆"),
            start: now.addingTimeInterval(3 * 60),
            color: CalendarColor(red: 0.69, green: 0.32, blue: 0.87),
            calendarTitle: localized(en: "Personal", zh: "个人")
        )
        let call = event(
            id: "call",
            title: localized(en: "Call with the Landlord", zh: "给房东回电话"),
            location: nil,
            start: now.addingTimeInterval(5 * 60),
            color: CalendarColor(red: 1.0, green: 0.27, blue: 0.23),
            calendarTitle: localized(en: "Home", zh: "家庭")
        )
        return EventReminderNotice(reminders: [
            EventReminder(event: starting, kind: .starting, minutesLeft: 0),
            EventReminder(event: lunch, kind: .upcoming, minutesLeft: 3),
            EventReminder(event: call, kind: .upcoming, minutesLeft: 5),
        ])
    }

    private static func event(
        id: String,
        title: String,
        location: String?,
        start: Date,
        color: CalendarColor,
        calendarTitle: String,
        meetingURL: URL? = nil
    ) -> AgendaEvent {
        AgendaEvent(
            id: "debug-\(id)",
            title: title,
            location: location,
            start: start,
            end: start.addingTimeInterval(30 * 60),
            isAllDay: false,
            color: color,
            calendarTitle: calendarTitle,
            meetingURL: meetingURL
        )
    }
}

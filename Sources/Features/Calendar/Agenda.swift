import Foundation

/// A calendar's color, each channel in 0...1.
struct CalendarColor: Sendable, Equatable, Hashable {
    var red: Double
    var green: Double
    var blue: Double
}

/// One event occurrence from any source (EventKit or a subscribed feed), in
/// the form the agenda lists it.
struct AgendaEvent: Sendable, Equatable, Identifiable {
    /// Unique per occurrence across all sources.
    var id: String
    var title: String
    var location: String?
    var start: Date
    /// Exclusive. EventKit all-day events end at 23:59:59 of their last day,
    /// feed ones at the following midnight; the agenda treats both alike.
    var end: Date
    var isAllDay: Bool
    var color: CalendarColor
    var calendarTitle: String
}

/// An event as listed on one day of the agenda.
struct AgendaEntry: Sendable, Equatable, Identifiable {
    var event: AgendaEvent
    /// Local midnight of the day it is listed on.
    var day: Date
    /// The event began on an earlier day.
    var startsBeforeDay: Bool
    /// The event continues into a later day.
    var endsAfterDay: Bool
    /// The event's id and the day, unique across the agenda.
    var id: String

    init(event: AgendaEvent, day: Date, startsBeforeDay: Bool, endsAfterDay: Bool) {
        self.event = event
        self.day = day
        self.startsBeforeDay = startsBeforeDay
        self.endsAfterDay = endsAfterDay
        id = "\(event.id)@\(day.timeIntervalSince1970)"
    }
}

/// One day of the agenda with what is listed on it.
struct AgendaDay: Sendable, Equatable, Identifiable {
    /// Local midnight.
    var start: Date
    var entries: [AgendaEntry]
    var id: Date { start }
}

/// Groups events into the days the agenda shows: today and the days after it.
enum Agenda {
    /// How many days, today included, the agenda may show.
    static let dayCountRange = 1...14

    /// From the start of today to the start of the day `dayCount` days later,
    /// with `dayCount` clamped to `dayCountRange`.
    static func window(now: Date, dayCount: Int, calendar: Foundation.Calendar) -> DateInterval {
        let count = min(max(dayCount, dayCountRange.lowerBound), dayCountRange.upperBound)
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: count, to: start) ?? start.addingTimeInterval(Double(count) * 86_400)
        return DateInterval(start: start, end: end)
    }

    /// The days of the window that have events, in order. An event that has
    /// ended by `now` is dropped (a zero-length one once its start has
    /// passed); any other is listed on every day of the window it overlaps.
    /// Within a day, all-day entries come first by title, then the rest by
    /// start, end and title.
    static func days(for events: [AgendaEvent], now: Date, dayCount: Int, calendar: Foundation.Calendar) -> [AgendaDay] {
        let window = window(now: now, dayCount: dayCount, calendar: calendar)
        let current = events.filter { event in
            event.end > event.start ? event.end > now : event.start >= now
        }
        var result: [AgendaDay] = []
        var dayStart = window.start
        while dayStart < window.end {
            guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { break }
            let entries = current
                .filter { event in
                    event.end > event.start
                        ? event.start < dayEnd && event.end > dayStart
                        : event.start >= dayStart && event.start < dayEnd
                }
                .map { event in
                    AgendaEntry(
                        event: event,
                        day: dayStart,
                        startsBeforeDay: event.start < dayStart,
                        endsAfterDay: event.end > dayEnd
                    )
                }
                .sorted(by: listsBefore)
            if !entries.isEmpty {
                result.append(AgendaDay(start: dayStart, entries: entries))
            }
            dayStart = dayEnd
        }
        return result
    }

    private static func listsBefore(_ first: AgendaEntry, _ second: AgendaEntry) -> Bool {
        let a = first.event
        let b = second.event
        if a.isAllDay != b.isAllDay { return a.isAllDay }
        if !a.isAllDay {
            if a.start != b.start { return a.start < b.start }
            if a.end != b.end { return a.end < b.end }
        }
        switch a.title.localizedStandardCompare(b.title) {
        case .orderedAscending: return true
        case .orderedDescending: return false
        case .orderedSame: return a.id < b.id
        }
    }
}

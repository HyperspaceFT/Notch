import Foundation
import NotchKit

/// A reminder list's color in sRGB.
struct ReminderColor: Sendable, Equatable, Hashable {
    var red: Double
    var green: Double
    var blue: Double
}

/// When a reminder is due. A date-only due is the start of its day.
struct ReminderDue: Sendable, Equatable, Hashable {
    var date: Date
    var hasTime: Bool

    /// From a reminder's due date components: timed when they carry an hour;
    /// otherwise the start of that day in `calendar`. `nil` without a usable date.
    init?(components: DateComponents?, calendar: Calendar) {
        guard let components else { return nil }
        if components.hour != nil {
            guard let date = calendar.date(from: components) else { return nil }
            self.init(date: date, hasTime: true)
        } else {
            let day = DateComponents(year: components.year, month: components.month, day: components.day)
            guard day.year != nil, day.month != nil, day.day != nil,
                  let date = calendar.date(from: day)
            else { return nil }
            self.init(date: calendar.startOfDay(for: date), hasTime: false)
        }
    }

    init(date: Date, hasTime: Bool) {
        self.date = date
        self.hasTime = hasTime
    }

    /// A timed due before `now`, or a date-only due on a day before today.
    func isOverdue(now: Date, calendar: Calendar) -> Bool {
        hasTime ? date < now : date < calendar.startOfDay(for: now)
    }

    /// "14:05" or "Today" for today, "Tomorrow", an abbreviated weekday for the
    /// rest of the coming week, else an abbreviated month and day; the 24-hour
    /// time follows whenever the due has one and the label is not the time alone.
    func label(now: Date, language: AppLanguage, calendar: Calendar) -> String {
        let today = calendar.startOfDay(for: now)
        let day = calendar.startOfDay(for: date)
        let daysAhead = calendar.dateComponents([.day], from: today, to: day).day ?? 0
        let locale = Locale(identifier: language.rawValue)
        let dayText: String
        switch daysAhead {
        case 0:
            if hasTime { return time(calendar: calendar) }
            return language == .simplifiedChinese ? "今天" : "Today"
        case 1:
            dayText = language == .simplifiedChinese ? "明天" : "Tomorrow"
        case 2...6:
            dayText = date.formatted(
                Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
                    .weekday(.abbreviated)
            )
        default:
            dayText = date.formatted(
                Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
                    .month(.abbreviated)
                    .day()
            )
        }
        return hasTime ? "\(dayText) \(time(calendar: calendar))" : dayText
    }

    private func time(calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }
}

/// An incomplete reminder from the Reminders app, as the card lists it.
struct ReminderItem: Sendable, Equatable, Identifiable {
    /// EventKit's calendar item identifier.
    var id: String
    var title: String
    var due: ReminderDue?
    var created: Date?
    var color: ReminderColor
    var listTitle: String

    /// Reminders with a due date first, earliest first (a date-only due at the
    /// start of its day, so before that day's timed ones); then those without,
    /// newest first and those with no creation date last. Title, then id,
    /// settle the rest, so the order is stable.
    static func ordered(_ items: [ReminderItem]) -> [ReminderItem] {
        items.sorted(by: precedes)
    }

    private static func precedes(_ first: ReminderItem, _ second: ReminderItem) -> Bool {
        switch (first.due, second.due) {
        case let (a?, b?):
            if a.date != b.date { return a.date < b.date }
            if a.hasTime != b.hasTime { return !a.hasTime }
        case (.some, nil):
            return true
        case (nil, .some):
            return false
        case (nil, nil):
            switch (first.created, second.created) {
            case let (a?, b?) where a != b: return a > b
            case (.some, nil): return true
            case (nil, .some): return false
            default: break
            }
        }
        if first.title != second.title { return first.title < second.title }
        return first.id < second.id
    }

    /// A title typed into the single-line field: line breaks and tabs become
    /// spaces, runs of whitespace collapse to one, and the ends are trimmed.
    /// `nil` when nothing is left.
    static func normalizedTitle(_ text: String) -> String? {
        let words = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        guard !words.isEmpty else { return nil }
        return words.joined(separator: " ")
    }
}

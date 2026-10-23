import Foundation

/// An RRULE (RFC 5545 §3.3.10) with the parts calendar feeds use in practice:
/// FREQ (DAILY, WEEKLY, MONTHLY or YEARLY), INTERVAL, COUNT, UNTIL, BYDAY,
/// BYMONTHDAY, BYMONTH, BYSETPOS and WKST. BYWEEKNO, BYYEARDAY, BYHOUR,
/// BYMINUTE and BYSECOND are ignored, so every occurrence keeps DTSTART's
/// wall-clock time.
struct RecurrenceRule: Sendable, Equatable {
    enum Frequency: String, Sendable {
        case daily = "DAILY", weekly = "WEEKLY", monthly = "MONTHLY", yearly = "YEARLY"
    }

    /// A BYDAY entry such as "TU", "2TU" or "-1FR".
    struct WeekdayNumber: Sendable, Equatable {
        /// The nth such weekday in the month or year; negative counts from the
        /// end. Nil means every one.
        var ordinal: Int?
        /// 1 is Sunday through 7 Saturday, as in Foundation.
        var weekday: Int
    }

    /// Stops runaway rules: no more periods than this are visited and no more
    /// starts than this are returned.
    static let expansionLimit = 10_000

    /// A larger INTERVAL makes the rule unsupported: no real feed asks for one,
    /// and the period arithmetic stays far from overflowing with it.
    static let maximumInterval = 10_000

    var frequency: Frequency
    var interval = 1
    var count: Int?
    /// Inclusive.
    var until: Date?
    var byDay: [WeekdayNumber] = []
    var byMonthDay: [Int] = []
    var byMonth: [Int] = []
    var bySetPos: [Int] = []
    /// 1 is Sunday through 7 Saturday; Monday unless WKST says otherwise.
    var weekStart = 2

    /// Nil when FREQ is missing or not one of the supported four, or INTERVAL
    /// exceeds `maximumInterval` (the event then shows once). Malformed
    /// parts are ignored. A date or floating UNTIL is read in `timeZone`, and
    /// a date UNTIL includes that whole day.
    init?(_ value: String, timeZone: TimeZone) {
        var text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.uppercased().hasPrefix("RRULE:") { text = String(text.dropFirst(6)) }
        var parts: [String: String] = [:]
        for part in text.split(separator: ";") {
            guard let equals = part.firstIndex(of: "=") else { continue }
            let name = part[..<equals].trimmingCharacters(in: .whitespaces).uppercased()
            parts[name] = part[part.index(after: equals)...].trimmingCharacters(in: .whitespaces)
        }
        guard let frequency = parts["FREQ"].flatMap({ Frequency(rawValue: $0.uppercased()) }) else { return nil }
        self.frequency = frequency

        func integers(_ name: String, in range: ClosedRange<Int>) -> [Int] {
            (parts[name] ?? "").split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                .filter { range.contains($0) && $0 != 0 }
        }
        if let interval = parts["INTERVAL"].flatMap(Int.init), interval > 0 {
            guard interval <= Self.maximumInterval else { return nil }
            self.interval = interval
        }
        if let count = parts["COUNT"].flatMap(Int.init), count > 0 { self.count = count }
        if let until = parts["UNTIL"] { self.until = Self.untilDate(until, timeZone: timeZone) }
        byDay = (parts["BYDAY"] ?? "").split(separator: ",").compactMap { Self.weekdayNumber(String($0)) }
        byMonthDay = integers("BYMONTHDAY", in: -31...31)
        byMonth = integers("BYMONTH", in: 1...12)
        bySetPos = integers("BYSETPOS", in: -366...366)
        if let weekStart = parts["WKST"].flatMap({ Self.weekday($0) }) { self.weekStart = weekStart }
    }

    /// Every occurrence start up to and including `limit`, in order, beginning
    /// with `start` (DTSTART, which always counts, even when it does not match
    /// the rule). Dates are computed on `calendar`'s time zone wall clock;
    /// only its time zone is used.
    ///
    /// Without COUNT, periods wholly before `notBefore` may be skipped (the
    /// result can then jump from `start` to near `notBefore`), so a daily rule
    /// begun years ago stays cheap. With COUNT every period from DTSTART is
    /// visited, since the count runs from there.
    func starts(from start: Date, calendar: Foundation.Calendar, notBefore: Date? = nil, through limit: Date) -> [Date] {
        guard start <= limit else { return [] }
        let calendar = ICalendarDate.calendar(in: calendar.timeZone)
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: start)
        guard let year = parts.year, let month = parts.month, let day = parts.day else { return [start] }
        let origin = Origin(
            year: year, month: month, day: day,
            dayNumber: CivilDay.number(year: year, month: month, day: day)
        )
        let time = (hour: parts.hour ?? 0, minute: parts.minute ?? 0, second: parts.second ?? 0)

        var result = [start]
        if let until, start >= until { return result }
        if let count, count <= 1 { return result }

        var period = 0
        if count == nil, let notBefore, notBefore > start {
            period = periodsToSkip(before: notBefore, origin: origin, calendar: calendar)
        }
        var visited = 0
        expansion: while visited < Self.expansionLimit {
            for candidate in candidateDays(period: period, origin: origin) where candidate > origin.dayNumber {
                let date = CivilDay.fields(of: candidate)
                guard let occurrence = calendar.date(from: DateComponents(
                    year: date.year, month: date.month, day: date.day,
                    hour: time.hour, minute: time.minute, second: time.second
                )) else { continue }
                if let until, occurrence > until { break expansion }
                if occurrence > limit { break expansion }
                result.append(occurrence)
                if let count, result.count >= count { break expansion }
                if result.count >= Self.expansionLimit { break expansion }
            }
            visited += 1
            period += 1
        }
        return result
    }

    // MARK: - Expansion

    /// DTSTART's date.
    private struct Origin {
        var year: Int
        var month: Int
        var day: Int
        var dayNumber: Int
    }

    /// The days of the `period`th period (counting in steps of INTERVAL from
    /// the one holding DTSTART) that the rule selects, ascending.
    private func candidateDays(period: Int, origin: Origin) -> [Int] {
        switch frequency {
        case .daily:
            let day = origin.dayNumber + period * interval
            let date = CivilDay.fields(of: day)
            guard byMonth.isEmpty || byMonth.contains(date.month),
                  byDay.isEmpty || byDay.contains(where: { $0.weekday == CivilDay.weekday(of: day) }),
                  byMonthDay.isEmpty || monthDays(year: date.year, month: date.month).contains(date.day)
            else { return [] }
            return [day]

        case .weekly:
            let weekStartDay = firstWeekStart(origin) + period * interval * 7
            let weekdays = byDay.isEmpty ? [CivilDay.weekday(of: origin.dayNumber)] : byDay.map(\.weekday)
            return Set(weekdays.map { weekStartDay + ($0 - weekStart + 7) % 7 })
                .filter { byMonth.isEmpty || byMonth.contains(CivilDay.fields(of: $0).month) }
                .sorted()

        case .monthly:
            let monthIndex = origin.year * 12 + origin.month - 1 + period * interval
            let year = monthIndex / 12
            let month = monthIndex % 12 + 1
            guard byMonth.isEmpty || byMonth.contains(month) else { return [] }
            return applyingSetPositions(days(year: year, month: month, defaultDay: origin.day))

        case .yearly:
            let year = origin.year + period * interval
            var days: [Int]
            if byMonth.isEmpty, !byDay.isEmpty, byMonthDay.isEmpty {
                // Ordinals count within the year.
                days = weekdays(
                    from: CivilDay.number(year: year, month: 1, day: 1),
                    through: CivilDay.number(year: year, month: 12, day: 31)
                )
            } else {
                let months = !byMonth.isEmpty ? byMonth.sorted()
                    : byDay.isEmpty && byMonthDay.isEmpty ? [origin.month] : Array(1...12)
                days = months.flatMap { self.days(year: year, month: $0, defaultDay: origin.day) }
            }
            return applyingSetPositions(Array(Set(days)).sorted())
        }
    }

    /// The days of one month that BYMONTHDAY and BYDAY select (both when both
    /// are given; ordinals count within the month), or DTSTART's day of the
    /// month when neither is given and the month has it.
    private func days(year: Int, month: Int, defaultDay: Int) -> [Int] {
        let first = CivilDay.number(year: year, month: month, day: 1)
        let length = CivilDay.daysInMonth(year: year, month: month)
        var selected: Set<Int>?
        if !byMonthDay.isEmpty {
            selected = Set(monthDays(year: year, month: month).map { first + $0 - 1 })
        }
        if !byDay.isEmpty {
            let matching = Set(weekdays(from: first, through: first + length - 1))
            selected = selected.map { $0.intersection(matching) } ?? matching
        }
        guard let selected else { return defaultDay <= length ? [first + defaultDay - 1] : [] }
        return selected.sorted()
    }

    /// BYMONTHDAY resolved to days of the given month; days the month lacks
    /// are skipped, never clamped.
    private func monthDays(year: Int, month: Int) -> [Int] {
        let length = CivilDay.daysInMonth(year: year, month: month)
        return byMonthDay.map { $0 > 0 ? $0 : length + 1 + $0 }.filter { (1...length).contains($0) }
    }

    /// The days from `first` through `last` that BYDAY selects, ordinals
    /// counting within that range.
    private func weekdays(from first: Int, through last: Int) -> [Int] {
        var result: [Int] = []
        for entry in byDay {
            let firstMatch = first + (entry.weekday - CivilDay.weekday(of: first) + 7) % 7
            let matches = Array(stride(from: firstMatch, through: last, by: 7))
            guard let ordinal = entry.ordinal else {
                result += matches
                continue
            }
            let index = ordinal > 0 ? ordinal - 1 : matches.count + ordinal
            if matches.indices.contains(index) { result.append(matches[index]) }
        }
        return Array(Set(result)).sorted()
    }

    /// BYSETPOS applied to one period's sorted days.
    private func applyingSetPositions(_ days: [Int]) -> [Int] {
        guard !bySetPos.isEmpty else { return days }
        let picked = bySetPos.compactMap { position -> Int? in
            let index = position > 0 ? position - 1 : days.count + position
            return days.indices.contains(index) ? days[index] : nil
        }
        return Array(Set(picked)).sorted()
    }

    /// The first day of the week (by WKST) that holds DTSTART.
    private func firstWeekStart(_ origin: Origin) -> Int {
        origin.dayNumber - (CivilDay.weekday(of: origin.dayNumber) - weekStart + 7) % 7
    }

    /// Whole periods that end before `notBefore`, less one for safety.
    private func periodsToSkip(before notBefore: Date, origin: Origin, calendar: Foundation.Calendar) -> Int {
        let parts = calendar.dateComponents([.year, .month, .day], from: notBefore)
        guard let year = parts.year, let month = parts.month, let day = parts.day else { return 0 }
        let elapsed: Int
        switch frequency {
        case .daily:
            elapsed = CivilDay.number(year: year, month: month, day: day) - origin.dayNumber
        case .weekly:
            elapsed = (CivilDay.number(year: year, month: month, day: day) - firstWeekStart(origin)) / 7
        case .monthly:
            elapsed = (year * 12 + month) - (origin.year * 12 + origin.month)
        case .yearly:
            elapsed = year - origin.year
        }
        return max(0, elapsed / interval - 1)
    }

    // MARK: - Parsing

    private static func weekday(_ code: String) -> Int? {
        ["SU": 1, "MO": 2, "TU": 3, "WE": 4, "TH": 5, "FR": 6, "SA": 7][code.uppercased()]
    }

    private static func weekdayNumber(_ text: String) -> WeekdayNumber? {
        let entry = text.trimmingCharacters(in: .whitespaces)
        guard entry.count >= 2, let weekday = weekday(String(entry.suffix(2))) else { return nil }
        let prefix = entry.dropLast(2)
        guard !prefix.isEmpty else { return WeekdayNumber(ordinal: nil, weekday: weekday) }
        guard let ordinal = Int(prefix), ordinal != 0, (-53...53).contains(ordinal) else { return nil }
        return WeekdayNumber(ordinal: ordinal, weekday: weekday)
    }

    private static func untilDate(_ value: String, timeZone: TimeZone) -> Date? {
        guard let fields = ICalendarDate.fields(value, forceDate: false) else { return nil }
        if fields.isUTC { return ICalendarDate.date(fields, in: .gmt) }
        guard fields.isDate else { return ICalendarDate.date(fields, in: timeZone) }
        // A date UNTIL includes that whole day.
        let calendar = ICalendarDate.calendar(in: timeZone)
        guard let dayStart = ICalendarDate.date(fields, in: timeZone),
              let nextDay = calendar.date(byAdding: .day, value: 1, to: dayStart)
        else { return nil }
        return nextDay.addingTimeInterval(-1)
    }
}

/// Proleptic Gregorian dates as day numbers (days since 1970-01-01), free of
/// time zones and DST so recurrence can step through days, weeks and months
/// with plain integers.
enum CivilDay {
    /// After Howard Hinnant's days_from_civil.
    static func number(year: Int, month: Int, day: Int) -> Int {
        let shiftedYear = month <= 2 ? year - 1 : year
        let era = (shiftedYear >= 0 ? shiftedYear : shiftedYear - 399) / 400
        let yearOfEra = shiftedYear - era * 400
        let dayOfYear = (153 * ((month + 9) % 12) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    /// The inverse of `number`, after Howard Hinnant's civil_from_days.
    static func fields(of number: Int) -> (year: Int, month: Int, day: Int) {
        let shifted = number + 719_468
        let era = (shifted >= 0 ? shifted : shifted - 146_096) / 146_097
        let dayOfEra = shifted - era * 146_097
        let yearOfEra = (dayOfEra - dayOfEra / 1460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let shiftedMonth = (5 * dayOfYear + 2) / 153
        let day = dayOfYear - (153 * shiftedMonth + 2) / 5 + 1
        let month = shiftedMonth < 10 ? shiftedMonth + 3 : shiftedMonth - 9
        return (yearOfEra + era * 400 + (month <= 2 ? 1 : 0), month, day)
    }

    /// 1 is Sunday through 7 Saturday, as in Foundation.
    static func weekday(of number: Int) -> Int {
        // 1970-01-01 was a Thursday.
        ((number % 7 + 7 + 4) % 7) + 1
    }

    static func daysInMonth(year: Int, month: Int) -> Int {
        switch month {
        case 2: isLeapYear(year) ? 29 : 28
        case 4, 6, 9, 11: 30
        default: 31
        }
    }

    static func isLeapYear(_ year: Int) -> Bool {
        (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
    }
}

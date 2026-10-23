import Foundation

/// Reads iCalendar (RFC 5545) feeds such as the "secret address in iCal format"
/// that Google Calendar and Outlook.com publish. Only what an agenda needs is
/// kept: the calendar's name and its events with their times and recurrence.
/// Never throws: whatever cannot be read is skipped.
enum ICalendar {
    /// Decodes `data` as UTF-8 (skipping a byte-order mark), falling back to
    /// ISO Latin-1, and parses it. Lines are unfolded before decoding, because
    /// a producer may fold inside a multi-byte UTF-8 sequence (RFC 5545 §3.1).
    static func parse(_ data: Data, defaultTimeZone: TimeZone = .current) -> ICalendarFeed {
        var bytes = data
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { bytes = bytes.dropFirst(3) }
        let unfolded = unfolded(bytes)
        let text = String(data: unfolded, encoding: .utf8) ?? String(data: unfolded, encoding: .isoLatin1) ?? ""
        return parse(text, defaultTimeZone: defaultTimeZone)
    }

    /// `bytes` without the line breaks (CRLF, LF or CR) that are followed by a
    /// space or tab, together with that space or tab.
    private static func unfolded(_ bytes: Data) -> Data {
        let cr = UInt8(ascii: "\r"), lf = UInt8(ascii: "\n")
        let space = UInt8(ascii: " "), tab = UInt8(ascii: "\t")
        var result = Data()
        result.reserveCapacity(bytes.count)
        let input = Array(bytes)
        var index = 0
        while index < input.count {
            let byte = input[index]
            if byte == cr || byte == lf {
                var next = index + 1
                if byte == cr, next < input.count, input[next] == lf { next += 1 }
                if next < input.count, input[next] == space || input[next] == tab {
                    index = next + 1
                    continue
                }
            }
            result.append(byte)
            index += 1
        }
        return result
    }

    /// Parses `text`. Floating times and all-day dates are placed in
    /// `defaultTimeZone`, as are times whose TZID cannot be resolved.
    static func parse(_ text: String, defaultTimeZone: TimeZone = .current) -> ICalendarFeed {
        let body = text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
        let root = ICalendarComponent.tree(from: ICalendarContentLine.lines(in: body))
        var reader = EventReader(
            timeZones: ICalendarTimeZone.Resolver(
                definitions: ICalendarTimeZone.definitions(in: root),
                defaultTimeZone: defaultTimeZone
            )
        )
        let calendarComponent = root.descendants(named: "VCALENDAR").first ?? root
        let name = calendarComponent.property("X-WR-CALNAME")
            .map { ICalendarText.unescape($0.value).trimmingCharacters(in: .whitespacesAndNewlines) }
        let events = root.descendants(named: "VEVENT").enumerated().compactMap { index, component in
            reader.event(from: component, index: index)
        }
        return ICalendarFeed(name: name?.isEmpty == false ? name : nil, events: events)
    }
}

/// A parsed calendar file.
struct ICalendarFeed: Sendable, Equatable {
    /// X-WR-CALNAME, when present and not empty.
    var name: String?
    /// Every readable VEVENT in file order, masters and overrides alike.
    var events: [ICalendarEvent]

    /// The occurrences that overlap `interval`, sorted by start then title.
    /// Recurring events are expanded; EXDATEs, cancellations and RECURRENCE-ID
    /// overrides are applied. A zero-length occurrence counts when its start
    /// lies in [interval.start, interval.end).
    func occurrences(overlapping interval: DateInterval) -> [ICalendarOccurrence] {
        var overridesByUID: [String: [ICalendarEvent]] = [:]
        for event in events where event.recurrenceID != nil {
            overridesByUID[event.uid, default: []].append(event)
        }
        var masterUIDs = Set<String>()
        var result: [ICalendarOccurrence] = []
        for master in events where master.recurrenceID == nil {
            masterUIDs.insert(master.uid)
            // A cancelled master cancels the whole series, overrides included.
            guard !master.isCancelled else { continue }
            result += master.expanded(around: interval, overrides: overridesByUID[master.uid] ?? [])
        }
        // An override whose master the feed does not carry stands on its own.
        for (uid, overrides) in overridesByUID where !masterUIDs.contains(uid) {
            result += overrides.filter { !$0.isCancelled }.map(\.occurrence)
        }
        // A feed can list the same event twice, or two masters can share a UID.
        var seen = Set<ICalendarOccurrence>()
        return result
            .filter { $0.overlaps(interval) && seen.insert($0).inserted }
            .sorted { ($0.start, $0.title) < ($1.start, $1.title) }
    }
}

/// One VEVENT: a single event, the master of a recurring series, or an
/// override of one occurrence (when `recurrenceID` is set).
struct ICalendarEvent: Sendable, Equatable {
    /// UID, or a placeholder unique within the feed when the event has none.
    var uid: String
    /// SUMMARY, possibly empty.
    var summary: String
    /// LOCATION; nil when absent or empty.
    var location: String?
    var start: Date
    /// Exclusive. Never before `start`.
    var end: Date
    /// DTSTART is a date: the event spans whole days from local midnight.
    var isAllDay: Bool
    /// The zone recurrence keeps wall-clock times in: DTSTART's TZID, UTC for
    /// a "Z" time, else the parse's default zone.
    var timeZone: TimeZone
    var recurrence: RecurrenceRule?
    /// RDATE values.
    var recurrenceDates: [Date] = []
    /// EXDATE values.
    var exceptionDates: [Date] = []
    /// RECURRENCE-ID: the start of the generated occurrence this one replaces.
    var recurrenceID: Date?
    /// STATUS:CANCELLED.
    var isCancelled = false

    /// This event alone, unexpanded.
    var occurrence: ICalendarOccurrence {
        ICalendarOccurrence(uid: uid, title: summary, location: location, start: start, end: end, isAllDay: isAllDay)
    }

    /// The occurrences of this master that may touch `interval`, with
    /// `overrides` (events with the same UID and a RECURRENCE-ID) applied.
    /// Not yet filtered to `interval`.
    fileprivate func expanded(around interval: DateInterval, overrides: [ICalendarEvent]) -> [ICalendarOccurrence] {
        let calendar = ICalendarDate.calendar(in: timeZone)
        let span = end.timeIntervalSince(start)
        // All-day occurrences last whole calendar days, which DST can make
        // 23 or 25 hours long.
        let dayLength = isAllDay ? calendar.dateComponents([.day], from: start, to: end).day ?? 1 : 0

        var starts = [start]
        if recurrence != nil || !recurrenceDates.isEmpty {
            if let recurrence {
                // Generate from far enough back that an occurrence still running
                // when the interval starts is included.
                let notBefore = interval.start.addingTimeInterval(-span - 2 * 86_400)
                starts = recurrence.starts(from: start, calendar: calendar, notBefore: notBefore, through: interval.end)
            }
            starts = Array(Set(starts + recurrenceDates)).sorted()
        }

        func key(_ date: Date) -> Date { isAllDay ? calendar.startOfDay(for: date) : date }
        let replaced = Set(exceptionDates.map(key) + overrides.compactMap { $0.recurrenceID.map(key) })
        var result = starts.filter { !replaced.contains(key($0)) }.map { occurrenceStart in
            var occurrence = self.occurrence
            occurrence.start = occurrenceStart
            occurrence.end = isAllDay
                ? calendar.date(byAdding: .day, value: dayLength, to: occurrenceStart) ?? occurrenceStart
                : occurrenceStart.addingTimeInterval(span)
            return occurrence
        }
        result += overrides.filter { !$0.isCancelled }.map(\.occurrence)
        return result
    }
}

/// One concrete occurrence of an event.
struct ICalendarOccurrence: Sendable, Equatable, Hashable {
    var uid: String
    var title: String
    var location: String?
    var start: Date
    /// Exclusive.
    var end: Date
    var isAllDay: Bool

    fileprivate func overlaps(_ interval: DateInterval) -> Bool {
        if end <= start { return start >= interval.start && start < interval.end }
        return start < interval.end && end > interval.start
    }
}

// MARK: - Reading events

/// Turns VEVENT components into events, resolving their time zones.
private struct EventReader {
    var timeZones: ICalendarTimeZone.Resolver

    /// A date or date-time property's value.
    struct DateTime {
        var date: Date
        var isDate: Bool
        var timeZone: TimeZone
    }

    mutating func event(from component: ICalendarComponent, index: Int) -> ICalendarEvent? {
        guard let startLine = component.property("DTSTART"),
              let start = dateTime(startLine.value, parameters: startLine.parameters)
        else { return nil }
        let calendar = ICalendarDate.calendar(in: start.timeZone)

        var end: Date
        if let line = component.property("DTEND"), let value = dateTime(line.value, parameters: line.parameters) {
            end = value.date
        } else if let line = component.property("DURATION"), let duration = ICalendarDuration(line.value) {
            end = duration.added(to: start.date, calendar: calendar)
        } else if start.isDate {
            end = calendar.date(byAdding: .day, value: 1, to: start.date) ?? start.date
        } else {
            end = start.date
        }
        end = max(end, start.date)

        let uid = component.property("UID")?.value.trimmingCharacters(in: .whitespaces) ?? ""
        let location = component.property("LOCATION").map { ICalendarText.unescape($0.value) }
        var event = ICalendarEvent(
            uid: uid.isEmpty ? "urn:notch:event:\(index)" : uid,
            summary: component.property("SUMMARY").map { ICalendarText.unescape($0.value) } ?? "",
            location: location?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? location : nil,
            start: start.date,
            end: end,
            isAllDay: start.isDate,
            timeZone: start.timeZone
        )
        event.recurrence = component.property("RRULE").flatMap { RecurrenceRule($0.value, timeZone: start.timeZone) }
        for line in component.properties("RDATE") where line.parameters["VALUE"]?.uppercased() != "PERIOD" {
            event.recurrenceDates += dateList(line)
        }
        for line in component.properties("EXDATE") {
            event.exceptionDates += dateList(line)
        }
        if let line = component.property("RECURRENCE-ID") {
            event.recurrenceID = dateTime(line.value, parameters: line.parameters)?.date
        }
        event.isCancelled = component.property("STATUS")?.value
            .trimmingCharacters(in: .whitespaces).uppercased() == "CANCELLED"
        return event
    }

    /// A DATE (all-day, at local midnight of the default zone), a UTC
    /// date-time, a date-time in its TZID's zone, or a floating date-time in
    /// the default zone.
    mutating func dateTime(_ value: String, parameters: [String: String]) -> DateTime? {
        let forceDate = parameters["VALUE"]?.uppercased() == "DATE"
        guard let fields = ICalendarDate.fields(value.trimmingCharacters(in: .whitespaces), forceDate: forceDate)
        else { return nil }
        let zone: TimeZone
        if fields.isDate {
            zone = timeZones.defaultTimeZone
        } else if fields.isUTC {
            zone = .gmt
        } else if let tzid = parameters["TZID"] {
            zone = timeZones.resolve(tzid)
        } else {
            zone = timeZones.defaultTimeZone
        }
        guard let date = ICalendarDate.date(fields, in: zone) else { return nil }
        return DateTime(date: date, isDate: fields.isDate, timeZone: zone)
    }

    /// The comma-separated values of an RDATE or EXDATE line.
    mutating func dateList(_ line: ICalendarContentLine) -> [Date] {
        line.value.split(separator: ",").compactMap { dateTime(String($0), parameters: line.parameters)?.date }
    }
}

// MARK: - Values

/// DATE and DATE-TIME values (RFC 5545 §3.3.4, §3.3.5).
enum ICalendarDate {
    /// The parts of "yyyyMMdd" or "yyyyMMdd'T'HHmmss" with an optional "Z";
    /// seconds may be missing.
    struct Fields: Equatable {
        var year: Int
        var month: Int
        var day: Int
        var hour = 0
        var minute = 0
        var second = 0
        var isDate: Bool
        var isUTC = false
    }

    /// Nil unless `value` is a valid date or date-time. With `forceDate`
    /// (VALUE=DATE) only the first eight digits count.
    static func fields(_ value: String, forceDate: Bool) -> Fields? {
        let bytes = Array(value.utf8)
        guard bytes.count >= 8, let year = number(bytes, 0, 4), let month = number(bytes, 4, 2),
              let day = number(bytes, 6, 2),
              (1...12).contains(month), (1...CivilDay.daysInMonth(year: year, month: month)).contains(day)
        else { return nil }
        var fields = Fields(year: year, month: month, day: day, isDate: true)
        if forceDate || bytes.count == 8 { return fields }

        guard bytes[8] == UInt8(ascii: "T") || bytes[8] == UInt8(ascii: "t") else { return nil }
        var timeEnd = bytes.count
        if let last = bytes.last, last == UInt8(ascii: "Z") || last == UInt8(ascii: "z") {
            fields.isUTC = true
            timeEnd -= 1
        }
        let timeLength = timeEnd - 9
        guard timeLength == 6 || timeLength == 4,
              let hour = number(bytes, 9, 2), let minute = number(bytes, 11, 2),
              (0...23).contains(hour), (0...59).contains(minute)
        else { return nil }
        let second = timeLength == 6 ? number(bytes, 13, 2) : 0
        guard let second, (0...60).contains(second) else { return nil }
        fields.hour = hour
        fields.minute = minute
        // A leap second is read as the second before it.
        fields.second = min(second, 59)
        fields.isDate = false
        return fields
    }

    /// The instant `fields` names as wall-clock time in `zone`.
    static func date(_ fields: Fields, in zone: TimeZone) -> Date? {
        calendar(in: zone).date(from: DateComponents(
            year: fields.year, month: fields.month, day: fields.day,
            hour: fields.hour, minute: fields.minute, second: fields.second
        ))
    }

    /// A Gregorian calendar in `zone`.
    static func calendar(in zone: TimeZone) -> Foundation.Calendar {
        var calendar = Foundation.Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar
    }

    private static func number(_ bytes: [UInt8], _ offset: Int, _ length: Int) -> Int? {
        guard offset + length <= bytes.count else { return nil }
        var value = 0
        for byte in bytes[offset..<(offset + length)] {
            guard (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte) else { return nil }
            value = value * 10 + Int(byte - UInt8(ascii: "0"))
        }
        return value
    }
}

/// DURATION values (RFC 5545 §3.3.6): weeks and days count as calendar days,
/// hours, minutes and seconds as elapsed time.
struct ICalendarDuration: Equatable {
    var days = 0
    var seconds = 0

    /// The largest value of one part (weeks, days, hours, minutes or seconds);
    /// a bigger one, or any overflow of the sums, makes the value unreadable.
    private static let maximumPart = 1_000_000

    /// Nil when `value` is not a duration or a part is absurdly large. A
    /// negative duration reads as zero.
    init?(_ value: String) {
        var text = Substring(value.trimmingCharacters(in: .whitespaces).uppercased())
        var isNegative = false
        if let sign = text.first, sign == "+" || sign == "-" {
            isNegative = sign == "-"
            text = text.dropFirst()
        }
        guard text.first == "P" else { return nil }
        var inTime = false
        var digits = ""
        var hasPart = false
        for character in text.dropFirst() {
            if character.isASCII, character.isNumber {
                digits.append(character)
                continue
            }
            if character == "T", digits.isEmpty {
                inTime = true
                continue
            }
            guard let amount = Int(digits), amount <= Self.maximumPart else { return nil }
            digits = ""
            hasPart = true
            let unit: Int
            switch (character, inTime) {
            case ("W", false): unit = 7
            case ("D", false): unit = 1
            case ("H", true): unit = 3600
            case ("M", true): unit = 60
            case ("S", true): unit = 1
            default: return nil
            }
            // Parts are capped, but a long run of them could still add up past Int.
            let (scaled, scaleOverflow) = amount.multipliedReportingOverflow(by: unit)
            guard !scaleOverflow else { return nil }
            if inTime {
                let (sum, overflow) = seconds.addingReportingOverflow(scaled)
                guard !overflow else { return nil }
                seconds = sum
            } else {
                let (sum, overflow) = days.addingReportingOverflow(scaled)
                guard !overflow else { return nil }
                days = sum
            }
        }
        guard hasPart, digits.isEmpty else { return nil }
        if isNegative {
            days = 0
            seconds = 0
        }
    }

    /// `date` moved by this duration, days on `calendar`'s wall clock.
    func added(to date: Date, calendar: Foundation.Calendar) -> Date {
        let moved = days == 0 ? date : calendar.date(byAdding: .day, value: days, to: date) ?? date
        return moved.addingTimeInterval(TimeInterval(seconds))
    }
}

/// TEXT values (RFC 5545 §3.3.11).
enum ICalendarText {
    /// Undoes the escapes: "\n" and "\N" become a newline; "\,", "\;" and "\\"
    /// the character itself. A backslash before anything else is dropped.
    static func unescape(_ text: String) -> String {
        guard text.contains("\\") else { return text }
        var result = ""
        var isEscaped = false
        for character in text {
            if isEscaped {
                result.append(character == "n" || character == "N" ? "\n" : character)
                isEscaped = false
            } else if character == "\\" {
                isEscaped = true
            } else {
                result.append(character)
            }
        }
        if isEscaped { result.append("\\") }
        return result
    }
}

// MARK: - Lexing

/// One unfolded content line (RFC 5545 §3.1): NAME;PARAM=value:VALUE.
struct ICalendarContentLine: Sendable, Equatable {
    /// Uppercased.
    var name: String
    /// Parameter names uppercased; values with their double quotes removed.
    var parameters: [String: String]
    /// Raw, still escaped.
    var value: String

    /// Unfolds `text` (CRLF, LF or CR line ends; a line starting with a space
    /// or tab continues the previous one, minus that character) and reads each
    /// line. Lines without a name and a colon are skipped.
    static func lines(in text: String) -> [ICalendarContentLine] {
        var unfolded: [String] = []
        for line in text.split(whereSeparator: { $0 == "\n" || $0 == "\r\n" || $0 == "\r" }) {
            if let first = line.first, first == " " || first == "\t", !unfolded.isEmpty {
                unfolded[unfolded.count - 1] += line.dropFirst()
            } else {
                unfolded.append(String(line))
            }
        }
        return unfolded.compactMap(ICalendarContentLine.init)
    }

    init(name: String, parameters: [String: String] = [:], value: String) {
        self.name = name
        self.parameters = parameters
        self.value = value
    }

    /// Splits at the first colon outside double quotes, so a quoted parameter
    /// value may hold colons and semicolons.
    init?(_ line: String) {
        var colon: String.Index?
        var inQuotes = false
        for index in line.utf8.indices {
            switch line.utf8[index] {
            case UInt8(ascii: "\""): inQuotes.toggle()
            case UInt8(ascii: ":") where !inQuotes: colon = index
            default: break
            }
            if colon != nil { break }
        }
        guard let colon else { return nil }

        var parts: [String] = []
        var current = ""
        inQuotes = false
        for character in line[..<colon] {
            if character == "\"" { inQuotes.toggle() }
            if character == ";", !inQuotes {
                parts.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        parts.append(current)

        let name = parts[0].trimmingCharacters(in: .whitespaces).uppercased()
        guard !name.isEmpty else { return nil }
        var parameters: [String: String] = [:]
        for part in parts.dropFirst() {
            guard let equals = part.firstIndex(of: "=") else { continue }
            let key = part[..<equals].trimmingCharacters(in: .whitespaces).uppercased()
            parameters[key] = part[part.index(after: equals)...].replacingOccurrences(of: "\"", with: "")
        }
        self.init(name: name, parameters: parameters, value: String(line[line.utf8.index(after: colon)...]))
    }
}

/// A BEGIN…END block with its own properties and nested blocks, so a VALARM's
/// SUMMARY never reads as its VEVENT's.
struct ICalendarComponent: Sendable {
    /// Uppercased; empty for the root that holds everything.
    var name: String
    var properties: [ICalendarContentLine] = []
    var children: [ICalendarComponent] = []

    /// Nests `lines` by BEGIN and END. An END closes the innermost open block
    /// of its name (and any left open inside it); a stray END is ignored and
    /// blocks still open at the end of the file are closed there.
    static func tree(from lines: [ICalendarContentLine]) -> ICalendarComponent {
        var stack = [ICalendarComponent(name: "")]
        func close(downTo depth: Int) {
            while stack.count > depth {
                let component = stack.removeLast()
                stack[stack.count - 1].children.append(component)
            }
        }
        for line in lines {
            switch line.name {
            case "BEGIN":
                stack.append(ICalendarComponent(name: line.value.trimmingCharacters(in: .whitespaces).uppercased()))
            case "END":
                let name = line.value.trimmingCharacters(in: .whitespaces).uppercased()
                if let depth = stack.lastIndex(where: { $0.name == name }), depth > 0 {
                    close(downTo: depth)
                }
            default:
                stack[stack.count - 1].properties.append(line)
            }
        }
        close(downTo: 1)
        return stack[0]
    }

    /// The first property called `name` (uppercase).
    func property(_ name: String) -> ICalendarContentLine? {
        properties.first { $0.name == name }
    }

    func properties(_ name: String) -> [ICalendarContentLine] {
        properties.filter { $0.name == name }
    }

    /// Every component called `name` (uppercase) below this one, depth first.
    func descendants(named name: String) -> [ICalendarComponent] {
        children.flatMap { child in
            (child.name == name ? [child] : []) + child.descendants(named: name)
        }
    }
}

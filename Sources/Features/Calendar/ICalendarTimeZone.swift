import Foundation

/// Resolves the TZID parameters calendar producers write to Foundation zones.
/// Google writes IANA names, Outlook writes Windows names ("China Standard
/// Time"), and older producers write path-style names
/// ("/citadel.org/20070129_1/Europe/Berlin") or zones of their own that only
/// the file's VTIMEZONE describes.
enum ICalendarTimeZone {
    /// What a VTIMEZONE block says about its zone.
    struct Definition: Sendable, Equatable {
        /// X-LIC-LOCATION, an IANA name some producers add.
        var location: String?
        /// TZOFFSETTO of the newest STANDARD observance (or of any observance
        /// when there is no STANDARD), in seconds east of UTC.
        var standardOffset: Int?
        /// TZOFFSETTO of the newest DAYLIGHT observance, only when the block also
        /// has a STANDARD one; nil for a zone without DST.
        var daylightOffset: Int?
    }

    /// Resolves TZIDs within one file, remembering each answer.
    struct Resolver {
        var definitions: [String: Definition]
        var defaultTimeZone: TimeZone
        private var cache: [String: TimeZone] = [:]

        init(definitions: [String: Definition] = [:], defaultTimeZone: TimeZone) {
            self.definitions = definitions
            self.defaultTimeZone = defaultTimeZone
        }

        mutating func resolve(_ tzid: String) -> TimeZone {
            if let zone = cache[tzid] { return zone }
            let zone = ICalendarTimeZone.resolve(tzid, definitions: definitions, defaultTimeZone: defaultTimeZone)
            cache[tzid] = zone
            return zone
        }
    }

    /// IDs that mean UTC however a producer spells them.
    private static let utcNames: Set<String> = [
        "UTC", "GMT", "Z", "UT", "UCT", "ZULU", "ETC/UTC", "ETC/GMT", "ETC/UCT", "ETC/ZULU", "ETC/UNIVERSAL",
        "UNIVERSAL", "GREENWICH", "GMT+0", "GMT-0", "UTC+0", "UTC-0", "COORDINATED UNIVERSAL TIME",
    ]

    /// The zone `tzid` names, trying in order: UTC spellings; the ID as an
    /// identifier; for a path-style ID, its last two then three components;
    /// the Windows table; the file's VTIMEZONE (its X-LIC-LOCATION; else
    /// `defaultTimeZone` when its January and July offsets are exactly the
    /// offsets the VTIMEZONE's observances name, which keeps DST for producers
    /// such as Outlook that invent zone names; else a fixed offset from its
    /// standard observance, which ignores DST); and finally `defaultTimeZone`.
    /// `now` picks the year whose offsets are compared.
    static func resolve(
        _ tzid: String,
        definitions: [String: Definition] = [:],
        defaultTimeZone: TimeZone,
        now: Date = Date()
    ) -> TimeZone {
        let id = tzid.trimmingCharacters(in: CharacterSet.whitespaces.union(["\""]))
        guard !id.isEmpty else { return defaultTimeZone }
        if utcNames.contains(id.uppercased()) { return .gmt }
        if let zone = TimeZone(identifier: id) { return zone }
        if id.contains("/") {
            let components = id.split(separator: "/")
            for count in [2, 3] where components.count >= count {
                if let zone = TimeZone(identifier: components.suffix(count).joined(separator: "/")) {
                    return zone
                }
            }
        }
        if let iana = WindowsTimeZones.ianaIdentifier(for: id), let zone = TimeZone(identifier: iana) {
            return zone
        }
        if let definition = definitions[id] {
            if let location = definition.location, let zone = TimeZone(identifier: location) {
                return zone
            }
            if let standard = definition.standardOffset,
               Set([standard, definition.daylightOffset ?? standard]) == offsets(of: defaultTimeZone, inYearOf: now) {
                return defaultTimeZone
            }
            if let offset = definition.standardOffset, let zone = TimeZone(secondsFromGMT: offset) {
                return zone
            }
        }
        return defaultTimeZone
    }

    /// The VTIMEZONE blocks anywhere under `root`, by TZID.
    static func definitions(in root: ICalendarComponent) -> [String: Definition] {
        var result: [String: Definition] = [:]
        for component in root.descendants(named: "VTIMEZONE") {
            guard let tzid = component.property("TZID")?.value
                .trimmingCharacters(in: CharacterSet.whitespaces.union(["\""])),
                !tzid.isEmpty
            else { continue }
            let location = component.property("X-LIC-LOCATION")?.value.trimmingCharacters(in: .whitespaces)
            let standard = component.children.filter { $0.name == "STANDARD" }
            let observances = standard.isEmpty ? component.children.filter { $0.name == "DAYLIGHT" } : standard
            // DTSTART values of one form sort as text; the newest rule is the
            // one in force now.
            func newestOffset(of observances: [ICalendarComponent]) -> Int? {
                observances.max {
                    ($0.property("DTSTART")?.value ?? "") < ($1.property("DTSTART")?.value ?? "")
                }?.property("TZOFFSETTO").flatMap { utcOffset($0.value) }
            }
            let daylight = component.children.filter { $0.name == "DAYLIGHT" }
            result[tzid] = Definition(
                location: location?.isEmpty == false ? location : nil,
                standardOffset: newestOffset(of: observances),
                daylightOffset: standard.isEmpty ? nil : newestOffset(of: daylight)
            )
        }
        return result
    }

    /// The UTC offsets `zone` has on 1 January and 1 July of `date`'s year, so a
    /// zone with DST in either hemisphere yields its standard and daylight pair.
    private static func offsets(of zone: TimeZone, inYearOf date: Date) -> Set<Int> {
        let calendar = ICalendarDate.calendar(in: .gmt)
        let year = calendar.component(.year, from: date)
        return Set([1, 7].compactMap { month in
            calendar.date(from: DateComponents(year: year, month: month, day: 1, hour: 12))
                .map { zone.secondsFromGMT(for: $0) }
        })
    }

    /// Seconds east of UTC for a UTC-OFFSET value (RFC 5545 §3.3.14):
    /// "+0800", "-0500", "+053000".
    static func utcOffset(_ value: String) -> Int? {
        let text = value.trimmingCharacters(in: .whitespaces)
        guard let sign = text.first, sign == "+" || sign == "-" else { return nil }
        let digits = text.dropFirst()
        guard digits.count == 4 || digits.count == 6, digits.allSatisfy({ $0.isASCII && $0.isNumber }) else {
            return nil
        }
        let numbers = Array(digits).map { Int(String($0))! }
        let hours = numbers[0] * 10 + numbers[1]
        let minutes = numbers[2] * 10 + numbers[3]
        let seconds = digits.count == 6 ? numbers[4] * 10 + numbers[5] : 0
        let total = hours * 3600 + minutes * 60 + seconds
        return sign == "-" ? -total : total
    }
}

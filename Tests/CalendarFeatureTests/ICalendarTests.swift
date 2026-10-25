import Foundation
import Testing
@testable import CalendarFeature

private let berlin = TimeZone(identifier: "Europe/Berlin")!

/// The instant of a wall-clock time in `zone`, computed independently of the parser.
func instant(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0,
             in zone: TimeZone) -> Date {
    var calendar = Foundation.Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    return calendar.date(from: DateComponents(
        year: year, month: month, day: day, hour: hour, minute: minute, second: second))!
}

/// A VCALENDAR around `lines`, joined with CRLF.
func feedText(_ lines: [String], separator: String = "\r\n") -> String {
    (["BEGIN:VCALENDAR", "VERSION:2.0"] + lines + ["END:VCALENDAR"]).joined(separator: separator) + separator
}

/// A VEVENT with `lines` inside.
func vevent(_ lines: String...) -> [String] {
    ["BEGIN:VEVENT"] + lines + ["END:VEVENT"]
}

private func onlyEvent(_ lines: [String], defaultTimeZone: TimeZone = berlin) throws -> ICalendarEvent {
    let feed = ICalendar.parse(feedText(lines), defaultTimeZone: defaultTimeZone)
    #expect(feed.events.count == 1)
    return try #require(feed.events.first)
}

struct ICalendarLexingTests {
    @Test func foldedLinesUnfoldWithCRLF() throws {
        // RFC 5545 §3.1: each fold removes the CRLF and the one space after it.
        let event = try onlyEvent(vevent(
            "UID:1",
            "DTSTART:20261022T090000Z",
            "SUMMARY:This is a lo",
            " ng description",
            "  that exists on a long line."
        ))
        #expect(event.summary == "This is a long description that exists on a long line.")
    }

    @Test func foldedLinesUnfoldWithLFAndTab() {
        let text = feedText(vevent("UID:1", "DTSTART:20261022T090000Z", "SUMMARY:Team", "\tsync"), separator: "\n")
        #expect(ICalendar.parse(text, defaultTimeZone: berlin).events.first?.summary == "Teamsync")
    }

    @Test func bareCarriageReturnsEndLines() {
        let text = feedText(vevent("UID:1", "DTSTART:20261022T090000Z", "SUMMARY:Plan"), separator: "\r")
        #expect(ICalendar.parse(text, defaultTimeZone: berlin).events.first?.summary == "Plan")
    }

    @Test func textEscapesAreUndone() throws {
        // RFC 5545 §3.3.11: \n or \N is a newline; \, \; and \\ stand for themselves.
        let event = try onlyEvent(vevent(
            "UID:1",
            "DTSTART:20261022T090000Z",
            #"SUMMARY:Meeting\, room 4\; bring \\laptop\nand notes\Nend"#,
            #"LOCATION:Building 7\, floor 2"#
        ))
        #expect(event.summary == "Meeting, room 4; bring \\laptop\nand notes\nend")
        #expect(event.location == "Building 7, floor 2")
    }

    @Test func namesAreCaseInsensitive() throws {
        let event = try onlyEvent([
            "begin:vevent",
            "uid:1",
            "dtstart;tzid=America/New_York:20261022T090000",
            "summary:Lower",
            "end:vevent",
        ])
        #expect(event.summary == "Lower")
        #expect(event.start == instant(2026, 10, 22, 13, in: .gmt))
    }

    @Test func alarmPropertiesStayInTheAlarm() throws {
        let event = try onlyEvent([
            "BEGIN:VEVENT",
            "UID:1",
            "SUMMARY:Dentist",
            "DTSTART:20261022T090000Z",
            "BEGIN:VALARM",
            "ACTION:DISPLAY",
            "SUMMARY:Reminder",
            "DESCRIPTION:Reminder",
            "TRIGGER:-PT15M",
            "END:VALARM",
            "LOCATION:Clinic",
            "END:VEVENT",
        ])
        #expect(event.summary == "Dentist")
        #expect(event.location == "Clinic")
    }

    @Test func calendarNameIsRead() {
        let feed = ICalendar.parse(feedText([#"X-WR-CALNAME:Work\, shared"#]), defaultTimeZone: berlin)
        #expect(feed.name == "Work, shared")
        #expect(feed.events.isEmpty)
        #expect(ICalendar.parse(feedText([]), defaultTimeZone: berlin).name == nil)
    }

    @Test func emptyLocationIsNil() throws {
        let event = try onlyEvent(vevent("UID:1", "DTSTART:20261022T090000Z", "LOCATION:"))
        #expect(event.location == nil)
        #expect(event.summary == "")
    }

    @Test func malformedEventsAreSkipped() {
        let text = feedText(
            ["this line has no colon"]
                + vevent("UID:no-start", "SUMMARY:No start")
                + vevent("UID:dashes", "DTSTART:2026-10-22", "SUMMARY:Dashes")
                + vevent("UID:month", "DTSTART:20261340T090000Z", "SUMMARY:Month 13")
                + vevent("UID:feb30", "DTSTART;VALUE=DATE:20260230", "SUMMARY:February 30")
                + vevent("UID:good", "DTSTART:20261022T090000Z", "SUMMARY:Good", "BOGUS;X=1:ignored")
                + ["BEGIN:X-UNKNOWN", "SUMMARY:Unknown", "END:X-UNKNOWN", "END:VTODO"]
        )
        let feed = ICalendar.parse(text, defaultTimeZone: berlin)
        #expect(feed.events.map(\.uid) == ["good"])
        #expect(feed.events.first?.summary == "Good")
    }

    @Test func dataDecodesUTF8WithBOMAndLatin1() {
        let utf8 = Data([0xEF, 0xBB, 0xBF]) + Data(feedText(["X-WR-CALNAME:日程"]).utf8)
        #expect(ICalendar.parse(utf8, defaultTimeZone: berlin).name == "日程")
        let latin1 = feedText(["X-WR-CALNAME:Café"]).data(using: .isoLatin1)!
        #expect(ICalendar.parse(latin1, defaultTimeZone: berlin).name == "Café")
    }

    @Test func foldsInsideMultiByteCharactersStillDecodeAsUTF8() throws {
        // "程" is E7 A8 8B; the producer folds after its first byte, and in SUMMARY after its second.
        var bytes = Data("BEGIN:VCALENDAR\r\nX-WR-CALNAME:日".utf8)
        bytes += Data([0xE7, 0x0D, 0x0A, 0x20, 0xA8, 0x8B])
        bytes += Data("\r\nBEGIN:VEVENT\r\nUID:1\r\nDTSTART:20261022T090000Z\r\nSUMMARY:日".utf8)
        bytes += Data([0xE7, 0xA8, 0x0A, 0x09, 0x8B])
        bytes += Data("\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n".utf8)
        let feed = ICalendar.parse(bytes, defaultTimeZone: berlin)
        #expect(feed.name == "日程")
        #expect(feed.events.first?.summary == "日程")
    }

    @Test func missingUIDsGetDistinctPlaceholders() {
        let text = feedText(
            vevent("DTSTART:20261022T090000Z") + vevent("DTSTART:20261023T090000Z")
        )
        let uids = ICalendar.parse(text, defaultTimeZone: berlin).events.map(\.uid)
        #expect(uids.count == 2)
        #expect(Set(uids).count == 2)
    }
}

/// Hostile nesting must neither overflow the stack nor hide what follows it.
struct ICalendarNestingTests {
    @Test func deepUnclosedNestingParsesWithoutCrashing() {
        let text = feedText(Array(repeating: "BEGIN:X", count: 100_000))
        #expect(ICalendar.parse(text, defaultTimeZone: berlin).events.isEmpty)
    }

    @Test func eventAfterDeepClosedNestingIsStillRead() {
        let text = feedText(
            Array(repeating: "BEGIN:X", count: 50_000) + Array(repeating: "END:X", count: 50_000)
                + vevent("UID:after", "DTSTART:20261022T090000Z", "SUMMARY:After")
        )
        let feed = ICalendar.parse(text, defaultTimeZone: berlin)
        #expect(feed.events.map(\.uid) == ["after"])
        #expect(feed.events.first?.summary == "After")
    }
}

struct ICalendarDateTests {
    @Test func utcTime() throws {
        let event = try onlyEvent(vevent("UID:1", "DTSTART:20261022T090000Z", "DTEND:20261022T100000Z"))
        #expect(event.start == instant(2026, 10, 22, 9, in: .gmt))
        #expect(event.end == instant(2026, 10, 22, 10, in: .gmt))
        #expect(!event.isAllDay)
        #expect(event.timeZone.secondsFromGMT() == 0)
    }

    @Test func ianaTimeZone() throws {
        let event = try onlyEvent(vevent("UID:1", "DTSTART;TZID=America/New_York:20261022T090000"))
        // New York is on EDT (UTC-4) on 22 October 2026.
        #expect(event.start == instant(2026, 10, 22, 13, in: .gmt))
        #expect(event.timeZone.identifier == "America/New_York")
    }

    @Test func quotedWindowsTimeZone() throws {
        let event = try onlyEvent(vevent("UID:1", #"DTSTART;TZID="China Standard Time":20261022T090000"#))
        // China Standard Time is UTC+8 with no DST.
        #expect(event.start == instant(2026, 10, 22, 1, in: .gmt))
        #expect(event.timeZone.identifier == "Asia/Shanghai")
    }

    @Test func pathStyleTimeZone() throws {
        let event = try onlyEvent(vevent("UID:1", "DTSTART;TZID=/citadel.org/20070129_1/Europe/Berlin:20261022T090000"))
        // Berlin is on CEST (UTC+2) until 25 October 2026.
        #expect(event.start == instant(2026, 10, 22, 7, in: .gmt))
        #expect(event.timeZone.identifier == "Europe/Berlin")
    }

    @Test func utcSpellingsResolveToUTC() throws {
        for tzid in ["UTC", "GMT", "Etc/UTC", "Z"] {
            let event = try onlyEvent(
                vevent("UID:1", "DTSTART;TZID=\(tzid):20261022T090000"),
                defaultTimeZone: TimeZone(identifier: "Asia/Tokyo")!
            )
            #expect(event.start == instant(2026, 10, 22, 9, in: .gmt), "TZID \(tzid)")
        }
    }

    @Test func vtimezoneLocationFallback() throws {
        let event = try onlyEvent([
            "BEGIN:VTIMEZONE",
            "TZID:Tokyo Office",
            "X-LIC-LOCATION:Asia/Tokyo",
            "BEGIN:STANDARD",
            "DTSTART:19700101T000000",
            "TZOFFSETFROM:+0900",
            "TZOFFSETTO:+0900",
            "END:STANDARD",
            "END:VTIMEZONE",
        ] + vevent("UID:1", "DTSTART;TZID=Tokyo Office:20261022T090000"))
        #expect(event.start == instant(2026, 10, 22, 0, in: .gmt))
        #expect(event.timeZone.identifier == "Asia/Tokyo")
    }

    @Test func vtimezoneStandardOffsetFallback() throws {
        // A zone only the file knows: its STANDARD offset is used and DST ignored.
        let event = try onlyEvent(vevent("UID:1", "DTSTART;TZID=Imaginary Zone:20261022T090000") + [
            "BEGIN:VTIMEZONE",
            "TZID:Imaginary Zone",
            "BEGIN:DAYLIGHT",
            "DTSTART:19700329T020000",
            "TZOFFSETFROM:+0530",
            "TZOFFSETTO:+0630",
            "END:DAYLIGHT",
            "BEGIN:STANDARD",
            "DTSTART:19701025T030000",
            "TZOFFSETFROM:+0630",
            "TZOFFSETTO:+0530",
            "END:STANDARD",
            "END:VTIMEZONE",
        ])
        #expect(event.timeZone.secondsFromGMT() == 19_800)
        #expect(event.start == instant(2026, 10, 22, 3, 30, in: .gmt))
    }

    @Test func vtimezoneWithDaylightMatchingTheDefaultZoneKeepsDST() throws {
        // A producer-invented zone name ("Customized Time Zone") with +0100 / +0200.
        let zone = [
            "BEGIN:VTIMEZONE",
            "TZID:Customized Time Zone",
            "BEGIN:DAYLIGHT",
            "DTSTART:19700329T020000",
            "TZOFFSETFROM:+0100",
            "TZOFFSETTO:+0200",
            "END:DAYLIGHT",
            "BEGIN:STANDARD",
            "DTSTART:19701025T030000",
            "TZOFFSETFROM:+0200",
            "TZOFFSETTO:+0100",
            "END:STANDARD",
            "END:VTIMEZONE",
        ]
        let july = vevent("UID:1", "DTSTART;TZID=Customized Time Zone:20260715T090000")
        let berlinEvent = try onlyEvent(zone + july, defaultTimeZone: berlin)
        #expect(berlinEvent.start == instant(2026, 7, 15, 7, in: .gmt))
        #expect(berlinEvent.timeZone.identifier == "Europe/Berlin")
        let winter = try onlyEvent(
            zone + vevent("UID:1", "DTSTART;TZID=Customized Time Zone:20261215T090000"), defaultTimeZone: berlin)
        #expect(winter.start == instant(2026, 12, 15, 8, in: .gmt))

        let shanghai = TimeZone(identifier: "Asia/Shanghai")!
        let fixed = try onlyEvent(zone + july, defaultTimeZone: shanghai)
        #expect(fixed.timeZone.secondsFromGMT() == 3600)
        #expect(fixed.start == instant(2026, 7, 15, 8, in: .gmt))
    }

    @Test func vtimezoneWithOnlyStandardMatchesAZoneWithoutDST() throws {
        let zone = [
            "BEGIN:VTIMEZONE",
            "TZID:Customized Time Zone",
            "BEGIN:STANDARD",
            "DTSTART:19700101T000000",
            "TZOFFSETFROM:+0800",
            "TZOFFSETTO:+0800",
            "END:STANDARD",
            "END:VTIMEZONE",
        ]
        let shanghai = TimeZone(identifier: "Asia/Shanghai")!
        let event = try onlyEvent(
            zone + vevent("UID:1", "DTSTART;TZID=Customized Time Zone:20260715T090000"), defaultTimeZone: shanghai)
        #expect(event.timeZone.identifier == "Asia/Shanghai")
        let other = try onlyEvent(
            zone + vevent("UID:1", "DTSTART;TZID=Customized Time Zone:20260715T090000"), defaultTimeZone: berlin)
        #expect(other.timeZone.secondsFromGMT() == 8 * 3600)
        #expect(other.start == instant(2026, 7, 15, 1, in: .gmt))
    }

    @Test func unknownTimeZoneFallsBackToDefault() throws {
        let event = try onlyEvent(vevent("UID:1", "DTSTART;TZID=Nowhere Standard Time:20261022T090000"))
        #expect(event.start == instant(2026, 10, 22, 9, in: berlin))
    }

    @Test func floatingTimeIsInDefaultZone() throws {
        let event = try onlyEvent(vevent("UID:1", "DTSTART:20261022T090000"))
        #expect(event.start == instant(2026, 10, 22, 9, in: berlin))
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        let inTokyo = try onlyEvent(vevent("UID:1", "DTSTART:20261022T090000"), defaultTimeZone: tokyo)
        #expect(inTokyo.start == instant(2026, 10, 22, 9, in: tokyo))
    }

    @Test func allDayWithEnd() throws {
        let event = try onlyEvent(vevent("UID:1", "DTSTART;VALUE=DATE:20261022", "DTEND;VALUE=DATE:20261025"))
        #expect(event.isAllDay)
        #expect(event.start == instant(2026, 10, 22, in: berlin))
        #expect(event.end == instant(2026, 10, 25, in: berlin))
    }

    @Test func allDayWithoutEndLastsOneDay() throws {
        // An eight-digit value is a date even without VALUE=DATE.
        let event = try onlyEvent(vevent("UID:1", "DTSTART:20261022"))
        #expect(event.isAllDay)
        #expect(event.start == instant(2026, 10, 22, in: berlin))
        #expect(event.end == instant(2026, 10, 23, in: berlin))
    }

    @Test func timedWithoutEndHasNoLength() throws {
        let event = try onlyEvent(vevent("UID:1", "DTSTART:20261022T090000Z"))
        #expect(event.end == event.start)
    }

    @Test func endBeforeStartBecomesStart() throws {
        let event = try onlyEvent(vevent("UID:1", "DTSTART:20261022T090000Z", "DTEND:20261022T080000Z"))
        #expect(event.end == event.start)
    }

    @Test func durations() throws {
        // RFC 5545 §3.3.6 / §3.8.2.5 examples.
        let long = try onlyEvent(vevent("UID:1", "DTSTART:20261022T090000Z", "DURATION:P15DT5H0M20S"))
        #expect(long.end == instant(2026, 11, 6, 14, 0, 20, in: .gmt))
        let weeks = try onlyEvent(vevent("UID:1", "DTSTART:20261022T090000Z", "DURATION:P7W"))
        #expect(weeks.end == instant(2026, 12, 10, 9, in: .gmt))
        let hour = try onlyEvent(vevent("UID:1", "DTSTART:20261022T090000Z", "DURATION:PT1H"))
        #expect(hour.end == instant(2026, 10, 22, 10, in: .gmt))
        let negative = try onlyEvent(vevent("UID:1", "DTSTART:20261022T090000Z", "DURATION:-PT1H"))
        #expect(negative.end == negative.start)
    }

    @Test func absurdDurationsAreIgnoredInsteadOfTrapping() throws {
        for value in ["PT2562047788015216H", "P9223372036854775807D", "P1000001W", "PT1000001S"] {
            let event = try onlyEvent(vevent("UID:1", "DTSTART:20261022T090000Z", "DURATION:\(value)"))
            #expect(event.end == event.start, "\(value)")
        }
        let limit = try onlyEvent(vevent("UID:1", "DTSTART:20261022T090000Z", "DURATION:PT1000000S"))
        #expect(limit.end == instant(2026, 10, 22, 9, in: .gmt).addingTimeInterval(1_000_000))
    }

    @Test func durationDaysAreCalendarDays() throws {
        // Berlin leaves DST on 25 October 2026, so that day lasts 25 hours.
        let event = try onlyEvent(vevent("UID:1", "DTSTART;TZID=Europe/Berlin:20261024T120000", "DURATION:P1D"))
        #expect(event.end == instant(2026, 10, 25, 12, in: berlin))
        #expect(event.end.timeIntervalSince(event.start) == 25 * 3600)
    }

    @Test func recurrencePropertiesAreRead() throws {
        let event = try onlyEvent(vevent(
            "UID:1",
            "DTSTART;TZID=America/New_York:20261019T090000",
            "RRULE:FREQ=DAILY;COUNT=5",
            "EXDATE;TZID=America/New_York:20261020T090000,20261021T090000",
            "EXDATE:20261023T130000Z",
            "RDATE;VALUE=DATE:20261030",
            "RDATE;VALUE=PERIOD:20261031T090000Z/PT1H",
            "STATUS:CANCELLED"
        ))
        let newYork = TimeZone(identifier: "America/New_York")!
        #expect(event.recurrence?.frequency == .daily)
        #expect(event.recurrence?.count == 5)
        #expect(event.exceptionDates == [
            instant(2026, 10, 20, 9, in: newYork), instant(2026, 10, 21, 9, in: newYork),
            instant(2026, 10, 23, 13, in: .gmt),
        ])
        #expect(event.recurrenceDates == [instant(2026, 10, 30, in: berlin)])
        #expect(event.isCancelled)
    }

    @Test func hugeIntervalMeansNoRecurrence() throws {
        let event = try onlyEvent(vevent("UID:1", "DTSTART:20261022T090000Z", "RRULE:FREQ=DAILY;INTERVAL=9223372036854775807"))
        #expect(event.recurrence == nil)
        let feed = ICalendar.parse(feedText(vevent(
            "UID:1", "DTSTART:20261022T090000Z", "RRULE:FREQ=WEEKLY;INTERVAL=10001"
        )), defaultTimeZone: berlin)
        let day = DateInterval(start: instant(2026, 10, 1, in: .gmt), end: instant(2027, 12, 31, in: .gmt))
        #expect(feed.occurrences(overlapping: day).count == 1)
    }

    @Test func unsupportedRuleMeansNoRecurrence() throws {
        let event = try onlyEvent(vevent("UID:1", "DTSTART:20261022T090000Z", "RRULE:FREQ=HOURLY;COUNT=3"))
        #expect(event.recurrence == nil)
    }
}

struct WindowsTimeZoneTests {
    @Test func everyIANAValueResolves() {
        #expect(WindowsTimeZones.ianaIdentifiers.count >= 135)
        for (windows, iana) in WindowsTimeZones.ianaIdentifiers {
            #expect(TimeZone(identifier: iana) != nil, "\(windows) → \(iana)")
        }
    }

    @Test func wellKnownNames() {
        let expected = [
            "China Standard Time": "Asia/Shanghai",
            "Pacific Standard Time": "America/Los_Angeles",
            "W. Europe Standard Time": "Europe/Berlin",
            "GMT Standard Time": "Europe/London",
            "Tokyo Standard Time": "Asia/Tokyo",
            "India Standard Time": "Asia/Calcutta",
            "Eastern Standard Time": "America/New_York",
            "UTC": "Etc/UTC",
        ]
        for (windows, iana) in expected {
            #expect(WindowsTimeZones.ianaIdentifier(for: windows) == iana)
        }
        #expect(WindowsTimeZones.ianaIdentifier(for: "china standard time") == "Asia/Shanghai")
        #expect(WindowsTimeZones.ianaIdentifier(for: "Atlantis Standard Time") == nil)
    }

    @Test func windowsNamesResolveThroughTheTable() {
        let zone = ICalendarTimeZone.resolve("Romance Standard Time", defaultTimeZone: .gmt)
        #expect(zone.identifier == "Europe/Paris")
    }
}

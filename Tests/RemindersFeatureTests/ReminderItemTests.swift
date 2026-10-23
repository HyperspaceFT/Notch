import Foundation
import NotchKit
import Testing
@testable import RemindersFeature

private let zone = TimeZone(secondsFromGMT: 8 * 3600)!

private var calendar: Foundation.Calendar {
    var calendar = Foundation.Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    return calendar
}

/// October 2026 in the test zone; days past 31 run into November.
private func oct(_ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
}

/// Thursday 22 October 2026, 10:00.
private let now = oct(22, 10)

private let gray = ReminderColor(red: 0.5, green: 0.5, blue: 0.5)

private func item(_ title: String, due: ReminderDue? = nil, created: Date? = nil, id: String? = nil) -> ReminderItem {
    ReminderItem(id: id ?? title, title: title, due: due, created: created, color: gray, listTitle: "List")
}

private func timed(_ date: Date) -> ReminderDue { ReminderDue(date: date, hasTime: true) }
private func dateOnly(_ date: Date) -> ReminderDue { ReminderDue(date: date, hasTime: false) }

struct ReminderOrderTests {
    @Test func datedComeBeforeUndated() {
        let ordered = ReminderItem.ordered([
            item("Undated", created: oct(22, 9)),
            item("Dated", due: timed(oct(30, 9))),
        ])
        #expect(ordered.map(\.title) == ["Dated", "Undated"])
    }

    @Test func earlierDueComesFirst() {
        let ordered = ReminderItem.ordered([
            item("Later", due: timed(oct(24, 9))),
            item("Overdue", due: dateOnly(oct(20))),
            item("Sooner", due: timed(oct(22, 15))),
        ])
        #expect(ordered.map(\.title) == ["Overdue", "Sooner", "Later"])
    }

    @Test func dateOnlyComesBeforeTimedOnTheSameDay() {
        let ordered = ReminderItem.ordered([
            item("Midnight", due: timed(oct(23, 0))),
            item("Morning", due: timed(oct(23, 8))),
            item("Whole day", due: dateOnly(oct(23))),
        ])
        #expect(ordered.map(\.title) == ["Whole day", "Midnight", "Morning"])
    }

    @Test func undatedNewestCreatedFirstAndUnknownCreatedLast() {
        let ordered = ReminderItem.ordered([
            item("No date"),
            item("Old", created: oct(1)),
            item("New", created: oct(21)),
        ])
        #expect(ordered.map(\.title) == ["New", "Old", "No date"])
    }

    @Test func tiesSettleByTitleThenID() {
        let input = [
            item("B", due: timed(oct(23, 9)), id: "1"),
            item("A", due: timed(oct(23, 9)), id: "3"),
            item("A", due: timed(oct(23, 9)), id: "2"),
            item("Same", id: "y"),
            item("Same", id: "x"),
        ]
        let expected = ["2", "3", "1", "x", "y"]
        #expect(ReminderItem.ordered(input).map(\.id) == expected)
        #expect(ReminderItem.ordered(input.reversed()).map(\.id) == expected)
    }
}

struct ReminderTitleTests {
    @Test func trimsAndCollapsesWhitespace() {
        #expect(ReminderItem.normalizedTitle("  Buy milk  ") == "Buy milk")
        #expect(ReminderItem.normalizedTitle("Buy\nmilk") == "Buy milk")
        #expect(ReminderItem.normalizedTitle("Buy \t\n  milk\r\nand   eggs") == "Buy milk and eggs")
    }

    @Test func blankIsNil() {
        #expect(ReminderItem.normalizedTitle("") == nil)
        #expect(ReminderItem.normalizedTitle("   ") == nil)
        #expect(ReminderItem.normalizedTitle(" \n\t \r\n") == nil)
    }
}

struct ReminderDueTests {
    @Test func dateOnlyComponentsAreTheStartOfTheirDay() {
        let due = ReminderDue(components: DateComponents(year: 2026, month: 10, day: 23), calendar: calendar)
        #expect(due == dateOnly(oct(23)))
        let withTime = ReminderDue(
            components: DateComponents(year: 2026, month: 10, day: 23, hour: 9, minute: 30),
            calendar: calendar
        )
        #expect(withTime == timed(oct(23, 9, 30)))
        #expect(ReminderDue(components: nil, calendar: calendar) == nil)
    }

    @Test func timedIsOverdueOnceItsTimeHasPassed() {
        #expect(timed(oct(22, 9, 59)).isOverdue(now: now, calendar: calendar))
        #expect(timed(oct(21, 18)).isOverdue(now: now, calendar: calendar))
        #expect(!timed(oct(22, 10, 1)).isOverdue(now: now, calendar: calendar))
        #expect(!timed(oct(23, 9)).isOverdue(now: now, calendar: calendar))
    }

    @Test func dateOnlyIsOverdueFromTheNextDay() {
        #expect(dateOnly(oct(21)).isOverdue(now: now, calendar: calendar))
        #expect(!dateOnly(oct(22)).isOverdue(now: now, calendar: calendar))
        #expect(!dateOnly(oct(23)).isOverdue(now: now, calendar: calendar))
    }

    private func labels(_ due: ReminderDue) -> (en: String, zh: String) {
        (
            due.label(now: now, language: .english, calendar: calendar),
            due.label(now: now, language: .simplifiedChinese, calendar: calendar)
        )
    }

    @Test func todayIsTheTimeOrToday() {
        #expect(labels(timed(oct(22, 14, 5))) == ("14:05", "14:05"))
        #expect(labels(timed(oct(22, 8))) == ("08:00", "08:00"))
        #expect(labels(dateOnly(oct(22))) == ("Today", "今天"))
    }

    @Test func tomorrowIsNamed() {
        #expect(labels(dateOnly(oct(23))) == ("Tomorrow", "明天"))
        #expect(labels(timed(oct(23, 9, 30))) == ("Tomorrow 09:30", "明天 09:30"))
    }

    @Test func theRestOfTheWeekIsAWeekday() {
        #expect(labels(dateOnly(oct(24))) == ("Sat", "周六"))
        #expect(labels(timed(oct(26, 8))) == ("Mon 08:00", "周一 08:00"))
        #expect(labels(dateOnly(oct(28))) == ("Wed", "周三"))
    }

    @Test func otherDaysAreAMonthAndDay() {
        #expect(labels(dateOnly(oct(29))) == ("Oct 29", "10月29日"))
        #expect(labels(timed(oct(29, 7, 15))) == ("Oct 29 07:15", "10月29日 07:15"))
        #expect(labels(dateOnly(oct(21))) == ("Oct 21", "10月21日"))
        #expect(labels(timed(oct(21, 18))) == ("Oct 21 18:00", "10月21日 18:00"))
        #expect(labels(dateOnly(oct(33))) == ("Nov 2", "11月2日"))
    }
}

import Foundation
import Testing
@testable import CalendarFeature

@MainActor
struct EventReminderWingsTests {
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func notice(_ titles: [String]) -> EventReminderNotice {
        EventReminderNotice(reminders: titles.enumerated().map { index, title in
            EventReminder(
                event: AgendaEvent(
                    id: "\(index)", title: title, location: nil, start: start,
                    end: start.addingTimeInterval(30 * 60), isAllDay: false,
                    color: CalendarColor(red: 0.2, green: 0.4, blue: 0.6), calendarTitle: "Test"
                ),
                kind: .upcoming,
                minutesLeft: 5
            )
        })
    }

    /// Five minutes before the start, as a reminder usually fires.
    private var now: Date { start.addingTimeInterval(-5 * 60) }

    @Test func aShortTitleGetsNarrowWings() {
        let wings = EventReminderWings.widths(for: notice(["Standup"]), now: now)
        #expect(wings.leading < EventReminderWings.maximumWidth)
        #expect(wings.trailing < EventReminderWings.maximumWidth)
    }

    @Test func moreEventsWidenOnlyTheLeftWing() {
        let one = EventReminderWings.widths(for: notice(["Standup"]), now: now)
        let three = EventReminderWings.widths(for: notice(["Standup", "Review", "Lunch"]), now: now)
        #expect(three.leading > one.leading)
        #expect(three.trailing == one.trailing)
    }

    @Test func theRightWingHasRoomForTheStatusOnceItStarts() {
        // Shorter than either status line, so they set the width.
        let short = EventReminderWings.widths(for: notice(["1:1"]), now: now)
        let atStart = EventReminderWings.widths(for: notice(["1:1"]), now: start)
        #expect(short.trailing == atStart.trailing)
        #expect(short.trailing >= EventReminderWings.minimumTrailingWidth)
    }

    @Test func aLongTitleStopsAtTheMaximum() {
        let wings = EventReminderWings.widths(
            for: notice(["Quarterly Planning Review with the Whole Product Team"]),
            now: now
        )
        #expect(wings.trailing == EventReminderWings.maximumWidth)
    }
}

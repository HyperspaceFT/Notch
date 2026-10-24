import AppKit
import NotchKit
import NotchUI
import SwiftUI

/// Width of each event reminder wing: room for the start time on the left and
/// a short title on the right.
let eventReminderWingWidth: CGFloat = 120

/// Space kept between a wing's content and the island's outer edge, so it stays
/// clear of the rounded bottom corner (`NotchTheme.activityBottomRadius`).
private let wingCornerClearance: CGFloat = 12
/// Space between a wing's content and the notch.
private let wingNotchClearance: CGFloat = 6

/// How far a wing's content moves while the island is hovered: half the ring it
/// grows by, outward (`outward` is -1 for the left wing, 1 for the right) and
/// down, so it keeps its place in the grown outline. As in the notification wings.
private func wingHoverOffset(isHovered: Bool, outward: CGFloat) -> CGSize {
    guard isHovered else { return .zero }
    return CGSize(width: NotchTheme.hoverGrowth.width / 2 * outward, height: NotchTheme.hoverGrowth.height / 2)
}

/// The event's title, or "No Title" as the agenda shows an untitled one.
@MainActor
private func displayTitle(_ event: AgendaEvent) -> String {
    let title = event.title.trimmingCharacters(in: .whitespacesAndNewlines)
    return title.isEmpty ? localized(en: "No Title", zh: "无标题") : title
}

/// "In 5 min", "Starting now", or "Started 7 min ago": the wing can show
/// long after the reminder fired, when it waited out an expanded island.
@MainActor
private func wingStatus(_ phase: EventReminderPhase) -> String {
    switch phase {
    case .startsIn(let minutes):
        localized(en: "In \(minutes) min", zh: "\(minutes) 分钟后")
    case .startingNow:
        localized(en: "Starting now", zh: "现在开始")
    case .startedAgo(let minutes):
        localized(en: "Started \(minutes) min ago", zh: "已开始 \(minutes) 分钟")
    }
}

/// Where the event stands at `now`, for the detail, which can stay open past
/// the moment the reminder fired: "Starts in 5 min" (minutes rounded up),
/// "Now" until it ends, then "Ended". A zero-length event is "Now" only at
/// its start.
@MainActor
private func liveStatus(_ event: AgendaEvent, now: Date) -> String {
    if now < event.start {
        let minutes = Int((event.start.timeIntervalSince(now) / 60).rounded(.up))
        return localized(en: "Starts in \(minutes) min", zh: "\(minutes) 分钟后开始")
    }
    let hasEnded = event.end > event.start ? now >= event.end : now > event.start
    return hasEnded ? localized(en: "Ended", zh: "已结束") : localized(en: "Now", zh: "进行中")
}

/// "09:00–10:30", or the start alone for an event without length.
private func timeRange(_ event: AgendaEvent) -> String {
    let start = CalendarFormat.clock(event.start, calendar: .current)
    guard event.end > event.start else { return start }
    return "\(start)–\(CalendarFormat.clock(event.end, calendar: .current))"
}

/// Left wing: a calendar symbol in the first event's calendar color and its
/// start time, with "+N" when more events are due, next to the notch. A click
/// opens the detail.
struct EventReminderWingLeading: View {
    let notice: EventReminderNotice
    let open: @MainActor () -> Void
    @Environment(\.notchIsHovered) private var isIslandHovered

    var body: some View {
        let event = notice.first.event
        Button(action: open) {
            HStack(spacing: 5) {
                Spacer(minLength: 0)
                Image(systemName: "calendar")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(event.color.color)
                Text(CalendarFormat.clock(event.start, calendar: .current))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(NotchTheme.primaryText)
                    .monospacedDigit()
                    .lineLimit(1)
                if notice.othersCount > 0 {
                    Text("+\(notice.othersCount)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(NotchTheme.secondaryText)
                        .monospacedDigit()
                        .lineLimit(1)
                }
            }
            // An offset, not padding: the text keeps its width. The island's
            // hover animation carries the move.
            .offset(wingHoverOffset(isHovered: isIslandHovered, outward: -1))
            .padding(.leading, wingCornerClearance)
            .padding(.trailing, wingNotchClearance)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

/// Right wing: the first event's title over how soon it starts, kept current.
/// A click opens the detail.
struct EventReminderWingTrailing: View {
    let notice: EventReminderNotice
    let open: @MainActor () -> Void
    @Environment(\.notchIsHovered) private var isIslandHovered

    /// How often the status line is worked out again.
    private static let refreshInterval: TimeInterval = 15

    var body: some View {
        let reminder = notice.first
        Button(action: open) {
            VStack(alignment: .leading, spacing: 1) {
                Text(displayTitle(reminder.event))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(NotchTheme.primaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                TimelineView(.periodic(from: .now, by: Self.refreshInterval)) { context in
                    Text(wingStatus(EventReminderPhase(start: reminder.event.start, now: context.date)))
                        .font(.system(size: 10))
                        .foregroundStyle(NotchTheme.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            // Moves with the hovered island, like the left wing.
            .offset(wingHoverOffset(isHovered: isIslandHovered, outward: 1))
            .padding(.leading, wingNotchClearance)
            .padding(.trailing, wingCornerClearance)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

/// The due events in full, opened from the reminder's wings: one event in a
/// roomy card, several as rows that scroll when they do not fit. Each shows
/// its calendar, title, time, where it stands now, and location, and a Join
/// button when it has a meeting link.
struct EventReminderDetailView: View {
    let notice: EventReminderNotice

    /// Height of the fade at the bottom, where rows longer than the card are cut off.
    private static let fadeHeight: CGFloat = 14
    /// How often "Starts in N min" and the rest are worked out again.
    private static let refreshInterval: TimeInterval = 30

    var body: some View {
        TimelineView(.periodic(from: .now, by: Self.refreshInterval)) { context in
            if notice.othersCount == 0 {
                single(notice.first, now: context.date)
            } else {
                list(now: context.date)
            }
        }
    }

    private func single(_ reminder: EventReminder, now: Date) -> some View {
        let event = reminder.event
        return NotchCard(tint: event.color.color) {
            VStack(alignment: .leading, spacing: 6) {
                CalendarLabel(event: event)
                Text(displayTitle(event))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(NotchTheme.primaryText)
                    .lineLimit(2)
                DetailLine(symbol: "clock", text: "\(timeRange(event)) · \(liveStatus(event, now: now))")
                if let location = event.location {
                    DetailLine(symbol: "mappin.and.ellipse", text: location)
                }
                Spacer(minLength: 0)
                if let url = event.meetingURL {
                    JoinButton(url: url)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func list(now: Date) -> some View {
        NotchCard {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(notice.reminders.enumerated()), id: \.offset) { index, reminder in
                        if index > 0 {
                            Rectangle()
                                .fill(Color.white.opacity(0.1))
                                .frame(height: 1)
                                .padding(.vertical, 6)
                        }
                        ReminderRow(reminder: reminder, now: now)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // Room to scroll the last row clear of the fade.
                .padding(.bottom, Self.fadeHeight)
            }
            .scrollIndicators(.hidden)
            // Rows cut off at the bottom fade out instead of ending at a hard edge.
            .mask {
                VStack(spacing: 0) {
                    Color.black
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: Self.fadeHeight)
                }
            }
        }
    }
}

/// One of several due events: a bar in its calendar's color, its title, time
/// and calendar, location, and a Join button when it has a meeting link.
private struct ReminderRow: View {
    let reminder: EventReminder
    let now: Date

    var body: some View {
        let event = reminder.event
        HStack(alignment: .center, spacing: 8) {
            Capsule()
                .fill(event.color.color)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                Text(displayTitle(event))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(NotchTheme.primaryText)
                    .lineLimit(1)
                Text([timeRange(event), liveStatus(event, now: now), event.calendarTitle]
                    .filter { !$0.isEmpty }
                    .joined(separator: " · "))
                    .font(.system(size: 10.5))
                    .foregroundStyle(NotchTheme.secondaryText)
                    .monospacedDigit()
                    .lineLimit(1)
                if let location = event.location {
                    Text(location)
                        .font(.system(size: 10.5))
                        .foregroundStyle(NotchTheme.secondaryText)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if let url = event.meetingURL {
                JoinButton(url: url)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// The event's calendar: a dot in its color and its name.
private struct CalendarLabel: View {
    let event: AgendaEvent

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(event.color.color)
                .frame(width: 8, height: 8)
            Text(event.calendarTitle)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(NotchTheme.secondaryText)
                .lineLimit(1)
        }
    }
}

/// A symbol and a line of secondary text.
private struct DetailLine: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 11))
                .frame(width: 14)
            Text(text)
                .font(.system(size: 12))
                .monospacedDigit()
                .lineLimit(1)
        }
        .foregroundStyle(NotchTheme.secondaryText)
    }
}

/// Opens the meeting link in its app or the browser.
private struct JoinButton: View {
    let url: URL

    var body: some View {
        GlassCapsuleButton(localized(en: "Join", zh: "加入会议"), symbol: "video") {
            NSWorkspace.shared.open(url)
        }
    }
}

import AppKit
import NotchKit
import NotchUI
import Observation
import SwiftUI

/// The calendar module at the size Home gives it: the coming days' events,
/// local and subscribed together (or either alone, as the card's switch says),
/// in a list that scrolls. From
/// `wideThreshold` on, each event's time sits in its own column with the
/// location after the title.
struct CalendarModuleView: View {
    let settings: CalendarSettings
    let local: LocalCalendars
    let feeds: SubscriptionFeeds
    let state: AgendaCardState
    let size: CGSize

    /// How often the module checks whether a feed needs downloading.
    static let checkInterval: Duration = .seconds(60)
    static let wideThreshold: CGFloat = 300

    var body: some View {
        // Redrawn every minute, so ended events drop off and "Now" moves on.
        TimelineView(.everyMinute) { context in
            let days = agenda(at: context.date)
            // Tinted by the calendar of the first event listed: one going on or the next.
            NotchCard(tint: days.first?.entries.first?.event.color.color) {
                content(days, now: context.date)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    // In every state, so the user can always switch back.
                    .overlay(alignment: .topTrailing) {
                        CalendarSourceSwitch(source: settings.source) { source in
                            withAnimation(.snappy(duration: 0.25)) {
                                settings.source = source
                            }
                        }
                    }
            }
        }
        .frame(width: size.width, height: size.height)
        // SwiftUI cancels this when the module leaves the screen, such as when the
        // panel collapses, so this loop downloads no feed while the island is
        // closed (the reminder loop in `CalendarFeature` may, while reminders are on).
        // It starts over when the source changes, so a feed newly included is
        // checked at once.
        .task(id: settings.source) {
            let source = settings.source
            if CalendarCardState.shouldRequestAccess(
                source: source,
                access: local.access,
                hasEnabledSubscriptions: hasEnabledSubscriptions
            ) {
                local.requestAccess()
            }
            while !Task.isCancelled {
                local.refreshAccess()
                if source.includesCloud {
                    feeds.refreshIfNeeded()
                }
                try? await Task.sleep(for: Self.checkInterval)
            }
        }
    }

    private var hasEnabledSubscriptions: Bool {
        settings.subscriptions.contains(where: \.isEnabled)
    }

    private func agenda(at now: Date) -> [AgendaDay] {
        let calendar = Calendar.current
        let window = Agenda.window(now: now, dayCount: settings.dayCount, calendar: calendar)
        let source = settings.source
        let events = (source.includesLocal ? local.events(in: window, hidden: settings.hiddenCalendarIDs) : [])
            + (source.includesCloud ? feeds.events() : [])
        return Agenda.days(for: events, now: now, dayCount: settings.dayCount, calendar: calendar)
    }

    @ViewBuilder
    private func content(_ days: [AgendaDay], now: Date) -> some View {
        if !days.isEmpty {
            AgendaList(
                days: days,
                now: now,
                state: state,
                isWide: size.width >= Self.wideThreshold,
                // Room for the switch, which the first day's title would run under.
                firstTitleTrailingInset: CalendarSourceSwitch.width + 6
            )
        } else {
            switch CalendarCardState.state(
                source: settings.source,
                access: local.access,
                hasEnabledSubscriptions: hasEnabledSubscriptions,
                isFetchingFirstTime: feeds.isFetchingFirstTime(),
                hasFailedWithoutData: feeds.hasFailedWithoutData()
            ) {
            case .allowAccess:
                centered {
                    StatusLine(symbol: "calendar") {
                        localized(en: "Show your events here", zh: "在这里显示你的日程")
                    }
                    GlassCapsuleButton(localized(en: "Allow", zh: "允许"), symbol: "checkmark") {
                        local.requestAccess()
                    }
                }
            case .accessNeeded:
                centered {
                    StatusLine(symbol: "calendar.badge.exclamationmark") {
                        localized(en: "Calendar access needed", zh: "需要日历权限")
                    }
                    GlassCapsuleButton(localized(en: "Open Settings", zh: "打开设置"), symbol: "gear") {
                        local.openPrivacySettings()
                    }
                }
            case .addLinks:
                centered {
                    StatusLine(symbol: "link") {
                        localized(en: "Add calendar links in Settings", zh: "在设置中添加日历链接")
                    }
                }
            case .loading:
                centered {
                    ProgressView()
                        .controlSize(.small)
                }
            case .failed:
                centered {
                    StatusLine(symbol: "exclamationmark.icloud") {
                        localized(en: "Couldn't update calendars", zh: "无法更新订阅日历")
                    }
                }
            case .empty:
                centered {
                    StatusLine(symbol: "calendar") {
                        let count = settings.dayCount
                        return count == 1
                            ? localized(en: "No more events today", zh: "今天没有更多日程")
                            : localized(en: "No events in the next \(count) days", zh: "未来 \(count) 天没有日程")
                    }
                }
            }
        }
    }

    private func centered<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 6) {
            content()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// What the card shows when there are no events to list, for the chosen
/// source. `.all` keeps the order the card had before the switch: the Calendar
/// app's access states only while no subscription is enabled.
enum CalendarCardState: Equatable {
    case allowAccess
    case accessNeeded
    case addLinks
    case loading
    case failed
    case empty

    static func state(
        source: CalendarSource,
        access: LocalCalendars.Access,
        hasEnabledSubscriptions: Bool,
        isFetchingFirstTime: Bool,
        hasFailedWithoutData: Bool
    ) -> CalendarCardState {
        switch source {
        case .local:
            switch access {
            case .notDetermined: return .allowAccess
            case .denied: return .accessNeeded
            case .granted: return .empty
            }
        case .cloud:
            if !hasEnabledSubscriptions { return .addLinks }
            if isFetchingFirstTime { return .loading }
            if hasFailedWithoutData { return .failed }
            return .empty
        case .all:
            if !hasEnabledSubscriptions && access == .notDetermined { return .allowAccess }
            if !hasEnabledSubscriptions && access == .denied { return .accessNeeded }
            if isFetchingFirstTime { return .loading }
            if hasFailedWithoutData { return .failed }
            return .empty
        }
    }

    /// Whether the card asks for Calendar access by itself when it appears: not
    /// for `.cloud`, and for `.all` only when subscriptions cannot fill the card.
    static func shouldRequestAccess(
        source: CalendarSource,
        access: LocalCalendars.Access,
        hasEnabledSubscriptions: Bool
    ) -> Bool {
        guard access == .notDetermined else { return false }
        switch source {
        case .local: return true
        case .cloud: return false
        case .all: return !hasEnabledSubscriptions
        }
    }
}

/// Three icon segments that pick which events the card lists, in the card's
/// top-trailing corner. The selection capsule slides between them.
private struct CalendarSourceSwitch: View {
    let source: CalendarSource
    let select: (CalendarSource) -> Void

    @Namespace private var selection

    private static let segmentSize = CGSize(width: 20, height: 16)
    private static let inset: CGFloat = 2

    /// Its width, for the room the first day's title leaves free.
    static var width: CGFloat {
        segmentSize.width * CGFloat(CalendarSource.allCases.count) + inset * 2
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(CalendarSource.allCases, id: \.self) { option in
                let isSelected = option == source
                Button {
                    select(option)
                } label: {
                    Image(systemName: option.symbol)
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(isSelected ? NotchTheme.primaryText : NotchTheme.secondaryText)
                        .frame(width: Self.segmentSize.width, height: Self.segmentSize.height)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(Color.white.opacity(0.16))
                                    .matchedGeometryEffect(id: "selection", in: selection)
                            }
                        }
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .help(option.title)
                .accessibilityLabel(option.title)
                .accessibilityValue(isSelected ? localized(en: "Selected", zh: "已选中") : "")
            }
        }
        .padding(Self.inset)
        // Dark enough that events scrolled under it stay out of the way.
        .background {
            Capsule()
                .fill(Color.black.opacity(0.55))
                .overlay { Capsule().fill(Color.white.opacity(0.08)) }
        }
    }
}

/// An icon over a short line, for the states without events.
private struct StatusLine: View {
    let symbol: String
    let text: () -> String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 18))
                .foregroundStyle(NotchTheme.secondaryText)
            Text(text())
                .font(.system(size: 11))
                .foregroundStyle(NotchTheme.secondaryText)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
        }
    }
}

private struct AgendaList: View {
    let days: [AgendaDay]
    let now: Date
    let state: AgendaCardState
    let isWide: Bool
    /// Trailing room the first day's title leaves free.
    let firstTitleTrailingInset: CGFloat

    /// Height of the fade at the bottom, where a list longer than the card is cut off.
    private static let fadeHeight: CGFloat = 18

    var body: some View {
        let language = Localization.shared.language
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(days) { day in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(CalendarFormat.dayTitle(day.start, now: now, language: language, calendar: .current))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(NotchTheme.secondaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .padding(.trailing, day.id == days.first?.id ? firstTitleTrailingInset : 0)
                        ForEach(day.entries) { entry in
                            EntryRow(
                                entry: entry,
                                time: CalendarFormat.timeText(entry, now: now, language: language, calendar: .current),
                                language: language,
                                isWide: isWide,
                                state: state
                            )
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // Room to scroll the last event clear of the fade.
            .padding(.bottom, Self.fadeHeight)
        }
        .scrollIndicators(.hidden)
        // Events cut off at the bottom fade out instead of ending at a hard edge.
        .mask {
            VStack(spacing: 0) {
                Color.black
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: Self.fadeHeight)
            }
        }
    }
}

/// One event: a bar in its calendar's color, the title, and the time. A click
/// expands it to the full title and location, the calendar, any meeting link,
/// and a button that copies them; another click collapses it.
private struct EntryRow: View {
    let entry: AgendaEntry
    let time: String
    let language: AppLanguage
    let isWide: Bool
    let state: AgendaCardState

    /// Wide enough for "Now · until 10:30" and "进行中 · 至 10:30".
    private static let timeColumnWidth: CGFloat = 108

    private var isExpanded: Bool { state.expandedID == entry.id }

    var body: some View {
        let event = entry.event
        Group {
            if isWide && isExpanded {
                HStack(alignment: .top, spacing: 8) {
                    bar(event.color.color)
                    timeText
                        .frame(width: Self.timeColumnWidth, alignment: .leading)
                    VStack(alignment: .leading, spacing: 3) {
                        titleText
                        details
                    }
                    Spacer(minLength: 0)
                }
                .fixedSize(horizontal: false, vertical: true)
            } else if isWide {
                HStack(spacing: 8) {
                    bar(event.color.color)
                        .frame(height: 14)
                    timeText
                        .frame(width: Self.timeColumnWidth, alignment: .leading)
                    HStack(spacing: 6) {
                        titleText
                            .layoutPriority(1)
                        if let location = event.location {
                            Text(CalendarFormat.capped(location))
                                .font(.system(size: 11))
                                .foregroundStyle(NotchTheme.secondaryText)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
            } else {
                HStack(spacing: 6) {
                    bar(event.color.color)
                    VStack(alignment: .leading, spacing: 1) {
                        titleText
                        timeText
                        if isExpanded {
                            details
                                .padding(.top, 2)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        // The gaps between the texts take the click too. The copy button's own
        // click goes to it, not here.
        .contentShape(.rect)
        .onTapGesture {
            withAnimation(.snappy(duration: 0.25)) {
                state.toggle(entry.id)
            }
        }
    }

    private func bar(_ color: Color) -> some View {
        Capsule()
            .fill(color)
            .frame(width: 3)
    }

    private var titleText: some View {
        Text(CalendarFormat.title(entry.event, language: language))
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(NotchTheme.primaryText)
            .lineLimit(isExpanded ? nil : 1)
            .fixedSize(horizontal: false, vertical: isExpanded)
    }

    private var timeText: some View {
        Text(time)
            .font(.system(size: 10.5))
            .foregroundStyle(NotchTheme.secondaryText)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    /// What the collapsed row leaves out, one line each, then the copy button.
    /// The dates only for an event that spans days, whose time on this day
    /// ("Until 02:00") hides when it began or ends.
    @ViewBuilder
    private var details: some View {
        let event = entry.event
        if entry.startsBeforeDay || entry.endsAfterDay {
            DetailLine(symbol: "clock", text: CalendarFormat.spanText(event, language: language, calendar: .current))
        }
        if let location = event.location {
            DetailLine(symbol: "mappin.and.ellipse", text: CalendarFormat.capped(location))
        }
        let calendarTitle = CalendarFormat.capped(event.calendarTitle)
        if !calendarTitle.isEmpty {
            DetailLine(symbol: "calendar", text: calendarTitle)
        }
        if let url = event.meetingURL {
            // Long links keep both ends; the copy holds the whole link.
            DetailLine(symbol: "video", text: url.absoluteString, wraps: false)
        }
        CopyButton(
            text: CalendarFormat.copyText(event, language: language, calendar: .current),
            isCopied: state.copiedID == entry.id
        ) {
            state.copied(entry.id)
        }
        .padding(.top, 2)
    }
}

/// A symbol and secondary text, wrapped unless `wraps` is false.
private struct DetailLine: View {
    let symbol: String
    let text: String
    var wraps = true

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 9.5))
                .frame(width: 12)
            Text(text)
                .font(.system(size: 10.5))
                .monospacedDigit()
                .lineLimit(wraps ? nil : 1)
                .truncationMode(.middle)
                .fixedSize(horizontal: false, vertical: wraps)
        }
        .foregroundStyle(NotchTheme.secondaryText)
    }
}

/// Puts `text` on the clipboard, then reads "Copied" with a checkmark while
/// `isCopied`.
private struct CopyButton: View {
    let text: String
    let isCopied: Bool
    let didCopy: () -> Void

    var body: some View {
        Button {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            didCopy()
        } label: {
            Label(
                isCopied ? localized(en: "Copied", zh: "已拷贝") : localized(en: "Copy", zh: "拷贝"),
                systemImage: isCopied ? "checkmark" : "doc.on.doc"
            )
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(isCopied ? NotchTheme.primaryText : NotchTheme.secondaryText)
            .padding(.horizontal, 8)
            .frame(height: 20)
            .background(Capsule().fill(Color.white.opacity(isCopied ? 0.16 : 0.1)))
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.2), value: isCopied)
    }
}

/// The agenda's own view state, owned by the module rather than the view
/// (`@State` needs a macro plugin the Command Line Tools do not ship).
@MainActor
@Observable
final class AgendaCardState {
    /// How long a copy button reads "Copied".
    static let copyFeedbackDuration: Duration = .seconds(1.5)

    /// The entry a click expanded to its full text; one at a time.
    private(set) var expandedID: String?
    /// The entry whose text was copied within `copyFeedbackDuration`.
    private(set) var copiedID: String?

    @ObservationIgnored private var copyFeedback: Task<Void, Never>?

    /// Expands the entry, collapsing any other, or collapses it if expanded.
    func toggle(_ id: String) {
        expandedID = expandedID == id ? nil : id
    }

    /// Shows "Copied" on the entry's button for `duration`; a later copy
    /// starts the time over.
    func copied(_ id: String, for duration: Duration = copyFeedbackDuration) {
        copiedID = id
        copyFeedback?.cancel()
        copyFeedback = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.copiedID = nil
        }
    }
}

/// The agenda's day titles and event times, in a given language on the 24-hour clock.
enum CalendarFormat {
    /// "Today", "Tomorrow", else a short weekday and date such as "Sat, Oct 24"
    /// or "10月24日 周六".
    static func dayTitle(_ day: Date, now: Date, language: AppLanguage, calendar: Foundation.Calendar) -> String {
        let today = calendar.startOfDay(for: now)
        if calendar.isDate(day, inSameDayAs: today) {
            return text(en: "Today", zh: "今天", language)
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: today),
           calendar.isDate(day, inSameDayAs: tomorrow) {
            return text(en: "Tomorrow", zh: "明天", language)
        }
        return date(day, language: language, calendar: calendar)
    }

    /// A short weekday and date such as "Sat, Oct 24" or "10月24日 周六".
    static func date(_ day: Date, language: AppLanguage, calendar: Foundation.Calendar) -> String {
        let style = Date.FormatStyle(
            locale: Locale(identifier: language.rawValue),
            calendar: calendar,
            timeZone: calendar.timeZone
        )
        .month(.abbreviated)
        .day()
        .weekday(.abbreviated)
        return day.formatted(style)
    }

    /// The longest title, location or calendar name the agenda shows or copies.
    /// Feeds cap neither, and the text is laid out on the main thread.
    static let maxTextLength = 1_000

    /// `text` without surrounding whitespace, cut to `maxTextLength` characters
    /// and an ellipsis when longer. Reads no further into `text` than that.
    static func capped(_ text: String) -> String {
        let head = text.drop(while: \.isWhitespace).prefix(maxTextLength + 1)
        if head.count > maxTextLength {
            return head.prefix(maxTextLength).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
        }
        return head.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The event's title, `capped`, or "No Title" when it has none.
    static func title(_ event: AgendaEvent, language: AppLanguage) -> String {
        let title = capped(event.title)
        return title.isEmpty ? text(en: "No Title", zh: "无标题", language) : title
    }

    /// When `event` happens, on dates rather than relative to today:
    /// "Sat, Oct 24 · 13:00–14:30", "Sat, Oct 24 · All day",
    /// "Sat, Oct 24 – Mon, Oct 26" for all-day events over several days, and
    /// "Sat, Oct 24 22:00 – Sun, Oct 25 02:00" for a timed one past midnight.
    static func spanText(_ event: AgendaEvent, language: AppLanguage, calendar: Foundation.Calendar) -> String {
        let startDay = date(event.start, language: language, calendar: calendar)
        if event.isAllDay {
            // The end is exclusive: the midnight after the last day (feeds) or
            // 23:59:59 of it (EventKit), so a second earlier falls on that day.
            let lastDay = max(event.start, event.end.addingTimeInterval(-1))
            if calendar.isDate(lastDay, inSameDayAs: event.start) {
                return "\(startDay) · \(text(en: "All day", zh: "全天", language))"
            }
            return "\(startDay) – \(date(lastDay, language: language, calendar: calendar))"
        }
        let start = clock(event.start, calendar: calendar)
        guard event.end > event.start else { return "\(startDay) · \(start)" }
        let end = clock(event.end, calendar: calendar)
        if calendar.isDate(event.end, inSameDayAs: event.start) {
            return "\(startDay) · \(start)–\(end)"
        }
        return "\(startDay) \(start) – \(date(event.end, language: language, calendar: calendar)) \(end)"
    }

    /// What an expanded event's copy button puts on the clipboard, one line
    /// each: the title, `spanText`, and the location, calendar and meeting link
    /// it has.
    static func copyText(_ event: AgendaEvent, language: AppLanguage, calendar: Foundation.Calendar) -> String {
        [
            title(event, language: language),
            spanText(event, language: language, calendar: calendar),
            event.location.map(capped) ?? "",
            capped(event.calendarTitle),
            event.meetingURL?.absoluteString ?? "",
        ]
        .filter { !$0.isEmpty }
        .joined(separator: "\n")
    }

    /// When `entry` happens on its day: "09:00–10:30", "All day", "Until 02:00"
    /// for an event that began on an earlier day, "From 22:00" for one that ends
    /// on a later day, and, while it goes on, "Now · until 10:30" (or "Now"
    /// when it runs past today).
    static func timeText(_ entry: AgendaEntry, now: Date, language: AppLanguage, calendar: Foundation.Calendar) -> String {
        let event = entry.event
        if event.isAllDay || (entry.startsBeforeDay && entry.endsAfterDay) {
            return text(en: "All day", zh: "全天", language)
        }
        let start = clock(event.start, calendar: calendar)
        let end = clock(event.end, calendar: calendar)
        let isOngoing = calendar.isDate(entry.day, inSameDayAs: now) && event.start <= now && now < event.end
        if isOngoing {
            return entry.endsAfterDay
                ? text(en: "Now", zh: "进行中", language)
                : text(en: "Now · until \(end)", zh: "进行中 · 至 \(end)", language)
        }
        if entry.startsBeforeDay {
            return text(en: "Until \(end)", zh: "至 \(end)", language)
        }
        if entry.endsAfterDay {
            return text(en: "From \(start)", zh: "\(start) 起", language)
        }
        return event.end > event.start ? "\(start)–\(end)" : start
    }

    /// "07:30".
    static func clock(_ date: Date, calendar: Foundation.Calendar) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    private static func text(en english: String, zh chinese: String, _ language: AppLanguage) -> String {
        switch language {
        case .english: english
        case .simplifiedChinese: chinese
        }
    }
}

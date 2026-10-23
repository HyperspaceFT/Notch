import NotchKit
import NotchUI
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
        // panel collapses, so no feed downloads while the island is closed. It
        // starts over when the source changes, so a feed newly included is
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
                                isWide: isWide
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

/// One event: a bar in its calendar's color, the title, and the time.
private struct EntryRow: View {
    let entry: AgendaEntry
    let time: String
    let isWide: Bool

    /// Wide enough for "Now · until 10:30" and "进行中 · 至 10:30".
    private static let timeColumnWidth: CGFloat = 108

    var body: some View {
        let event = entry.event
        Group {
            if isWide {
                HStack(spacing: 8) {
                    bar(event.color.color)
                        .frame(height: 14)
                    timeText
                        .frame(width: Self.timeColumnWidth, alignment: .leading)
                    HStack(spacing: 6) {
                        titleText
                            .layoutPriority(1)
                        if let location = event.location {
                            Text(location)
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
                    }
                    Spacer(minLength: 0)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func bar(_ color: Color) -> some View {
        Capsule()
            .fill(color)
            .frame(width: 3)
    }

    private var titleText: some View {
        let title = entry.event.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return Text(title.isEmpty ? localized(en: "No Title", zh: "无标题") : title)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(NotchTheme.primaryText)
            .lineLimit(1)
    }

    private var timeText: some View {
        Text(time)
            .font(.system(size: 10.5))
            .foregroundStyle(NotchTheme.secondaryText)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.8)
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

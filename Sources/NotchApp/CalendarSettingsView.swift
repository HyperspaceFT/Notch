import AppKit
import CalendarFeature
import NotchKit
import Observation
import SwiftUI

/// The Calendar pane: which events (the Calendar app's, the feeds', or both)
/// and how many days the Home calendar module shows, when event reminders
/// show, which of the Calendar app's calendars, and the subscribed calendar
/// feeds. Taller than the window allows, the form scrolls.
struct CalendarSettingsView: View {
    @Bindable var settings: CalendarSettings
    let local: LocalCalendars
    let feeds: SubscriptionFeeds

    /// What the add row holds. Created with the pane, which the window keeps
    /// (`@State` needs a macro plugin the Command Line Tools do not ship).
    private let draft = SubscriptionDraft()

    /// The pane's tallest; with many calendars the form scrolls past it.
    private static let maximumHeight: CGFloat = 620

    var body: some View {
        Form {
            daysSection
            remindersSection
            calendarAppSection
            subscriptionsSection
        }
        .formStyle(.grouped)
        .frame(width: 420)
        // The ideal height is the whole form's, capped so the window stays on screen.
        .frame(maxHeight: Self.maximumHeight)
        .onAppear {
            local.refreshAccess()
            feeds.refreshIfNeeded()
        }
        // Coming back from System Settings, where Calendars access may have changed.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            local.refreshAccess()
        }
    }

    // MARK: Days

    private var daysSection: some View {
        Section {
            Picker(localized(en: "Show", zh: "显示"), selection: $settings.source) {
                ForEach(CalendarSource.allCases, id: \.self) { source in
                    Text(source.title).tag(source)
                }
            }
            .pickerStyle(.segmented)
            Stepper(value: $settings.dayCount, in: CalendarSettings.dayCountRange) {
                let count = settings.dayCount
                Text(count == 1
                    ? localized(en: "Show 1 day", zh: "显示 1 天")
                    : localized(en: "Show \(count) days", zh: "显示 \(count) 天"))
                    .monospacedDigit()
            }
        } header: {
            Text(localized(en: "Days", zh: "天数"))
        } footer: {
            footnote(localized(
                en: "Today counts as the first day.",
                zh: "今天算作第一天。"
            ))
        }
    }

    // MARK: Reminders

    private var remindersSection: some View {
        Section {
            Picker(localized(en: "Event Reminders", zh: "日程提醒"), selection: $settings.reminderLead) {
                ForEach(EventReminderLead.allCases, id: \.self) { lead in
                    Text(lead.title).tag(lead)
                }
            }
        } footer: {
            footnote(localized(
                en: "Shown beside the notch before an event starts. While reminders are on, subscribed calendars also update every 30 minutes with the island closed.",
                zh: "在日程开始前，于刘海两侧提醒；打开提醒后，订阅链接的日程在岛收起时也会每 30 分钟更新一次。"
            ))
        }
    }

    // MARK: Calendar app

    private var calendarAppSection: some View {
        Section {
            switch local.access {
            case .notDetermined:
                Text(localized(
                    en: "Notch can show events from the Calendar app once you allow it.",
                    zh: "允许后，Notch 可以显示「日历」App 中的日程。"
                ))
                Button(localized(en: "Allow Access…", zh: "允许访问…")) {
                    local.requestAccess()
                }
            case .denied:
                Text(localized(
                    en: "Allow Notch in System Settings → Privacy & Security → Calendars.",
                    zh: "请在「系统设置 → 隐私与安全性 → 日历」中允许 Notch。"
                ))
                Button(localized(en: "Open Privacy Settings…", zh: "打开隐私设置…")) {
                    local.openPrivacySettings()
                }
            case .granted:
                if local.calendars.isEmpty {
                    Text(localized(en: "No calendars", zh: "没有日历"))
                        .foregroundStyle(.secondary)
                }
                ForEach(sources, id: \.self) { source in
                    Text(source.isEmpty ? localized(en: "Other", zh: "其他") : source)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(local.calendars.filter { $0.sourceTitle == source }) { calendar in
                        Toggle(isOn: shownBinding(calendar.id)) {
                            HStack(spacing: 8) {
                                ColorDot(color: calendar.color)
                                Text(calendar.title)
                            }
                        }
                        .toggleStyle(.switch)
                    }
                }
            }
        } header: {
            Text(localized(en: "Calendar App", zh: "「日历」App"))
        } footer: {
            footnote(localized(
                en: "Accounts added in System Settings → Internet Accounts, such as Google or Exchange, also appear here.",
                zh: "在「系统设置 → 互联网账户」中添加的账户（如 Google 或 Exchange）也会出现在这里。"
            ))
        }
    }

    /// Account titles in the calendars' order.
    private var sources: [String] {
        var seen = Set<String>()
        return local.calendars.map(\.sourceTitle).filter { seen.insert($0).inserted }
    }

    private func shownBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { settings.isCalendarShown(id) },
            set: { settings.setCalendar(id, shown: $0) }
        )
    }

    // MARK: Subscriptions

    private var subscriptionsSection: some View {
        Section {
            ForEach(settings.subscriptions) { subscription in
                SubscriptionRow(settings: settings, feeds: feeds, subscription: subscription)
            }
            AddSubscriptionRow(settings: settings, feeds: feeds, draft: draft)
            HStack {
                Spacer()
                Button(localized(en: "Refresh Now", zh: "立即刷新")) {
                    feeds.refreshNow()
                }
                .disabled(!settings.subscriptions.contains(where: \.isEnabled))
            }
        } header: {
            Text(localized(en: "Subscriptions", zh: "订阅"))
        } footer: {
            footnote(localized(
                en: "Google Calendar: Settings → the calendar → Integrate calendar → Secret address in iCal format. Outlook: Settings → Calendar → Shared calendars → Publish a calendar → ICS link. Anyone with the link can read the calendar; Notch keeps it on this Mac only.",
                zh: "Google 日历：设置 → 选择日历 → 集成日历 → iCal 格式的私密地址。Outlook：设置 → 日历 → 共享日历 → 发布日历 → ICS 链接。任何拿到链接的人都能读取该日历；Notch 只把它保存在这台 Mac 上。"
            ))
        }
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
    }
}

/// One subscription: its color, name, host and status, a switch, and a remove button.
private struct SubscriptionRow: View {
    let settings: CalendarSettings
    let feeds: SubscriptionFeeds
    let subscription: CalendarSubscription

    var body: some View {
        let status = feeds.status(of: subscription.id)
        HStack(spacing: 10) {
            ColorDot(color: subscription.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(subscription.displayName(feedName: status.feedName))
                    .lineLimit(1)
                // Only the host: the rest of the address is the calendar's password.
                Text("\(subscription.displayHost) · \(statusText(status))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Toggle(localized(en: "Show", zh: "显示"), isOn: Binding(
                get: { subscription.isEnabled },
                set: { enabled in
                    settings.setSubscription(id: subscription.id, enabled: enabled)
                    feeds.refreshIfNeeded()
                }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .controlSize(.small)
            Button(role: .destructive) {
                settings.removeSubscription(id: subscription.id)
                // Drops what the feeds keep for it.
                feeds.refreshIfNeeded()
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .help(localized(en: "Remove", zh: "移除"))
        }
    }

    private func statusText(_ status: SubscriptionFeeds.Status) -> String {
        if status.isUpdating {
            return localized(en: "Updating…", zh: "正在更新…")
        }
        if let error = status.errorText {
            return localized(en: "Couldn't update: \(error)", zh: "无法更新：\(error)")
        }
        if let updated = status.lastUpdated {
            let parts = Calendar.current.dateComponents([.hour, .minute], from: updated)
            let time = String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
            return localized(en: "Updated \(time)", zh: "\(time) 已更新")
        }
        return localized(en: "Not updated yet", zh: "尚未更新")
    }
}

/// The name and address being typed into the add row.
@MainActor
@Observable
private final class SubscriptionDraft {
    var name = ""
    var address = ""
}

/// An optional name and the feed's address, added once the address is valid and new.
private struct AddSubscriptionRow: View {
    let settings: CalendarSettings
    let feeds: SubscriptionFeeds
    @Bindable var draft: SubscriptionDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField(
                localized(en: "Name", zh: "名称"),
                text: $draft.name,
                prompt: Text(localized(en: "Optional", zh: "可选"))
            )
            HStack {
                TextField(
                    localized(en: "Address", zh: "地址"),
                    text: $draft.address,
                    prompt: Text(localized(en: "https://… or webcal://…", zh: "https://… 或 webcal://…"))
                )
                .onSubmit(add)
                Button(localized(en: "Add", zh: "添加"), action: add)
                    .disabled(!settings.canAddSubscription(address: draft.address))
            }
        }
    }

    private func add() {
        guard settings.addSubscription(name: draft.name, address: draft.address) else { return }
        draft.name = ""
        draft.address = ""
        feeds.refreshIfNeeded()
    }
}

private struct ColorDot: View {
    let color: Color

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 10, height: 10)
    }
}

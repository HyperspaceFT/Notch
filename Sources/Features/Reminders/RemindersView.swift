import NotchKit
import NotchUI
import Observation
import SwiftUI

/// The reminders module at the size Home gives it: a field to add one, then
/// the incomplete reminders of every list. From
/// `wideThreshold` on, a reminder's due date sits on its title's line; below
/// it, under the title.
struct RemindersView: View {
    let store: RemindersStore
    let state: RemindersCardState
    let size: CGSize

    static let wideThreshold: CGFloat = 260
    /// How often the card checks whether access changed in System Settings.
    static let checkInterval: Duration = .seconds(60)

    var body: some View {
        // Redrawn every minute, so due dates roll over and turn overdue.
        TimelineView(.everyMinute) { context in
            // Tinted by the list of the first reminder listed.
            NotchCard(tint: store.items.first?.color.color) {
                content(now: context.date)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(width: size.width, height: size.height)
        // Never asks for access by itself, unlike the calendar module: that one
        // already prompts on the first expand, and two system prompts at once
        // would be confusing. Only the card's "Allow" asks.
        .task {
            while !Task.isCancelled {
                store.refreshAccess()
                store.fetchIfNeeded()
                try? await Task.sleep(for: Self.checkInterval)
            }
        }
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        switch store.access {
        case .notDetermined:
            centered {
                StatusLine(symbol: "checklist") {
                    localized(en: "Show your reminders here", zh: "在这里显示你的提醒事项")
                }
                GlassCapsuleButton(localized(en: "Allow", zh: "允许"), symbol: "checkmark") {
                    store.requestAccess()
                }
            }
        case .denied:
            centered {
                StatusLine(symbol: "exclamationmark.triangle") {
                    localized(en: "Reminders access needed", zh: "需要提醒事项权限")
                }
                GlassCapsuleButton(localized(en: "Open Settings", zh: "打开设置"), symbol: "gear") {
                    store.openPrivacySettings()
                }
            }
        case .granted:
            VStack(alignment: .leading, spacing: 8) {
                ReminderInputRow { text in
                    guard let id = store.add(title: text) else { return false }
                    state.scrollTarget = id
                    return true
                }
                if store.items.isEmpty {
                    // Only once a fetch has delivered; before that the list is not known to be empty.
                    if store.hasFetched {
                        centered {
                            StatusLine(symbol: "checkmark.circle") {
                                localized(en: "No reminders", zh: "没有待办的提醒事项")
                            }
                        }
                    }
                } else {
                    RemindersList(
                        store: store,
                        state: state,
                        now: now,
                        isWide: size.width >= Self.wideThreshold
                    )
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

/// One card's own view state, owned by whoever creates the card rather than the
/// view (`@State` needs a macro plugin the Command Line Tools do not ship).
@MainActor
@Observable
final class RemindersCardState {
    /// A reminder this card added, to scroll to once a fetch lists it.
    var scrollTarget: String?
}

/// The "+" icon and the field that adds a reminder on Return.
private struct ReminderInputRow: View {
    let submit: (String) -> Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "plus.circle")
                .font(.system(size: 13))
                .foregroundStyle(NotchTheme.secondaryText)
                .frame(width: 14, height: 14)
            ReminderInputField(
                placeholder: localized(en: "New Reminder", zh: "新提醒事项"),
                onSubmit: submit
            )
            .frame(height: 16)
        }
    }
}

/// The reminders, scrolling, with a fade where the card cuts them off.
private struct RemindersList: View {
    let store: RemindersStore
    let state: RemindersCardState
    let now: Date
    let isWide: Bool

    /// Height of the fade at the bottom, where a list longer than the card is cut off.
    private static let fadeHeight: CGFloat = 14

    var body: some View {
        let language = Localization.shared.language
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(store.items) { item in
                        ReminderRow(
                            item: item,
                            isPending: store.completions.isPending(item.id),
                            isWide: isWide,
                            now: now,
                            language: language,
                            toggle: { store.completions.toggle(item.id) }
                        )
                        .id(item.id)
                        .contextMenu {
                            Button(localized(en: "Open in Reminders", zh: "在「提醒事项」中打开")) {
                                store.openRemindersApp()
                            }
                            Button(localized(en: "Delete", zh: "删除"), role: .destructive) {
                                store.delete(item.id)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // Room to scroll the last reminder clear of the fade.
                .padding(.bottom, Self.fadeHeight)
            }
            .scrollIndicators(.hidden)
            // Reminders cut off at the bottom fade out instead of ending at a hard edge.
            .mask {
                VStack(spacing: 0) {
                    Color.black
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: Self.fadeHeight)
                }
            }
            .onAppear { scrollToTarget(proxy) }
            .onChange(of: store.items) { scrollToTarget(proxy) }
            .onChange(of: state.scrollTarget) { scrollToTarget(proxy) }
        }
    }

    /// Scrolls to the reminder this card added once the list has it.
    private func scrollToTarget(_ proxy: ScrollViewProxy) {
        guard let target = state.scrollTarget, store.items.contains(where: { $0.id == target }) else { return }
        state.scrollTarget = nil
        withAnimation(.snappy(duration: 0.25)) {
            proxy.scrollTo(target)
        }
    }
}

/// One reminder: a circle in its list's color that ticks it off, its title, and
/// when it is due.
private struct ReminderRow: View {
    let item: ReminderItem
    let isPending: Bool
    let isWide: Bool
    let now: Date
    let language: AppLanguage
    let toggle: () -> Void

    /// A warm red for overdue dates, readable on the dark card.
    private static let overdueColor = Color(red: 1, green: 0.42, blue: 0.36)

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            CompletionCircle(color: item.color.color, isPending: isPending, action: toggle)
                .padding(.top, 1)
            if isWide {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    title
                    Spacer(minLength: 0)
                    dueLabel
                }
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    title
                    dueLabel
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
    }

    private var title: some View {
        Text(item.title.isEmpty ? localized(en: "New Reminder", zh: "新提醒事项") : item.title)
            .font(.system(size: 12))
            .strikethrough(isPending)
            .foregroundStyle(isPending || item.title.isEmpty ? NotchTheme.secondaryText : NotchTheme.primaryText)
            .lineLimit(1)
    }

    @ViewBuilder
    private var dueLabel: some View {
        if let due = item.due {
            let calendar = Calendar.current
            Text(due.label(now: now, language: language, calendar: calendar))
                .font(.system(size: 10))
                .monospacedDigit()
                .foregroundStyle(due.isOverdue(now: now, calendar: calendar) ? Self.overdueColor : NotchTheme.secondaryText)
                .lineLimit(1)
                .fixedSize()
        }
    }
}

/// The 14 pt circle that ticks a reminder off: an outline, or filled with a
/// checkmark while the completion waits to be written.
private struct CompletionCircle: View {
    let color: Color
    let isPending: Bool
    let action: () -> Void

    var body: some View {
        let label = isPending
            ? localized(en: "Mark as Not Completed", zh: "标为未完成")
            : localized(en: "Mark as Completed", zh: "标为已完成")
        Button(action: action) {
            ZStack {
                if isPending {
                    Circle()
                        .fill(color)
                    Image(systemName: "checkmark")
                        .font(.system(size: 7.5, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.8))
                } else {
                    Circle()
                        .strokeBorder(color, lineWidth: 1.5)
                }
            }
            .frame(width: 14, height: 14)
            .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}

/// An icon over a short line, for the states without reminders.
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

extension ReminderColor {
    var color: Color { Color(red: red, green: green, blue: blue) }
}

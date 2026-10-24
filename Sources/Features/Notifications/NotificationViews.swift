import AppKit
import NotchKit
import NotchUI
import SwiftUI

/// Space kept between a wing's content and the island's outer edge, so it stays
/// clear of the rounded bottom corner (`NotchTheme.activityBottomRadius`).
private let wingCornerClearance: CGFloat = 12
/// Space between a wing's content and the notch.
private let wingNotchClearance: CGFloat = 6

/// The notification wings' widths, each fitted to its own content, as the wings
/// draw it: the app's icon and name on the left, the longer of the two text lines
/// on the right. Neither grows past `maximumWidth`, where the text is cut short.
enum NotificationWings {
    static let maximumWidth: CGFloat = 120
    /// The right wing's least width, so a one-word line does not pinch the island.
    static let minimumTrailingWidth: CGFloat = 52
    static let iconSide: CGFloat = 20
    static let iconSpacing: CGFloat = 6
    static let nameSize: CGFloat = 11
    static let headlineSize: CGFloat = 12
    static let detailSize: CGFloat = 10

    static func widths(for item: NotificationItem) -> (leading: CGFloat, trailing: CGFloat) {
        let name = width(of: item.appName, in: .systemFont(ofSize: nameSize, weight: .medium))
        let leading = wingCornerClearance + iconSide + (name > 0 ? iconSpacing + name : 0) + wingNotchClearance
        let summary = item.summary
        let text = max(
            width(of: summary.headline, in: .systemFont(ofSize: headlineSize, weight: .semibold)),
            width(of: summary.detail, in: .systemFont(ofSize: detailSize))
        )
        let trailing = wingNotchClearance + text + wingCornerClearance
        return (min(leading, maximumWidth), min(max(trailing, minimumTrailingWidth), maximumWidth))
    }

    /// Rounded up with a point to spare, so a line that just fits is not cut short
    /// where SwiftUI lays it out on whole pixels.
    private static func width(of text: String?, in font: NSFont) -> CGFloat {
        guard let text, !text.isEmpty else { return 0 }
        return ceil((text as NSString).size(withAttributes: [.font: font]).width) + 1
    }
}

/// How far a wing's content moves while the island is hovered: half the ring it
/// grows by, outward (`outward` is -1 for the left wing, 1 for the right) and
/// down, so it keeps its place in the grown outline.
private func wingHoverOffset(isHovered: Bool, outward: CGFloat) -> CGSize {
    guard isHovered else { return .zero }
    return CGSize(width: NotchTheme.hoverGrowth.width / 2 * outward, height: NotchTheme.hoverGrowth.height / 2)
}

/// Left wing: the app's icon and name, next to the notch (`NotificationWings`
/// sizes it). A click opens the island on the whole notification.
struct NotificationWingLeading: View {
    let item: NotificationItem
    let inbox: NotificationInbox
    let apps: NotificationAppResolver
    let open: @MainActor () -> Void
    @Environment(\.notchIsHovered) private var isIslandHovered

    var body: some View {
        // The listed copy, once a slow lookup has found the app's icon.
        let shown = inbox.item(id: item.id) ?? item
        Button(action: open) {
            ZStack(alignment: .trailing) {
                HStack(spacing: NotificationWings.iconSpacing) {
                    NotificationAppIcon(image: apps.icon(for: shown.appURL), side: NotificationWings.iconSide)
                    Text(shown.appName ?? "")
                        .font(.system(size: NotificationWings.nameSize, weight: .medium))
                        .foregroundStyle(NotchTheme.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                // Every banner presents the same activity, so the shell keeps these
                // wings and only their item changes: a notification that takes over
                // from one still showing blurs in, as a new activity replacing
                // another does.
                .id(item.id)
                .transition(.blurReplace)
            }
            .animation(NotchTheme.activityAnimation, value: item.id)
            // An offset, not padding: the text keeps its width. The island's
            // hover animation carries the move.
            .offset(wingHoverOffset(isHovered: isIslandHovered, outward: -1))
            .padding(.leading, wingCornerClearance)
            .padding(.trailing, wingNotchClearance)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(shown.appName ?? localized(en: "Notification", zh: "通知"))
    }
}

/// Right wing: the title over the body (or subtitle), a line each. A click opens
/// the island on the whole notification.
struct NotificationWingTrailing: View {
    let item: NotificationItem
    let inbox: NotificationInbox
    let open: @MainActor () -> Void
    @Environment(\.notchIsHovered) private var isIslandHovered

    var body: some View {
        let summary = (inbox.item(id: item.id) ?? item).summary
        Button(action: open) {
            ZStack(alignment: .leading) {
                VStack(alignment: .leading, spacing: 1) {
                    if let headline = summary.headline {
                        Text(headline)
                            .font(.system(size: NotificationWings.headlineSize, weight: .semibold))
                            .foregroundStyle(NotchTheme.primaryText)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    if let detail = summary.detail {
                        Text(detail)
                            .font(.system(size: NotificationWings.detailSize))
                            .foregroundStyle(NotchTheme.secondaryText)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                // Blurs in over the one it replaces, like the left wing.
                .id(item.id)
                .transition(.blurReplace)
            }
            .animation(NotchTheme.activityAnimation, value: item.id)
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

/// An app's icon at `side`, or a generic app symbol while the app is not known.
private struct NotificationAppIcon: View {
    let image: NSImage?
    let side: CGFloat

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "app.badge")
                    .font(.system(size: side * 0.7))
                    .foregroundStyle(NotchTheme.secondaryText)
            }
        }
        .frame(width: side, height: side)
    }
}

/// The Notifications tab: how many there are and a button that clears them,
/// then the notifications, newest first. A click on one brings its app forward
/// and, when there was an app to open, takes it off the list.
struct NotificationsTabView: View {
    let inbox: NotificationInbox
    let apps: NotificationAppResolver
    let open: @MainActor (NotificationItem) -> Void

    /// Height of the fade at the bottom, where a list longer than the card is cut off.
    private static let fadeHeight: CGFloat = 14

    var body: some View {
        NotchCard {
            VStack(alignment: .leading, spacing: 6) {
                header
                list
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(countLabel)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(NotchTheme.secondaryText)
                .lineLimit(1)
            Spacer(minLength: 8)
            GlassCapsuleButton(localized(en: "Clear All", zh: "全部清除"), symbol: "xmark") {
                inbox.removeAll()
            }
        }
    }

    private var countLabel: String {
        let count = inbox.items.count
        return localized(
            en: count == 1 ? "1 Notification" : "\(count) Notifications",
            zh: "\(count) 条通知"
        )
    }

    private var list: some View {
        // Redrawn every minute, so "now" turns into "1 min. ago" and onwards.
        TimelineView(.everyMinute) { context in
            let language = Localization.shared.language
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(inbox.items) { item in
                        if item.id != inbox.items.first?.id {
                            Rectangle()
                                .fill(Color.white.opacity(0.1))
                                .frame(height: 1)
                                .padding(.vertical, 6)
                        }
                        NotificationRow(
                            item: item,
                            icon: apps.icon(for: item.appURL),
                            received: NotificationFormat.relative(item.received, now: context.date, language: language),
                            open: { open(item) }
                        )
                        .contextMenu {
                            Button(localized(en: "Open App", zh: "打开 App")) {
                                open(item)
                            }
                            Button(localized(en: "Remove", zh: "移除"), role: .destructive) {
                                inbox.remove(id: item.id)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // Room to scroll the last notification clear of the fade.
                .padding(.bottom, Self.fadeHeight)
            }
            .scrollIndicators(.hidden)
            // Notifications cut off at the bottom fade out instead of ending at a hard edge.
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

/// One notification in full, opened from its activity: a card with its app's
/// icon, name, and when it arrived, and one with its title, subtitle, and whole
/// body, which scrolls when it does not fit. Display only.
struct NotificationDetailView: View {
    let item: NotificationItem
    let inbox: NotificationInbox
    let apps: NotificationAppResolver

    private static let sourceWidth: CGFloat = 150
    /// Height of the fade at the bottom, where text longer than the card is cut off.
    private static let fadeHeight: CGFloat = 14

    var body: some View {
        // The listed copy, once a slow lookup has found the app's icon; the item
        // itself once it has left the list.
        let shown = inbox.item(id: item.id) ?? item
        HStack(spacing: 10) {
            NotchCard {
                source(shown)
            }
            .frame(width: Self.sourceWidth)
            NotchCard {
                message(shown)
            }
        }
    }

    private func source(_ item: NotificationItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            NotificationAppIcon(image: apps.icon(for: item.appURL), side: 40)
            if let appName = item.appName {
                Text(appName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(NotchTheme.primaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            // Redrawn every minute, like the tab's list.
            TimelineView(.everyMinute) { context in
                Text(NotificationFormat.relative(item.received, now: context.date, language: Localization.shared.language))
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .foregroundStyle(NotchTheme.secondaryText)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func message(_ item: NotificationItem) -> some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 2) {
                if let title = item.title {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(NotchTheme.primaryText)
                }
                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(NotchTheme.primaryText)
                }
                if let body = item.body {
                    Text(body)
                        .font(.system(size: 11))
                        .foregroundStyle(NotchTheme.secondaryText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // Room to scroll the last line clear of the fade.
            .padding(.bottom, Self.fadeHeight)
        }
        .scrollIndicators(.hidden)
        // Text cut off at the bottom fades out instead of ending at a hard edge,
        // as in the tab's list.
        .mask {
            VStack(spacing: 0) {
                Color.black
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: Self.fadeHeight)
            }
        }
    }
}

/// One notification: its app's icon, name, and when it arrived, then its title,
/// subtitle, and up to three lines of its body.
private struct NotificationRow: View {
    let item: NotificationItem
    let icon: NSImage?
    let received: String
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(alignment: .top, spacing: 8) {
                NotificationAppIcon(image: icon, side: 22)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(item.appName ?? "")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(NotchTheme.secondaryText)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Text(received)
                            .font(.system(size: 10))
                            .monospacedDigit()
                            .foregroundStyle(NotchTheme.secondaryText)
                            .lineLimit(1)
                            .fixedSize()
                    }
                    if let title = item.title {
                        Text(title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(NotchTheme.primaryText)
                            .lineLimit(1)
                    }
                    if let subtitle = item.subtitle {
                        Text(subtitle)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(NotchTheme.primaryText)
                            .lineLimit(1)
                    }
                    if let body = item.body {
                        Text(body)
                            .font(.system(size: 11))
                            .foregroundStyle(NotchTheme.secondaryText)
                            .lineLimit(3)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

/// When a notification arrived, in a given language.
enum NotificationFormat {
    /// "now" / "刚刚" within the first minute, then "5 min. ago" / "5分钟前" and so on.
    static func relative(_ date: Date, now: Date, language: AppLanguage) -> String {
        if now.timeIntervalSince(date) < 60 {
            return language == .english ? "now" : "刚刚"
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: language.rawValue)
        formatter.unitsStyle = .abbreviated
        formatter.dateTimeStyle = .numeric
        return formatter.localizedString(for: date, relativeTo: now)
    }
}

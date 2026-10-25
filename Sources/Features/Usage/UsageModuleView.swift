import NotchKit
import NotchUI
import Observation
import SwiftUI

/// What the pointer rests on in the Usage Home module: a provider's window
/// column, or its state symbol (`window == nil`).
struct UsageHoverTarget: Equatable {
    var provider: UsageProvider
    var window: Int?
}

/// The Home module's hover target, created once with the module rather than
/// by the view (`@State` needs a macro plugin the Command Line Tools do not ship).
@MainActor
@Observable
final class UsageModuleHover {
    var target: UsageHoverTarget?

    /// Clears the target on hover-out only if it is still `target`, so moving
    /// straight onto the next column does not clear that one's.
    func leave(_ target: UsageHoverTarget) {
        if self.target == target {
            self.target = nil
        }
    }
}

/// How the Usage Home module's groups fill its fixed width: one column width
/// for every window, the logos' size, and the gap between groups.
struct UsageModuleLayout: Equatable, Sendable {
    var columnWidth: CGFloat
    var logoSize: CGFloat
    var groupGap: CGFloat

    static let columnWidths: ClosedRange<CGFloat> = 4...12
    static let logoSizes: ClosedRange<CGFloat> = 9...12
    static let columnGap: CGFloat = 3
    static let groupGap: CGFloat = 6
    /// The narrowest the group gap may get, only when nothing fits otherwise.
    static let minimumGroupGap: CGFloat = 3
    /// From this column width on the percent shows above the bar.
    static let numberWidth: CGFloat = 11
    /// From this column width on the window's icon shows below the bar.
    static let iconWidth: CGFloat = 9

    var showsNumbers: Bool { columnWidth >= Self.numberWidth }
    var showsIcons: Bool { columnWidth >= Self.iconWidth }

    /// The groups' width at this layout, each at least as wide as its logo.
    static func width(columnCounts: [Int], columnWidth: CGFloat, logoSize: CGFloat, groupGap: CGFloat) -> CGFloat {
        let groups = columnCounts.reduce(CGFloat(0)) { total, count in
            let count = max(count, 1)
            return total + max(logoSize, CGFloat(count) * columnWidth + CGFloat(count - 1) * columnGap)
        }
        return groups + CGFloat(max(columnCounts.count - 1, 0)) * groupGap
    }

    /// The widest columns that fit `contentWidth`, with the 6-pt group gap and
    /// logos from 12 down to 9 pt first; only when nothing fits at the
    /// narrowest columns does the group gap shrink toward 3 pt. `columnCounts`
    /// holds each provider's window count, 1 for one shown as a state symbol.
    static func make(contentWidth: CGFloat, columnCounts: [Int]) -> UsageModuleLayout {
        let step: CGFloat = 0.25
        var gap = groupGap
        while gap >= minimumGroupGap {
            var logo = logoSizes.upperBound
            while logo >= logoSizes.lowerBound {
                var column = columnWidths.upperBound
                while column >= columnWidths.lowerBound {
                    if width(columnCounts: columnCounts, columnWidth: column, logoSize: logo, groupGap: gap) <= contentWidth + 0.001 {
                        return UsageModuleLayout(columnWidth: column, logoSize: logo, groupGap: gap)
                    }
                    column -= step
                }
                logo -= step
            }
            gap -= step
        }
        return UsageModuleLayout(
            columnWidth: columnWidths.lowerBound,
            logoSize: logoSizes.lowerBound,
            groupGap: minimumGroupGap
        )
    }
}

/// The Usage Home module, as wide as the providers the user shows need
/// (`width(for:)`, fixed, so it cannot be dragged): one group per displayed
/// provider, spread across the card, each its logo over a vertical bar per
/// window (the short window left, the weekly one right), with the percent above
/// each bar and the window's icon below. A Debug sample with more providers
/// than the width was made for still fits, its bars thinner and without those
/// (`UsageModuleLayout`). Hovering a bar shows the limit's name and when it
/// resets in a bubble over the card. A click opens the Usage tab.
struct UsageModuleView: View {
    let model: UsageModel
    let hover: UsageModuleHover
    let size: CGSize
    let openTab: @MainActor () -> Void

    /// The narrowest the module gets, so the bubble's words do not break mid-word.
    nonisolated static let minimumWidth: CGFloat = 68
    /// The gap between groups the width is made for.
    nonisolated static let widthGroupGap: CGFloat = 8

    /// The module's width for `providers`: their groups at 12-pt columns and
    /// logos, 3-pt column gaps and 8-pt group gaps, plus the card's padding, no
    /// narrower than `minimumWidth`. It counts each provider's expected windows,
    /// so the width does not change when the data arrives.
    nonisolated static func width(for providers: [UsageProvider]) -> CGFloat {
        let column = UsageModuleLayout.columnWidths.upperBound
        let logo = UsageModuleLayout.logoSizes.upperBound
        let groups = providers.reduce(CGFloat(0)) { total, provider in
            let count = CGFloat(provider.expectedWindowCount)
            return total + max(logo, count * column + (count - 1) * UsageModuleLayout.columnGap)
        }
        let content = groups + CGFloat(max(providers.count - 1, 0)) * widthGroupGap
        return max(minimumWidth, content + cardPadding * 2)
    }

    /// Fixed at the width the user's own choice of providers needs. It reads
    /// the settings, never a Debug sample, so a sample cannot change the saved
    /// Home layout.
    @MainActor
    static func sizing(settings: UsageSettings) -> HomeModuleSizing {
        .fixed(.points(width(for: settings.shownProviders)))
    }
    /// The card's padding on each side (`NotchCard`).
    nonisolated static let cardPadding: CGFloat = 12

    var body: some View {
        Button(action: openTab) {
            // Redrawn every minute, so the reset times count down.
            TimelineView(.everyMinute) { context in
                let level = model.worstLevel
                NotchCard(tint: level == .normal ? nil : level.color) {
                    content
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .overlay(alignment: .top) {
                    bubble(now: context.date)
                        .padding(4)
                        .allowsHitTesting(false)
                        .animation(.smooth(duration: 0.15), value: hover.target)
                }
            }
        }
        .buttonStyle(.plain)
        .contentShape(.rect)
        .frame(width: size.width, height: size.height)
        .modifier(UsageRefreshLoop(model: model))
    }

    @ViewBuilder
    private var content: some View {
        let providers = model.displayedProviders
        if providers.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "gauge.with.needle")
                    .font(.system(size: 18))
                    .foregroundStyle(NotchTheme.secondaryText)
                Text(localized(en: "Choose AIs under Settings → Usage.", zh: "在「设置 → 用量」中选择要显示的 AI。"))
                    .font(.system(size: 10))
                    .foregroundStyle(NotchTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.8)
            }
        } else {
            let layout = UsageModuleLayout.make(
                contentWidth: size.width - Self.cardPadding * 2,
                columnCounts: providers.map { max(model.status(of: $0).report?.windows.count ?? 1, 1) }
            )
            HStack(alignment: .top, spacing: 0) {
                Spacer(minLength: 0)
                ForEach(providers.indices, id: \.self) { index in
                    if index > 0 {
                        Spacer(minLength: layout.groupGap)
                    }
                    ProviderGroup(model: model, hover: hover, provider: providers[index], layout: layout)
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: Hover bubble

    /// The limit's name and when it resets, or the provider and its state:
    /// never truncated, wrapping onto more lines as the card's width needs.
    @ViewBuilder
    private func bubble(now: Date) -> some View {
        if let target = hover.target, model.displayedProviders.contains(target.provider) {
            let status = model.status(of: target.provider)
            let (title, detail) = bubbleLines(target, status: status, now: now)
            VStack(spacing: 2) {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(NotchTheme.primaryText)
                if let detail {
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundStyle(NotchTheme.secondaryText)
                        .monospacedDigit()
                }
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(6)
            .frame(maxWidth: .infinity)
            .background {
                let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
                shape.fill(.black.opacity(0.85))
                    .overlay { shape.strokeBorder(.white.opacity(0.15), lineWidth: 1) }
            }
            .transition(.opacity)
        }
    }

    private func bubbleLines(_ target: UsageHoverTarget, status: UsageStatus, now: Date) -> (String, String?) {
        if let index = target.window, let window = status.report?.windows[safe: index] {
            return (UsageFormat.limitName(window.duration), window.resetsAt.map { UsageFormat.resetText($0, now: now) })
        }
        let state = switch status.state {
        case .loading, .ok: localized(en: "Loading…", zh: "正在读取…")
        default: UsageFormat.stateTitle(status.state) ?? ""
        }
        return (target.provider.displayName, state)
    }
}

/// One provider: its logo over its window columns, or over a state symbol.
private struct ProviderGroup: View {
    let model: UsageModel
    let hover: UsageModuleHover
    let provider: UsageProvider
    let layout: UsageModuleLayout

    var body: some View {
        let status = model.status(of: provider)
        VStack(spacing: 4) {
            UsageProviderLogo(provider: provider, size: layout.logoSize)
            if let report = status.report, !report.windows.isEmpty {
                HStack(alignment: .bottom, spacing: UsageModuleLayout.columnGap) {
                    ForEach(report.windows.indices, id: \.self) { index in
                        WindowColumn(
                            window: report.windows[index],
                            provider: provider,
                            layout: layout,
                            target: UsageHoverTarget(provider: provider, window: index),
                            hover: hover
                        )
                    }
                }
            } else {
                stateSymbol(status.state)
                    .frame(width: layout.logoSize)
                    .frame(maxHeight: .infinity)
                    .contentShape(.rect)
                    .onHover { inside in
                        let target = UsageHoverTarget(provider: provider, window: nil)
                        if inside { hover.target = target } else { hover.leave(target) }
                    }
            }
        }
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private func stateSymbol(_ state: UsageStatus.State) -> some View {
        let symbol: String? = switch state {
        case .loading, .ok: nil
        case .signedOut: "person.crop.circle.badge.questionmark"
        case .needsVerification: "checkmark.shield"
        case .failed: "exclamationmark.triangle"
        }
        if let symbol {
            Image(systemName: symbol)
                .font(.system(size: 11))
                .foregroundStyle(NotchTheme.secondaryText)
        } else {
            ProgressView()
                .controlSize(.mini)
        }
    }
}

/// One window: the percent and the window's icon when there is room
/// (`UsageModuleLayout`), and a bar filled from the bottom.
private struct WindowColumn: View {
    let window: UsageWindow
    let provider: UsageProvider
    let layout: UsageModuleLayout
    let target: UsageHoverTarget
    let hover: UsageModuleHover

    var body: some View {
        let isHovered = hover.target == target
        let width = layout.columnWidth
        VStack(spacing: 3) {
            if layout.showsNumbers {
                Text("\(Int(window.percent.rounded()))")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(UsageLevel(percent: window.percent).color ?? NotchTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(width: width)
            }
            VerticalUsageBar(percent: window.percent, provider: provider)
                .frame(width: width)
                .frame(maxHeight: .infinity)
            if layout.showsIcons {
                UsageWindowIcon(
                    duration: window.duration,
                    size: min(10, width),
                    color: isHovered ? NotchTheme.primaryText : NotchTheme.secondaryText
                )
            }
        }
        .contentShape(.rect)
        .onHover { inside in
            if inside { hover.target = target } else { hover.leave(target) }
        }
    }
}

/// A vertical capsule filled from the bottom to `percent` (at most 100): the
/// provider's color, or yellow and red from 70% and 90%.
private struct VerticalUsageBar: View {
    let percent: Double
    let provider: UsageProvider

    var body: some View {
        let fraction = min(max(percent / 100, 0), 1)
        Capsule()
            .fill(.white.opacity(0.14))
            .overlay(alignment: .bottom) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(fill)
                        .frame(height: proxy.size.height * fraction)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
            }
            .clipShape(.capsule)
    }

    private var fill: AnyShapeStyle {
        if let color = UsageLevel(percent: percent).color { return AnyShapeStyle(color) }
        return NotchTheme.accent(provider.accentColor)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

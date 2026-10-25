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

/// The Usage Home module: one group per displayed provider, spread across the
/// card, each its logo over a vertical bar per window (the short window left,
/// the weekly one right) with the window's icon below and, when the columns
/// are wide enough, the percent above. Hovering a bar shows its details in a
/// bubble over the card. A click opens the Usage tab.
struct UsageModuleView: View {
    let model: UsageModel
    let hover: UsageModuleHover
    let size: CGSize
    let openTab: @MainActor () -> Void

    static let sizing = HomeModuleSizing.resizable(minimum: .points(100), maximum: .points(240))
    /// The card's padding on each side (`NotchCard`).
    static let cardPadding: CGFloat = 12
    static let groupGap: CGFloat = 8
    static let columnGap: CGFloat = 3
    static let barWidths: ClosedRange<CGFloat> = 7...12
    /// From this column width on the percent shows above the bar.
    static let numberWidth: CGFloat = 12

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
                        .padding(6)
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
            let columnWidth = columnWidth(for: providers)
            HStack(alignment: .top, spacing: 0) {
                Spacer(minLength: 0)
                ForEach(providers.indices, id: \.self) { index in
                    if index > 0 {
                        Spacer(minLength: Self.groupGap)
                    }
                    ProviderGroup(model: model, hover: hover, provider: providers[index], columnWidth: columnWidth)
                }
                Spacer(minLength: 0)
            }
        }
    }

    /// One width for every column: the widest within `barWidths` at which the
    /// groups (each at least as wide as its logo) and their gaps fit the card.
    private func columnWidth(for providers: [UsageProvider]) -> CGFloat {
        let counts = providers.map { model.status(of: $0).report?.windows.count ?? 0 }
        let available = size.width - Self.cardPadding * 2 - CGFloat(providers.count - 1) * Self.groupGap
        func needed(_ width: CGFloat) -> CGFloat {
            counts.reduce(0) { total, count in
                total + max(ProviderGroup.logoSize, CGFloat(count) * width + CGFloat(max(count - 1, 0)) * Self.columnGap)
            }
        }
        var width = Self.barWidths.upperBound
        while width > Self.barWidths.lowerBound, needed(width) > available {
            width -= 0.25
        }
        return max(width, Self.barWidths.lowerBound)
    }

    // MARK: Hover bubble

    @ViewBuilder
    private func bubble(now: Date) -> some View {
        if let target = hover.target, model.displayedProviders.contains(target.provider) {
            let status = model.status(of: target.provider)
            VStack(alignment: .leading, spacing: 3) {
                if let index = target.window, let window = status.report?.windows[safe: index] {
                    windowLines(window, provider: target.provider, now: now)
                } else {
                    stateLines(status.state, provider: target.provider)
                }
            }
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
                shape.fill(.black.opacity(0.85))
                    .overlay { shape.strokeBorder(.white.opacity(0.15), lineWidth: 1) }
            }
            .transition(.opacity)
        }
    }

    private func titleLine(_ provider: UsageProvider, _ text: String) -> some View {
        HStack(spacing: 4) {
            UsageProviderLogo(provider: provider, size: 10)
            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(NotchTheme.primaryText)
        }
    }

    @ViewBuilder
    private func windowLines(_ window: UsageWindow, provider: UsageProvider, now: Date) -> some View {
        titleLine(provider, "\(provider.displayName) · \(UsageFormat.windowLabel(window.duration))")
        let percent = Text("\(Int(window.percent.rounded()))%")
            .foregroundStyle(UsageLevel(percent: window.percent).color ?? NotchTheme.primaryText)
        Group {
            if let resetsAt = window.resetsAt {
                Text("\(percent) · \(UsageFormat.resetText(resetsAt, now: now))")
            } else {
                percent
            }
        }
        .font(.system(size: 10))
        .foregroundStyle(NotchTheme.secondaryText)
        .monospacedDigit()
        if !window.scoped.isEmpty {
            UsageScopedText.text(window.scoped, provider: provider)
                .font(.system(size: 10))
        }
    }

    @ViewBuilder
    private func stateLines(_ state: UsageStatus.State, provider: UsageProvider) -> some View {
        titleLine(provider, provider.displayName)
        let (title, hint): (String, String?) = switch state {
        case .loading, .ok: (localized(en: "Loading…", zh: "正在读取…"), nil)
        case .signedOut: (UsageFormat.stateTitle(state) ?? "", UsageFormat.signInHint())
        case .needsVerification: (UsageFormat.stateTitle(state) ?? "", UsageFormat.verificationHint())
        case .failed: (UsageFormat.stateTitle(state) ?? "", nil)
        }
        Text(title)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(NotchTheme.primaryText)
        if let hint {
            Text(hint)
                .font(.system(size: 10))
                .foregroundStyle(NotchTheme.secondaryText)
        }
    }
}

/// One provider: its logo over its window columns, or over a state symbol.
private struct ProviderGroup: View {
    let model: UsageModel
    let hover: UsageModuleHover
    let provider: UsageProvider
    let columnWidth: CGFloat

    static let logoSize: CGFloat = 12

    var body: some View {
        let status = model.status(of: provider)
        VStack(spacing: 4) {
            UsageProviderLogo(provider: provider, size: Self.logoSize)
            if let report = status.report, !report.windows.isEmpty {
                HStack(alignment: .bottom, spacing: UsageModuleView.columnGap) {
                    ForEach(report.windows.indices, id: \.self) { index in
                        WindowColumn(
                            window: report.windows[index],
                            provider: provider,
                            width: columnWidth,
                            target: UsageHoverTarget(provider: provider, window: index),
                            hover: hover
                        )
                    }
                }
            } else {
                stateSymbol(status.state)
                    .frame(width: Self.logoSize)
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

/// One window: the percent (when there is room), a bar filled from the bottom,
/// and the window's icon.
private struct WindowColumn: View {
    let window: UsageWindow
    let provider: UsageProvider
    let width: CGFloat
    let target: UsageHoverTarget
    let hover: UsageModuleHover

    var body: some View {
        let isHovered = hover.target == target
        VStack(spacing: 3) {
            if width >= UsageModuleView.numberWidth {
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
            UsageWindowIcon(
                duration: window.duration,
                size: 10,
                color: isHovered ? NotchTheme.primaryText : NotchTheme.secondaryText
            )
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

import NotchKit
import NotchUI
import SwiftUI

/// The Usage Home module: per displayed provider its glyph beside one thin line
/// per window (bar and percent), the short window above the weekly one. From
/// `detailWidth` on each line also shows the window's length and when it resets.
/// A click opens the Usage tab.
struct UsageModuleView: View {
    let model: UsageModel
    let size: CGSize
    let openTab: @MainActor () -> Void

    static let sizing = HomeModuleSizing.resizable(minimum: .points(100), maximum: .points(240))
    static let detailWidth: CGFloat = 170

    var body: some View {
        Button(action: openTab) {
            let level = model.worstLevel
            NotchCard(tint: level == .normal ? nil : level.color) {
                // Redrawn every minute, so the reset times count down.
                TimelineView(.everyMinute) { context in
                    content(now: context.date)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .buttonStyle(.plain)
        .contentShape(.rect)
        .frame(width: size.width, height: size.height)
        .modifier(UsageRefreshLoop(model: model))
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
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
            VStack(alignment: .leading, spacing: 0) {
                ForEach(providers.indices, id: \.self) { index in
                    if index > 0 {
                        Spacer(minLength: 4)
                    }
                    ProviderBlock(
                        model: model,
                        provider: providers[index],
                        showsDetail: size.width >= Self.detailWidth,
                        now: now
                    )
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
    }
}

/// One provider: the glyph, and its windows' lines or a one-word state.
private struct ProviderBlock: View {
    let model: UsageModel
    let provider: UsageProvider
    let showsDetail: Bool
    let now: Date

    var body: some View {
        let status = model.status(of: provider)
        HStack(alignment: .center, spacing: 6) {
            UsageGlyph(provider: provider, size: 10)
                .frame(width: 12)
            VStack(alignment: .leading, spacing: 3) {
                if let report = status.report, !report.windows.isEmpty {
                    ForEach(report.windows.indices, id: \.self) { index in
                        line(report.windows[index])
                    }
                } else {
                    stateLine(status.state)
                }
            }
        }
    }

    private func line(_ window: UsageWindow) -> some View {
        HStack(spacing: 4) {
            if showsDetail, let label = UsageFormat.compactWindowLabel(window.duration) {
                Text(label)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(NotchTheme.secondaryText)
                    .monospacedDigit()
                    .frame(width: 18, alignment: .leading)
            }
            UsageBar(percent: window.percent, provider: provider, height: 4)
            UsagePercent(percent: window.percent, size: 11, weight: .medium)
                .frame(minWidth: 28, alignment: .trailing)
            if showsDetail, let resetsAt = window.resetsAt {
                Text(UsageFormat.shortResetText(resetsAt, now: now))
                    .font(.system(size: 9))
                    .foregroundStyle(NotchTheme.secondaryText)
                    .monospacedDigit()
                    .lineLimit(1)
                    .frame(width: 34, alignment: .trailing)
            }
        }
    }

    @ViewBuilder
    private func stateLine(_ state: UsageStatus.State) -> some View {
        switch state {
        case .loading, .ok:
            ProgressView()
                .controlSize(.mini)
        case .signedOut:
            stateText(localized(en: "Sign in", zh: "未登录"))
        case .needsVerification:
            stateText(localized(en: "Verify", zh: "需验证"))
        case .failed:
            stateText(localized(en: "Error", zh: "出错"))
        }
    }

    private func stateText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(NotchTheme.secondaryText)
            .lineLimit(1)
    }
}

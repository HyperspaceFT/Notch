import NotchKit
import NotchUI
import SwiftUI

/// The Usage tab: one card per displayed provider, side by side at equal widths.
struct UsageTabView: View {
    let model: UsageModel

    static let cardSpacing: CGFloat = 10
    /// From this width a card lays its windows side by side; narrower, it stacks them.
    static let sideBySideWidth: CGFloat = 300

    var body: some View {
        GeometryReader { proxy in
            let providers = model.displayedProviders
            let count = CGFloat(max(providers.count, 1))
            let cardWidth = (proxy.size.width - Self.cardSpacing * (count - 1)) / count
            // Redrawn every minute, so the reset times count down.
            TimelineView(.everyMinute) { context in
                HStack(spacing: Self.cardSpacing) {
                    ForEach(providers, id: \.self) { provider in
                        UsageProviderCard(
                            model: model,
                            provider: provider,
                            sideBySide: cardWidth >= Self.sideBySideWidth,
                            now: context.date
                        )
                        .frame(width: max(cardWidth, 0))
                    }
                }
            }
        }
        .modifier(UsageRefreshLoop(model: model))
    }
}

/// One provider's card: its name and plan over its windows, or what keeps them
/// from showing.
private struct UsageProviderCard: View {
    let model: UsageModel
    let provider: UsageProvider
    let sideBySide: Bool
    let now: Date

    var body: some View {
        let status = model.status(of: provider)
        NotchCard {
            VStack(alignment: .leading, spacing: 6) {
                header(status)
                if let report = status.report {
                    windows(report)
                } else {
                    stateView(status.state)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    private func header(_ status: UsageStatus) -> some View {
        HStack(spacing: 5) {
            UsageProviderLogo(provider: provider, size: 12)
            Button {
                openUsagePage(provider)
            } label: {
                Text(provider.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(NotchTheme.primaryText)
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
            .help(localized(en: "Open \(provider.displayName)'s usage page", zh: "打开 \(provider.displayName) 的用量页面"))
            if let plan = status.report?.plan, !plan.isEmpty {
                Text(plan)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(NotchTheme.secondaryText)
                    .lineLimit(1)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.white.opacity(0.12), in: .capsule)
            }
            Spacer(minLength: 0)
            if model.isRefreshing(provider) {
                ProgressView()
                    .controlSize(.mini)
            } else if status.report != nil, let problem = UsageFormat.stateTitle(status.state) {
                // A failed refresh with an older report still on screen.
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.yellow)
                    .help(problem)
            }
        }
    }

    @ViewBuilder
    private func windows(_ report: UsageReport) -> some View {
        if sideBySide {
            HStack(alignment: .top, spacing: 14) {
                ForEach(report.windows.indices, id: \.self) { index in
                    UsageWindowView(window: report.windows[index], provider: provider, now: now)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(report.windows.indices, id: \.self) { index in
                    UsageWindowView(window: report.windows[index], provider: provider, now: now)
                }
            }
        }
        Spacer(minLength: 0)
    }

    @ViewBuilder
    private func stateView(_ state: UsageStatus.State) -> some View {
        switch state {
        case .loading, .ok:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text(localized(en: "Loading…", zh: "正在读取…"))
                    .font(.system(size: 11))
                    .foregroundStyle(NotchTheme.secondaryText)
                    .lineLimit(1)
            }
        case .signedOut:
            message(UsageFormat.stateTitle(state) ?? "", detail: UsageFormat.signInHint())
        case .needsVerification:
            message(UsageFormat.stateTitle(state) ?? "", detail: UsageFormat.verificationHint())
        case .failed(let failure):
            VStack(spacing: 6) {
                Text(UsageFormat.failureText(failure))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(NotchTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                GlassCapsuleButton(localized(en: "Retry", zh: "重试"), symbol: "arrow.clockwise") {
                    model.refresh(provider, force: true)
                }
            }
        }
    }

    private func message(_ title: String, detail: String) -> some View {
        VStack(spacing: 3) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(NotchTheme.primaryText)
                .lineLimit(1)
            Text(detail)
                .font(.system(size: 10))
                .foregroundStyle(NotchTheme.secondaryText)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.8)
        }
    }
}

/// One window: its label and percent, a bar, then the reset time and its parts.
private struct UsageWindowView: View {
    let window: UsageWindow
    let provider: UsageProvider
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .center, spacing: 4) {
                UsageWindowIcon(duration: window.duration, size: 11, color: NotchTheme.secondaryText)
                Text(UsageFormat.windowLabel(window.duration))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(NotchTheme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                UsagePercent(percent: window.percent, size: 13)
            }
            UsageBar(percent: window.percent, provider: provider, height: 5)
            HStack(spacing: 4) {
                if let resetsAt = window.resetsAt {
                    Text(UsageFormat.resetText(resetsAt, now: now))
                        .foregroundStyle(NotchTheme.secondaryText)
                        .layoutPriority(1)
                }
                Spacer(minLength: 0)
                if !window.scoped.isEmpty {
                    scopedText
                        .help(scopedHelp)
                }
            }
            .font(.system(size: 10))
            .lineLimit(1)
            .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var scopedText: Text {
        UsageScopedText.text(window.scoped, provider: provider)
    }

    /// Each part's use, with its own reset time when it differs from the window's.
    private var scopedHelp: String {
        window.scoped.map { scope in
            var line = "\(UsageFormat.scopeLabel(scope, provider: provider)): \(Int(scope.percent.rounded()))%"
            if let resetsAt = scope.resetsAt,
               abs(resetsAt.timeIntervalSince(window.resetsAt ?? resetsAt)) > 60 || window.resetsAt == nil {
                line += " · " + UsageFormat.resetText(resetsAt, now: now)
            }
            return line
        }
        .joined(separator: "\n")
    }
}

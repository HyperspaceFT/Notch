import AppKit
import NotchKit
import NotchUI
import SwiftUI

extension UsageLevel {
    /// The color of a percent at this level; `nil` for normal, which keeps the
    /// surrounding text's color.
    var color: Color? {
        switch self {
        case .normal: nil
        case .warning: .yellow
        case .danger: .red
        }
    }
}

/// A thin capsule filled to `percent` (at most 100): the provider's color, or
/// yellow and red from 70% and 90%.
struct UsageBar: View {
    let percent: Double
    let provider: UsageProvider
    let height: CGFloat

    var body: some View {
        let fraction = min(max(percent / 100, 0), 1)
        Capsule()
            .fill(.white.opacity(0.14))
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(fill)
                        .frame(width: proxy.size.width * fraction)
                }
            }
            .clipShape(.capsule)
            .frame(height: height)
    }

    private var fill: AnyShapeStyle {
        if let color = UsageLevel(percent: percent).color { return AnyShapeStyle(color) }
        return NotchTheme.accent(provider.accentColor)
    }
}

/// A rounded percent in its level's color.
struct UsagePercent: View {
    let percent: Double
    let size: CGFloat
    var weight: Font.Weight = .semibold

    var body: some View {
        Text("\(Int(percent.rounded()))%")
            .font(.system(size: size, weight: weight, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(UsageLevel(percent: percent).color ?? NotchTheme.primaryText)
            .lineLimit(1)
    }
}

/// The provider's glyph in its color.
struct UsageGlyph: View {
    let provider: UsageProvider
    let size: CGFloat

    var body: some View {
        Image(systemName: provider.glyph)
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(NotchTheme.accent(provider.accentColor))
    }
}

/// Re-reads the usage while a usage view is on screen; SwiftUI cancels the
/// loop when the view goes, such as when the panel collapses.
struct UsageRefreshLoop: ViewModifier {
    let model: UsageModel

    /// How often a mounted view checks whether a provider is due.
    static let checkInterval: Duration = .seconds(60)

    func body(content: Content) -> some View {
        content.task {
            while !Task.isCancelled {
                model.refreshIfNeeded()
                try? await Task.sleep(for: Self.checkInterval)
            }
        }
    }
}

extension UsageModel {
    /// The worst level among the displayed providers' reports.
    var worstLevel: UsageLevel {
        displayedProviders
            .flatMap { status(of: $0).report?.windows ?? [] }
            .map { UsageLevel(percent: $0.percent) }
            .max() ?? .normal
    }

    /// The highest percent among the displayed providers' reports; `nil` without any.
    var highestPercent: Double? {
        displayedProviders
            .flatMap { status(of: $0).report?.windows ?? [] }
            .map(\.percent)
            .max()
    }
}

@MainActor
func openUsagePage(_ provider: UsageProvider) {
    NSWorkspace.shared.open(provider.usagePageURL)
}

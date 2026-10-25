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

/// The provider's logo (`UsageLogos`), `size` points square, in its colors.
public struct UsageProviderLogo: View {
    /// Where the logo shows, which decides its colors.
    public enum Style: Sendable {
        /// On the island's black: Claude orange and Codex's gradient with light
        /// and color, primary text without; Grok always primary text.
        case island
        /// In a system window: Claude orange, the others the primary label color.
        case system
    }

    let provider: UsageProvider
    let size: CGFloat
    let style: Style

    public init(provider: UsageProvider, size: CGFloat, style: Style = .island) {
        self.provider = provider
        self.size = size
        self.style = style
    }

    public var body: some View {
        SVGShape(path: UsageLogos.path(for: provider))
            .fill(fill, style: FillStyle(eoFill: UsageLogos.usesEvenOdd(provider)))
            .frame(width: size, height: size)
    }

    private static let claudeOrange = Color(red: 0xD9 / 255, green: 0x77 / 255, blue: 0x57 / 255)
    /// Lobe's codex-color gradient stops.
    private static let codexGradient = LinearGradient(
        stops: [
            .init(color: Color(red: 0xB1 / 255, green: 0xA7 / 255, blue: 0xFF / 255), location: 0),
            .init(color: Color(red: 0x7A / 255, green: 0x9D / 255, blue: 0xFF / 255), location: 0.5),
            .init(color: Color(red: 0x39 / 255, green: 0x41 / 255, blue: 0xFF / 255), location: 1),
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    private var fill: AnyShapeStyle {
        switch (style, provider) {
        case (.system, .claude): AnyShapeStyle(Self.claudeOrange)
        case (.system, _): AnyShapeStyle(.primary)
        case (.island, .claude): NotchTheme.accent(Self.claudeOrange)
        case (.island, .codex):
            NotchAppearance.shared.isLightAndColorEnabled ? AnyShapeStyle(Self.codexGradient) : AnyShapeStyle(NotchTheme.primaryText)
        case (.island, .grok): AnyShapeStyle(NotchTheme.primaryText)
        }
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

/// A window's parts as one line of text.
@MainActor
enum UsageScopedText {
    /// "Fable 74%", the percents in their levels' colors.
    static func text(_ scoped: [UsageScope], provider: UsageProvider) -> Text {
        scoped.enumerated().reduce(Text("")) { text, entry in
            let (index, scope) = entry
            let label = UsageFormat.scopeLabel(scope, provider: provider)
            let percent = Text("\(Int(scope.percent.rounded()))%")
                .foregroundStyle(UsageLevel(percent: scope.percent).color ?? NotchTheme.primaryText)
            return Text("\(text)\(index == 0 ? "" : "  ")\(label) \(percent)")
                .foregroundStyle(NotchTheme.secondaryText)
        }
    }
}

@MainActor
func openUsagePage(_ provider: UsageProvider) {
    NSWorkspace.shared.open(provider.usagePageURL)
}

import SwiftUI

/// A circular Liquid Glass button showing a single SF Symbol.
///
/// Group several of these inside a `GlassEffectContainer` so neighbouring
/// glass shapes blend into each other.
public struct GlassIconButton: View {
    private let symbol: String
    private let isSelected: Bool
    private let help: String?
    private let action: () -> Void

    public init(
        symbol: String,
        isSelected: Bool = false,
        help: String? = nil,
        action: @escaping () -> Void
    ) {
        self.symbol = symbol
        self.isSelected = isSelected
        self.help = help
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isSelected ? NotchTheme.primaryText : NotchTheme.secondaryText)
                .frame(width: 28, height: 28)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassEffect(
            isSelected ? .regular.tint(.white.opacity(0.18)).interactive() : .regular.interactive(),
            in: .circle
        )
        .help(help ?? "")
    }
}

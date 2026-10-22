import SwiftUI

/// A compact Liquid Glass capsule button with an SF Symbol and a short label.
public struct GlassCapsuleButton: View {
    private let title: String
    private let symbol: String
    private let action: () -> Void

    public init(_ title: String, symbol: String, action: @escaping () -> Void) {
        self.title = title
        self.symbol = symbol
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(NotchTheme.secondaryText)
                .padding(.horizontal, 10)
                .frame(height: 26)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
    }
}

import SwiftUI

/// A rounded container for grouping content inside the expanded island, lit from
/// above. A tint washes it from the top-leading corner with a color that says
/// something about the content, such as the sky or a charging battery.
public struct NotchCard<Content: View>: View {
    private let title: String?
    private let tint: Color?
    private let content: Content

    public init(title: String? = nil, tint: Color? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.tint = tint
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(NotchTheme.secondaryText)
            }
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
            // Clear rather than absent without a tint, so a tint fades in and out.
            let tint = tint ?? .clear
            shape
                .fill(NotchTheme.cardFill)
                .overlay {
                    shape.fill(LinearGradient(
                        stops: [
                            .init(color: tint.opacity(NotchTheme.cardTintOpacity), location: 0),
                            .init(color: tint.opacity(0), location: 0.8),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                }
                .overlay {
                    shape.strokeBorder(NotchTheme.cardRim, lineWidth: 1)
                }
                .animation(.smooth, value: tint)
        }
    }
}

import NotchKit
import NotchUI
import SwiftUI

/// Home tab, the first one in the expanded panel. For now it shows only the
/// live time. No activities.
@MainActor
public final class HomeFeature: NotchFeature {
    public let id = "home"
    public var title: String { localized(en: "Home", zh: "主页") }
    public let symbol = "house"

    public init() {}

    public func makeExpandedView() -> AnyView? {
        AnyView(HomeExpandedView())
    }
}

private struct HomeExpandedView: View {
    private static let timeStyle = Date.FormatStyle(locale: Locale(identifier: "zh_CN"))
        .hour(.twoDigits(amPM: .omitted))
        .minute(.twoDigits)
        .second(.twoDigits)

    var body: some View {
        NotchCard {
            // Ticks once per second; SwiftUI pauses it while the view is off screen.
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(context.date, format: Self.timeStyle)
                    .font(.system(size: 48, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.smooth(duration: 0.3), value: context.date)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

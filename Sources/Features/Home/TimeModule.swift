import NotchKit
import NotchUI
import SwiftUI

/// Home's own module: the time with the date below. At its narrowest it is a
/// square showing hours and minutes; from `secondsThreshold` on it adds seconds.
enum TimeModule {
    static let id = "time"
    /// Wide enough for "00:00:00" at the clock's size plus the card's padding.
    static let maximumWidth: CGFloat = 184
    /// From this width on the clock shows seconds. Below `maximumWidth` they do
    /// not fit at full size, so the digits shrink, by at most 15% here.
    static let secondsThreshold: CGFloat = 160
    static let sizing = HomeModuleSizing.resizable(minimum: .height(1), maximum: .points(maximumWidth))

    static func showsSeconds(width: CGFloat) -> Bool {
        width >= secondsThreshold
    }

    @MainActor
    static func makeModule() -> NotchHomeModule {
        NotchHomeModule(
            id: id,
            title: { localized(en: "Time", zh: "时间") },
            symbol: "clock",
            sizing: sizing
        ) { size in
            AnyView(TimeModuleView(showsSeconds: showsSeconds(width: size.width)))
        }
    }
}

private struct TimeModuleView: View {
    let showsSeconds: Bool

    private static let minuteStyle = Date.FormatStyle(locale: Locale(identifier: "zh_CN"))
        .hour(.twoDigits(amPM: .omitted))
        .minute(.twoDigits)
    private static let secondStyle = minuteStyle.second(.twoDigits)

    var body: some View {
        NotchCard {
            // Ticks once per second; SwiftUI pauses it while the view is off screen.
            TimelineView(.periodic(from: .now, by: 1)) { context in
                // Formatted to strings first: `Text(_:format:)` would use the
                // environment's locale instead of the styles' own.
                VStack(spacing: 2) {
                    Text(context.date.formatted(showsSeconds ? Self.secondStyle : Self.minuteStyle))
                        .font(.system(size: 36, weight: .semibold, design: .rounded))
                        .foregroundStyle(NotchTheme.headline())
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .contentTransition(.numericText())
                        .animation(.smooth(duration: 0.3), value: context.date)
                    Text(context.date.formatted(dateStyle))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(NotchTheme.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    /// "Thu, Oct 22" or "10月22日 周四", in the interface language.
    private var dateStyle: Date.FormatStyle {
        Date.FormatStyle(locale: Locale(identifier: Localization.shared.language.rawValue))
            .month(.abbreviated)
            .day()
            .weekday(.abbreviated)
    }
}

import NotchKit
import NotchUI
import SwiftUI

/// The clock's Home module: the time with the date below. At its narrowest it is
/// a square showing hours and minutes; from `secondsThreshold` on it adds seconds.
/// A click opens the timer's tab, on its picker while idle; while a timer counts
/// down or rings, the card shows it instead of the time.
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
    static func makeModule(timer: TimerModel, openTimer: @escaping @MainActor () -> Void) -> NotchHomeModule {
        let hover = TimeCardHover()
        return NotchHomeModule(
            id: id,
            title: { localized(en: "Time", zh: "时间") },
            symbol: "clock",
            sizing: sizing
        ) { size in
            AnyView(TimeModuleView(
                timer: timer,
                hover: hover,
                showsSeconds: showsSeconds(width: size.width),
                openTimer: openTimer
            ))
        }
    }
}

/// Whether the pointer rests on the clock card. Owned by the module rather than
/// the view (`@State` needs a macro plugin the Command Line Tools do not ship).
@MainActor
@Observable
private final class TimeCardHover {
    var isHovered = false
}

private struct TimeModuleView: View {
    let timer: TimerModel
    let hover: TimeCardHover
    let showsSeconds: Bool
    let openTimer: @MainActor () -> Void

    private static let minuteStyle = Date.FormatStyle(locale: Locale(identifier: "zh_CN"))
        .hour(.twoDigits(amPM: .omitted))
        .minute(.twoDigits)
    private static let secondStyle = minuteStyle.second(.twoDigits)

    var body: some View {
        Button(action: openTimer) {
            switch timer.phase {
            case .idle:
                clock
                    .overlay(alignment: .topTrailing) {
                        // Says the card does something when clicked.
                        Image(systemName: "timer")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(NotchTheme.secondaryText)
                            .padding(10)
                            .opacity(hover.isHovered ? 1 : 0)
                            .animation(.smooth(duration: 0.2), value: hover.isHovered)
                    }
            case .counting(let countdown):
                NotchCard(tint: timerColor) {
                    CountdownTimeline(timer: countdown) { now in
                        bigLine(
                            CountdownTimer.display(countdown.remaining(at: now)),
                            color: countdown.isPaused ? NotchTheme.secondaryText : NotchTheme.primaryText,
                            secondary: timerStatus(countdown)
                        )
                    }
                }
            case .finished:
                NotchCard(tint: timerColor) {
                    VStack(spacing: 4) {
                        Image(systemName: "bell.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(NotchTheme.accent(timerColor))
                            .symbolEffect(.wiggle, options: .repeat(.continuous))
                        Text(localized(en: "Time's up", zh: "时间到"))
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                            .foregroundStyle(NotchTheme.headline())
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .buttonStyle(.plain)
        .contentShape(.rect)
        .onHover { hover.isHovered = $0 }
    }

    /// Big digits over a secondary line, as the clock draws them.
    private func bigLine(_ text: String, color: Color, secondary: String) -> some View {
        VStack(spacing: 2) {
            Text(text)
                .font(.system(size: 36, weight: .semibold, design: .rounded))
                .foregroundStyle(NotchTheme.headline(color))
                .monospacedDigit()
                .lineLimit(1)
                // Room for "1:04:59" in the square card.
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText(countsDown: true))
                .animation(.smooth(duration: 0.3), value: text)
            Text(secondary)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(NotchTheme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var clock: some View {
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

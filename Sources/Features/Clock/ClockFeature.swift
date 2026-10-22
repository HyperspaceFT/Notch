import NotchKit
import NotchUI
import SwiftUI

/// "今天" tab: live time, date, and weekday in the Chinese locale. No activities.
@MainActor
public final class ClockFeature: NotchFeature {
    public let id = "clock"
    public let title = "今天"
    public let symbol = "clock"

    public init() {}

    public func makeExpandedView() -> AnyView? {
        AnyView(ClockExpandedView())
    }
}

private struct ClockExpandedView: View {
    private static let locale = Locale(identifier: "zh_CN")
    private static let timeStyle = Date.FormatStyle(locale: locale)
        .hour(.twoDigits(amPM: .omitted))
        .minute(.twoDigits)
        .second(.twoDigits)
    private static let dateStyle = Date.FormatStyle(locale: locale)
        .year()
        .month(.wide)
        .day()
    private static let weekdayStyle = Date.FormatStyle(locale: locale)
        .weekday(.wide)

    var body: some View {
        NotchCard(title: "今天") {
            // Ticks once per second; SwiftUI pauses it while the view is off screen.
            TimelineView(.periodic(from: .now, by: 1)) { context in
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    Text(context.date, format: Self.timeStyle)
                        .font(.system(size: 40, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    VStack(alignment: .leading, spacing: 4) {
                        Text(context.date, format: Self.dateStyle)
                            .font(.system(size: 13, weight: .medium))
                        Text(context.date, format: Self.weekdayStyle)
                            .font(.system(size: 13))
                            .foregroundStyle(NotchTheme.secondaryText)
                    }
                    Spacer(minLength: 0)
                }
                .animation(.smooth(duration: 0.3), value: context.date)
            }
        }
    }
}

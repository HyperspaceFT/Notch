import NotchKit
import SwiftUI
import WeatherFeature

/// The Weather pane: what the Home weather module shows at each time of day.
/// The day splits into three periods, set on a 24-hour dial, each showing
/// today's weather, the next hours, or tomorrow's weather.
struct WeatherSettingsView: View {
    @Bindable var settings: WeatherSettings

    var body: some View {
        Form {
            Section {
                WeatherScheduleDial(settings: settings)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            } footer: {
                Text(localized(
                    en: "Drag the knobs on the ring to move where each period starts.",
                    zh: "拖动圆环上的圆点，调整每个时段的开始时间。"
                ))
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            Section {
                ForEach(0..<WeatherSchedule.periodCount, id: \.self) { period in
                    PeriodRow(settings: settings, period: period)
                }
            } header: {
                Text(localized(en: "Periods", zh: "时段"))
            } footer: {
                HStack {
                    Spacer()
                    Button(localized(en: "Restore Defaults", zh: "恢复默认")) {
                        settings.resetSchedule()
                    }
                    .disabled(settings.schedule == .standard)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// One period: its color, its hours, and what it shows.
private struct PeriodRow: View {
    @Bindable var settings: WeatherSettings
    let period: Int

    var body: some View {
        let schedule = settings.schedule
        HStack(spacing: 10) {
            Circle()
                .fill(schedule.modes[period].color)
                .frame(width: 10, height: 10)
            Text("\(clockText(schedule.starts[period])) – \(clockText(schedule.end(of: period)))")
                .monospacedDigit()
            Spacer(minLength: 8)
            Picker(localized(en: "Shows", zh: "显示"), selection: $settings.schedule.modes[period]) {
                ForEach(WeatherDisplayMode.allCases, id: \.self) { mode in
                    Label(mode.title, systemImage: mode.symbol)
                        .tag(mode)
                }
            }
            .labelsHidden()
            .fixedSize()
        }
    }
}

/// The day as a ring, midnight at the top and noon at the bottom, clockwise.
/// Each period is an arc in its mode's color with the mode's symbol on it; the
/// knob where a period starts drags around the ring. The center tells what Home
/// shows right now, or the time under the knob while dragging.
private struct WeatherScheduleDial: View {
    @Bindable var settings: WeatherSettings
    /// The period whose start is being dragged; back to nil when the drag ends.
    @GestureState private var dragging: Int?

    private static let size: CGFloat = 228
    private static let ringWidth: CGFloat = 26
    private static var radius: CGFloat { (size - ringWidth) / 2 - 6 }
    private static let knobSize: CGFloat = 22

    var body: some View {
        let schedule = settings.schedule
        // Once a minute, for the marker and the readout of the current period.
        TimelineView(.everyMinute) { context in
            let now = minuteOfDay(context.date)
            ZStack {
                Circle()
                    .stroke(.quaternary, lineWidth: Self.ringWidth)
                    .frame(width: Self.radius * 2, height: Self.radius * 2)
                ForEach(0..<WeatherSchedule.periodCount, id: \.self) { period in
                    DialArc(start: schedule.starts[period], end: schedule.end(of: period), radius: Self.radius)
                        .stroke(schedule.modes[period].color.gradient, lineWidth: Self.ringWidth)
                    Image(systemName: schedule.modes[period].symbol)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .position(Self.point(atMinute: middle(of: period, in: schedule), radius: Self.radius))
                        .allowsHitTesting(false)
                }
                ticks
                nowMarker(at: now)
                ForEach(0..<WeatherSchedule.periodCount, id: \.self) { period in
                    knob(for: period, in: schedule)
                }
                readout(schedule: schedule, now: now)
            }
            .frame(width: Self.size, height: Self.size)
            .coordinateSpace(.named(DialSpace.name))
        }
    }

    // MARK: Pieces

    /// Hour marks inside the ring, with the quarter hours of the day labeled.
    private var ticks: some View {
        ZStack {
            ForEach(0..<24, id: \.self) { hour in
                let isQuarter = hour % 6 == 0
                Capsule()
                    .fill(isQuarter ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
                    .frame(width: isQuarter ? 2 : 1, height: isQuarter ? 6 : 4)
                    .offset(y: -(Self.radius - Self.ringWidth / 2 - 7))
                    .rotationEffect(.degrees(Double(hour) * 15))
            }
            ForEach([0, 6, 12, 18], id: \.self) { hour in
                Text("\(hour)")
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .position(Self.point(atMinute: hour * 60, radius: Self.radius - Self.ringWidth / 2 - 20))
            }
        }
        .frame(width: Self.size, height: Self.size)
        .allowsHitTesting(false)
    }

    /// A small pointer just outside the ring at the current time.
    private func nowMarker(at minute: Int) -> some View {
        Image(systemName: "arrowtriangle.down.fill")
            .font(.system(size: 8))
            .foregroundStyle(.primary)
            .rotationEffect(.radians(WeatherSchedule.angle(forMinute: minute)))
            .position(Self.point(atMinute: minute, radius: Self.radius + Self.ringWidth / 2 + 6))
            .allowsHitTesting(false)
    }

    private func knob(for period: Int, in schedule: WeatherSchedule) -> some View {
        let isDragging = dragging == period
        return Circle()
            .fill(.white)
            .overlay(Circle().strokeBorder(.black.opacity(0.1)))
            .shadow(color: .black.opacity(0.3), radius: isDragging ? 4 : 2, y: 1)
            .frame(width: Self.knobSize, height: Self.knobSize)
            .scaleEffect(isDragging ? 1.15 : 1)
            .animation(.snappy(duration: 0.15), value: isDragging)
            // Pointer, gesture, and accessibility go on the knob itself, before
            // `position`, which would stretch them over the whole dial.
            .pointerStyle(isDragging ? .grabActive : .grabIdle)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named(DialSpace.name))
                    .updating($dragging) { _, state, _ in
                        state = period
                    }
                    .onChanged { value in
                        let center = CGPoint(x: Self.size / 2, y: Self.size / 2)
                        // Clockwise from the top, the dial's own angle convention.
                        let angle = atan2(value.location.x - center.x, center.y - value.location.y)
                        var moved = settings.schedule
                        moved.moveStart(of: period, to: WeatherSchedule.minute(forAngle: angle))
                        if moved != settings.schedule {
                            settings.schedule = moved
                        }
                    }
            )
            .accessibilityElement()
            .accessibilityLabel(localized(en: "Period \(period + 1) start", zh: "时段 \(period + 1) 开始"))
            .accessibilityValue(clockText(schedule.starts[period]))
            .accessibilityAdjustableAction { direction in
                var moved = settings.schedule
                let step = direction == .increment ? WeatherSchedule.step : -WeatherSchedule.step
                moved.moveStart(of: period, to: moved.starts[period] + step)
                settings.schedule = moved
            }
            .position(Self.point(atMinute: schedule.starts[period], radius: Self.radius))
    }

    /// The dragged knob's time, or what Home shows now and until when.
    private func readout(schedule: WeatherSchedule, now: Int) -> some View {
        VStack(spacing: 3) {
            if let dragging {
                Text(clockText(schedule.starts[dragging]))
                    .font(.system(size: 28, weight: .semibold, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText())
                Text(schedule.modes[dragging].title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                let period = schedule.period(atMinute: now)
                let mode = schedule.modes[period]
                Image(systemName: mode.symbol)
                    .font(.system(size: 22))
                    .foregroundStyle(mode.color)
                Text(mode.title)
                    .font(.headline)
                Text(localized(
                    en: "Now, until \(clockText(schedule.end(of: period)))",
                    zh: "现在，到 \(clockText(schedule.end(of: period)))"
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
        }
        .frame(width: Self.radius * 2 - Self.ringWidth - 40)
        .allowsHitTesting(false)
    }

    // MARK: Geometry

    private func middle(of period: Int, in schedule: WeatherSchedule) -> Int {
        schedule.starts[period] + schedule.length(of: period) / 2
    }

    /// A point on a circle of `radius` around the dial's center at `minute`.
    static func point(atMinute minute: Int, radius: CGFloat) -> CGPoint {
        let angle = WeatherSchedule.angle(forMinute: minute)
        return CGPoint(x: size / 2 + radius * sin(angle), y: size / 2 - radius * cos(angle))
    }
}

private enum DialSpace {
    static let name = "WeatherScheduleDial"
}

/// The part of the dial's circle from `start` to `end`, clockwise, wrapping past midnight.
private struct DialArc: Shape {
    let start: Int
    let end: Int
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let day = WeatherSchedule.minutesPerDay
        let length = (end - start + day) % day == 0 ? day : (end - start + day) % day
        let center = CGPoint(x: rect.midX, y: rect.midY)
        // One point every few minutes draws a smooth arc without the flipped-axis
        // ambiguity of `addArc(clockwise:)`.
        let steps = max(length / 5, 2)
        var path = Path()
        for step in 0...steps {
            let minute = start + length * step / steps
            let angle = WeatherSchedule.angle(forMinute: minute)
            let point = CGPoint(x: center.x + radius * sin(angle), y: center.y - radius * cos(angle))
            if step == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        return path
    }
}

private extension WeatherDisplayMode {
    /// Morning sun, daytime sky, and night: the color of the mode's arc and dot.
    var color: Color {
        switch self {
        case .today: .orange
        case .upcoming: .teal
        case .tomorrow: .indigo
        }
    }
}

/// "07:30" for 450 minutes after midnight.
private func clockText(_ minute: Int) -> String {
    let minute = (minute % WeatherSchedule.minutesPerDay + WeatherSchedule.minutesPerDay) % WeatherSchedule.minutesPerDay
    return String(format: "%02d:%02d", minute / 60, minute % 60)
}

private func minuteOfDay(_ date: Date) -> Int {
    let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
    return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
}

import NotchKit
import NotchUI
import SwiftUI

/// Width of each wing once the timer has run out: room for "Time's up" on the right.
let finishedWingWidth: CGFloat = 76

/// The timer's color: the ring, the card's tint, the bell, the band around the island.
let timerColor = Color.orange

/// The timer's color for what shows it beside the notch (the wings' ring and bell,
/// the tab button's ring and bell): orange in both appearance modes, like the band
/// around the island; shaded with light and color, flat without.
@MainActor
func timerStyle() -> AnyShapeStyle {
    NotchAppearance.shared.isLightAndColorEnabled ? AnyShapeStyle(timerColor.gradient) : AnyShapeStyle(timerColor)
}

/// Room each wing leaves between its content and the island's outer edge, so the
/// content stays clear of the rounded bottom corner (`NotchTheme.activityBottomRadius`).
/// The content hugs the notch, so this is part of the wing's width, not padding.
private let wingCornerClearance: CGFloat = 12
/// Space between a wing's content and the notch.
private let wingNotchClearance: CGFloat = 6

/// The countdown wings' widths: only as wide as the time on the right needs (the
/// ring on the left needs less), as it reads when the wings are presented.
enum CountdownWings {
    /// Room for "59:59" at the wing's 12-point semibold digits.
    static let shortTimeWidth: CGFloat = 34
    /// Room for "0:00:00".
    static let longTimeWidth: CGFloat = 46

    /// Each wing's width for a timer with `remaining` seconds left: the time's
    /// room (`timeWidth`) and both clearances.
    static func width(remaining: TimeInterval) -> CGFloat {
        wingCornerClearance + timeWidth(remaining: remaining) + wingNotchClearance
    }

    /// Room for the time with `remaining` seconds left: for "m:ss" under an hour,
    /// and for "h:mm:ss" from one, as `CountdownTimer.display` shows it (rounded
    /// up, so 3599.5 seconds already read "1:00:00"). The right wing keeps the time
    /// to this room, so time added later past the hour shrinks its digits rather
    /// than run into the corner clearance; the wings keep their width.
    static func timeWidth(remaining: TimeInterval) -> CGFloat {
        Int(max(remaining, 0).rounded(.up)) >= 3600 ? longTimeWidth : shortTimeWidth
    }
}

/// How far a wing's content moves while the island is hovered: half the ring it
/// grows by, outward (`outward` is -1 for the left wing, 1 for the right) and
/// down, so it keeps its place in the grown outline.
private func wingHoverOffset(isHovered: Bool, outward: CGFloat) -> CGSize {
    guard isHovered else { return .zero }
    return CGSize(width: NotchTheme.hoverGrowth.width / 2 * outward, height: NotchTheme.hoverGrowth.height / 2)
}

/// A preset's name: "5 min" or "5 分钟", and "1 hr" or "1 小时" for an hour.
@MainActor
func presetTitle(minutes: Int) -> String {
    if minutes % 60 == 0 {
        let hours = minutes / 60
        return localized(en: "\(hours) hr", zh: "\(hours) 小时")
    }
    return localized(en: "\(minutes) min", zh: "\(minutes) 分钟")
}

/// "Ends 2:37 PM" or "14:37 结束" for a running timer, "Paused" or "已暂停" for a
/// paused one.
@MainActor
func timerStatus(_ timer: CountdownTimer) -> String {
    guard let endDate = timer.endDate else {
        return localized(en: "Paused", zh: "已暂停")
    }
    let time = endDate.formatted(
        Date.FormatStyle(date: .omitted, time: .shortened)
            .locale(Locale(identifier: Localization.shared.language.rawValue))
    )
    return localized(en: "Ends \(time)", zh: "\(time) 结束")
}

/// Redraws `content` every second while `timer` runs, on the moments its shown
/// time changes: whole seconds before the end, plus a little, so that rounding
/// up never shows the second just gone. Paused, it draws once.
struct CountdownTimeline<Content: View>: View {
    let timer: CountdownTimer
    @ViewBuilder let content: (Date) -> Content

    var body: some View {
        if let endDate = timer.endDate {
            let anchor = endDate.addingTimeInterval(-(max(endDate.timeIntervalSinceNow, 0).rounded(.up) + 1) + 0.05)
            TimelineView(.periodic(from: anchor, by: 1)) { context in
                // The first entry is the latest tick, up to a second old: drawn at
                // its date, a fresh five-minute timer would read "5:01".
                content(max(context.date, Date()))
            }
        } else {
            content(Date())
        }
    }
}

/// A ring showing the share of the timer left, orange with light and color, or
/// in `style`.
struct CountdownRing: View {
    let progress: Double
    let lineWidth: CGFloat
    /// The filled part's style; `nil` is the timer's color with light and color only.
    var style: AnyShapeStyle? = nil

    var body: some View {
        ZStack {
            Circle()
                .stroke(NotchTheme.primaryText.opacity(0.2), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(style ?? NotchTheme.accent(timerColor), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        // The stroke is centred on the path, so inset it to keep the outer edge at the frame.
        .padding(lineWidth / 2)
        .animation(.smooth(duration: 0.5), value: progress)
    }
}

// MARK: Wings

/// Left wing while counting down: a small ring with the share left, right next
/// to the notch, dimmed while paused. A click opens the timer's tab.
struct CountdownWingLeading: View {
    let model: TimerModel
    let open: @MainActor () -> Void
    @Environment(\.notchIsHovered) private var isIslandHovered

    var body: some View {
        Button(action: open) {
            Group {
                if case .counting(let timer) = model.phase {
                    CountdownTimeline(timer: timer) { now in
                        CountdownRing(progress: timer.progress(at: now), lineWidth: 3, style: timerStyle())
                            .frame(width: 18, height: 18)
                            .opacity(timer.isPaused ? 0.45 : 1)
                    }
                }
            }
            // An offset, not padding: the content keeps its size. The island's
            // hover animation carries the move.
            .offset(wingHoverOffset(isHovered: isIslandHovered, outward: -1))
            .padding(.trailing, wingNotchClearance)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(localized(en: "Timer", zh: "计时器"))
    }
}

/// Right wing while counting down: the time left, ticking each second, right
/// next to the notch, dimmed while paused. A click opens the timer's tab.
struct CountdownWingTrailing: View {
    let model: TimerModel
    /// Room the time keeps to (`CountdownWings.timeWidth`).
    let timeWidth: CGFloat
    let open: @MainActor () -> Void
    @Environment(\.notchIsHovered) private var isIslandHovered

    var body: some View {
        Button(action: open) {
            Group {
                if case .counting(let timer) = model.phase {
                    CountdownTimeline(timer: timer) { now in
                        Text(CountdownTimer.display(timer.remaining(at: now)))
                            .font(.system(size: 12, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(timer.isPaused ? NotchTheme.secondaryText : NotchTheme.primaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: timeWidth, alignment: .leading)
                    }
                }
            }
            // Moves with the hovered island, like the left wing.
            .offset(wingHoverOffset(isHovered: isIslandHovered, outward: 1))
            .padding(.leading, wingNotchClearance)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

/// Left wing once the timer has run out: a ringing bell next to the notch. A
/// click stops the alert.
struct FinishedWingLeading: View {
    let stop: @MainActor () -> Void
    @Environment(\.notchIsHovered) private var isIslandHovered

    var body: some View {
        Button(action: stop) {
            Image(systemName: "bell.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(timerStyle())
                .symbolEffect(.wiggle, options: .repeat(.continuous))
                .offset(wingHoverOffset(isHovered: isIslandHovered, outward: -1))
                .padding(.trailing, wingNotchClearance)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(localized(en: "Stop Alert", zh: "停止提醒"))
    }
}

/// Right wing once the timer has run out, next to the notch. A click stops the alert.
struct FinishedWingTrailing: View {
    let stop: @MainActor () -> Void
    @Environment(\.notchIsHovered) private var isIslandHovered

    var body: some View {
        Button(action: stop) {
            Text(localized(en: "Time's up", zh: "时间到"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(NotchTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .offset(wingHoverOffset(isHovered: isIslandHovered, outward: 1))
                .padding(.leading, wingNotchClearance)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

// MARK: Panel

/// The timer's panel, opened on its own in the expanded island: the setter while
/// idle, the ring and controls while counting down, the alert once finished.
/// Opened while idle; a started timer moves on to the timer's tab (`TimerTab`).
struct TimerPanel: View {
    let model: TimerModel
    /// Called after the setter starts a timer.
    let didStart: @MainActor () -> Void

    var body: some View {
        Group {
            switch model.phase {
            case .idle:
                TimerSetter(model: model, didStart: didStart)
            case .counting(let timer):
                TimerCountdown(model: model, timer: timer)
            case .finished:
                TimerFinished(model: model)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.smooth(duration: 0.3), value: model.phase)
    }
}

/// The timer's tab, shown while it counts down or rings: the ring and controls,
/// or the alert. Idle, the tab is hidden and this draws nothing.
struct TimerTab: View {
    let model: TimerModel

    var body: some View {
        Group {
            switch model.phase {
            case .idle:
                Color.clear
            case .counting(let timer):
                TimerCountdown(model: model, timer: timer)
            case .finished:
                TimerFinished(model: model)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.smooth(duration: 0.3), value: model.phase)
    }
}

/// The timer tab's button: a small ring with the share left around a timer
/// glyph, ticking each second and dimmed while paused; a bell once finished.
struct TimerTabIcon: View {
    let model: TimerModel

    var body: some View {
        switch model.phase {
        case .idle:
            Image(systemName: "timer")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(NotchTheme.secondaryText)
        case .counting(let timer):
            CountdownTimeline(timer: timer) { now in
                ZStack {
                    CountdownRing(progress: timer.progress(at: now), lineWidth: 2, style: timerStyle())
                    Image(systemName: "timer")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(NotchTheme.primaryText)
                }
                .frame(width: 20, height: 20)
                .opacity(timer.isPaused ? 0.45 : 1)
            }
        case .finished:
            Image(systemName: "bell.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(timerStyle())
                .symbolEffect(.wiggle, options: .repeat(.continuous))
        }
    }
}

private struct TimerSetter: View {
    let model: TimerModel
    let didStart: @MainActor () -> Void

    var body: some View {
        HStack(spacing: 10) {
            NotchCard {
                VStack(spacing: 8) {
                    Text(CountdownTimer.display(TimeInterval(model.setterMinutes * 60)))
                        .font(.system(size: 36, weight: .semibold, design: .rounded))
                        .foregroundStyle(NotchTheme.headline())
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .contentTransition(.numericText())
                        .animation(.smooth(duration: 0.3), value: model.setterMinutes)
                    GlassEffectContainer {
                        HStack(spacing: 12) {
                            GlassIconButton(symbol: "minus", help: localized(en: "1 Minute Less", zh: "减 1 分钟")) {
                                model.adjustSetter(by: -1)
                            }
                            GlassIconButton(symbol: "plus", help: localized(en: "1 Minute More", zh: "加 1 分钟")) {
                                model.adjustSetter(by: 1)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: 160)

            VStack(spacing: 8) {
                GlassEffectContainer {
                    Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                        ForEach([0, 4], id: \.self) { start in
                            GridRow {
                                ForEach(CountdownTimer.presetMinutes[start..<start + 4], id: \.self) { minutes in
                                    PresetChip(title: presetTitle(minutes: minutes)) {
                                        model.start(minutes: minutes)
                                        didStart()
                                    }
                                }
                            }
                        }
                    }
                }
                GlassCapsuleButton(localized(en: "Start", zh: "开始"), symbol: "play.fill") {
                    model.start(minutes: model.setterMinutes)
                    didStart()
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

/// A preset in the setter: starts the timer at once.
private struct PresetChip: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(NotchTheme.secondaryText)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .frame(height: 26)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
    }
}

private struct TimerCountdown: View {
    let model: TimerModel
    let timer: CountdownTimer

    var body: some View {
        HStack(spacing: 20) {
            CountdownTimeline(timer: timer) { now in
                ZStack {
                    CountdownRing(progress: timer.progress(at: now), lineWidth: 6)
                        .opacity(timer.isPaused ? 0.5 : 1)
                    Text(CountdownTimer.display(timer.remaining(at: now)))
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundStyle(NotchTheme.headline(timer.isPaused ? NotchTheme.secondaryText : NotchTheme.primaryText))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .padding(.horizontal, 12)
                        .contentTransition(.numericText(countsDown: true))
                        .animation(.smooth(duration: 0.3), value: timer.remaining(at: now).rounded(.up))
                }
            }
            .frame(width: 112, height: 112)

            VStack(alignment: .leading, spacing: 12) {
                Text(timerStatus(timer))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(NotchTheme.secondaryText)
                    .lineLimit(1)
                GlassEffectContainer {
                    HStack(spacing: 8) {
                        GlassIconButton(
                            symbol: timer.isPaused ? "play.fill" : "pause.fill",
                            help: timer.isPaused ? localized(en: "Resume", zh: "继续") : localized(en: "Pause", zh: "暂停")
                        ) {
                            model.togglePause()
                        }
                        GlassCapsuleButton(localized(en: "+1 min", zh: "+1 分钟"), symbol: "plus") {
                            model.addMinute()
                        }
                        GlassIconButton(symbol: "xmark", help: localized(en: "Cancel Timer", zh: "取消计时")) {
                            model.cancel()
                        }
                    }
                }
            }
        }
    }
}

private struct TimerFinished: View {
    let model: TimerModel

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "bell.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(NotchTheme.accent(timerColor))
                    .symbolEffect(.wiggle, options: .repeat(.continuous))
                Text(localized(en: "Time's up", zh: "时间到"))
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(NotchTheme.headline())
                    .lineLimit(1)
            }
            GlassEffectContainer {
                HStack(spacing: 8) {
                    GlassCapsuleButton(localized(en: "Restart", zh: "再来一次"), symbol: "arrow.counterclockwise") {
                        model.restart()
                    }
                    GlassCapsuleButton(localized(en: "Done", zh: "完成"), symbol: "checkmark") {
                        model.stopAlert()
                    }
                }
            }
        }
    }
}

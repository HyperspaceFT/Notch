import AppKit
import NotchKit
import NotchUI
import Observation
import SwiftUI

/// The timer picker's ruler, as numbers: one tick per minute of
/// `CountdownTimer.setterMinutes`, `spacing` apart. The ruler stands at a
/// position, in minutes and fractional while it moves, that sits under the
/// fixed center; the selected minute is the nearest whole one.
enum MinuteRuler {
    /// Space between neighbouring ticks: some 25 minutes either way of the
    /// selection show at once in the standard-width tab.
    static let spacing: CGFloat = 8
    static let tickWidth: CGFloat = 2
    /// A tick's height away from the selection.
    static let tickHeight: CGFloat = 14
    /// Every `majorInterval` minutes a tick stands a little taller, to find one's
    /// way along the ruler without labels.
    static let majorTickHeight: CGFloat = 20
    static let majorInterval = 10
    /// The selected tick's height, sticking out above and below the others.
    static let selectedTickHeight: CGFloat = 44
    /// Ticks each side of the selection over which the height falls back to normal.
    static let falloffRadius: Double = 5

    /// `position` kept on the ruler.
    static func clamped(_ position: Double) -> Double {
        min(max(position, Double(CountdownTimer.setterMinutes.lowerBound)), Double(CountdownTimer.setterMinutes.upperBound))
    }

    /// The whole minute nearest `position`, on the ruler.
    static func minute(at position: Double) -> Int {
        Int(clamped(position).rounded())
    }

    /// Where the ruler stands once its ticks moved `points` to the right (to the
    /// left when negative) from `position`: right brings smaller minutes under
    /// the center, left larger ones.
    static func position(_ position: Double, movedBy points: CGFloat) -> Double {
        clamped(position - Double(points / spacing))
    }

    /// The minute whose tick is `offset` points right of the center (left when
    /// negative) while the ruler stands at `position`.
    static func minute(atOffset offset: CGFloat, from position: Double) -> Int {
        minute(at: position + Double(offset / spacing))
    }

    /// How much a tick `distance` minutes from the ruler's position stands out:
    /// 1 at the position, falling along half a cosine wave to 0 at
    /// `falloffRadius` and beyond, so the heights ease into the normal ones.
    static func emphasis(distance: Double) -> Double {
        let distance = abs(distance)
        guard distance < falloffRadius else { return 0 }
        return (1 + cos(.pi * distance / falloffRadius)) / 2
    }

    /// The height of `minute`'s tick while the ruler stands at `position`.
    static func height(ofTick minute: Int, position: Double) -> CGFloat {
        let base = minute % majorInterval == 0 ? majorTickHeight : tickHeight
        return base + (selectedTickHeight - base) * CGFloat(emphasis(distance: Double(minute) - position))
    }
}

/// The picker on the idle timer's tab: where its ruler stands, and the input that
/// moves it. The selected minute is the model's `setterMinutes`, which follows
/// the ruler as it moves; each minute the user moves it to taps the trackpad.
@MainActor
@Observable
final class TimerPicker {
    /// Settles the ruler on a whole minute once the user lets go.
    static let snapAnimation = Animation.snappy(duration: 0.25)

    let model: TimerModel
    /// Where the ruler stands while the user moves it; `nil` at rest, on
    /// `model.setterMinutes`.
    private var movingPosition: Double?

    init(model: TimerModel) {
        self.model = model
    }

    /// Where the ruler stands, in minutes. A moving position the model's minute
    /// no longer agrees with (another source set it, such as a preset start) is
    /// stale, and the model wins.
    var position: Double {
        if let movingPosition, MinuteRuler.minute(at: movingPosition) == model.setterMinutes {
            return movingPosition
        }
        return Double(model.setterMinutes)
    }

    /// Moves the ruler to `position`, kept on the ruler, selecting the minute
    /// nearest it; settles only when `settle()` is called.
    func move(to position: Double) {
        let position = MinuteRuler.clamped(position)
        movingPosition = position
        select(MinuteRuler.minute(at: position))
    }

    /// Moves the ruler's ticks `points` to the right (left when negative).
    func move(by points: CGFloat) {
        move(to: MinuteRuler.position(position, movedBy: points))
    }

    /// Settles the moved ruler on the selected minute.
    func settle() {
        guard movingPosition != nil else { return }
        withAnimation(Self.snapAnimation) {
            movingPosition = nil
        }
    }

    /// Drops the moving position at once, without the settling animation: the
    /// ruler left the screen mid-gesture, so no end of the gesture will settle it.
    func reset() {
        movingPosition = nil
    }

    /// Selects `minute` (kept on the ruler) and settles the ruler on it, as a
    /// click on a tick or a step of a mouse's wheel does.
    func pick(_ minute: Int) {
        select(minute)
        settle()
    }

    func step(by minutes: Int) {
        pick(model.setterMinutes + minutes)
    }

    /// Only user input gets here, so only it taps the trackpad: the value the
    /// picker opens on, or one a start remembers, changes `setterMinutes` directly.
    private func select(_ minute: Int) {
        let minute = CountdownTimer.clampedSetterMinutes(minute)
        guard minute != model.setterMinutes else { return }
        model.selectSetter(minute)
        // A step of a value, as Apple describes `.levelChange`. macOS plays it
        // only on a Force Touch trackpad, and only while a finger is on it: not
        // during a swipe's momentum, nor for a mouse.
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }
}

/// The idle timer's tab: the selected minutes, the ruler that picks them, and
/// Start.
struct TimerPickerView: View {
    let picker: TimerPicker

    var body: some View {
        let minutes = picker.model.setterMinutes
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(minutes)")
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .foregroundStyle(NotchTheme.headline())
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.2), value: minutes)
                Text(localized(en: "min", zh: "分钟"))
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(NotchTheme.secondaryText)
            }
            .lineLimit(1)

            MinuteRulerView(picker: picker)

            GlassCapsuleButton(localized(en: "Start", zh: "开始"), symbol: "play.fill") {
                picker.model.start(minutes: picker.model.setterMinutes)
            }
            .disabled(minutes == 0)
            .opacity(minutes == 0 ? 0.4 : 1)
        }
    }
}

/// The ruler: a tick per minute sliding under the fixed center, where the
/// selected one stands tallest in the timer's color, and fading out at the edges.
/// An AppKit overlay takes the scrolling, dragging, and clicks
/// (`MinuteRulerInput`).
private struct MinuteRulerView: View {
    let picker: TimerPicker

    var body: some View {
        let position = picker.position
        let selected = picker.model.setterMinutes
        ZStack {
            ForEach(CountdownTimer.setterMinutes, id: \.self) { minute in
                Capsule()
                    .fill(tickStyle(minute: minute, selected: selected))
                    .frame(width: MinuteRuler.tickWidth, height: MinuteRuler.height(ofTick: minute, position: position))
                    .offset(x: CGFloat(Double(minute) - position) * MinuteRuler.spacing)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: MinuteRuler.selectedTickHeight)
        .clipped()
        .mask {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.3),
                    .init(color: .black, location: 0.7),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
        .overlay {
            MinuteRulerInput(picker: picker)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(localized(en: "Duration", zh: "时长"))
        .accessibilityValue(localized(en: "\(selected) min", zh: "\(selected) 分钟"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: picker.step(by: 1)
            case .decrement: picker.step(by: -1)
            @unknown default: break
            }
        }
    }

    private func tickStyle(minute: Int, selected: Int) -> AnyShapeStyle {
        if minute == selected {
            return timerStyle()
        }
        return AnyShapeStyle(minute % MinuteRuler.majorInterval == 0 ? NotchTheme.primaryText.opacity(0.75) : NotchTheme.secondaryText)
    }
}

/// Covers the ruler to take its input in AppKit, where a scroll's phases tell
/// when the fingers lift and its momentum ends, so the ruler settles on a whole
/// minute exactly when the movement stops.
private struct MinuteRulerInput: NSViewRepresentable {
    let picker: TimerPicker

    func makeNSView(context: Context) -> MinuteRulerInputView {
        let view = MinuteRulerInputView()
        view.picker = picker
        return view
    }

    func updateNSView(_ view: MinuteRulerInputView, context: Context) {
        view.picker = picker
    }
}

/// - Two-finger scrolling on a trackpad moves the ruler with the fingers, left
///   and right, and its momentum carries it on; it settles once momentum stops,
///   or when the fingers lift without any.
/// - A mouse's wheel, which reports no phases, steps a minute per notch.
/// - Dragging moves the ruler with the pointer; a click selects the tick under it.
private final class MinuteRulerInputView: NSView {
    var picker: TimerPicker?
    /// Where the press began, and where the ruler stood then.
    private var press: (x: CGFloat, position: Double)?
    private var isDragging = false
    /// Settles a scroll whose fingers lifted, unless momentum begins first.
    private var pendingSettle: Task<Void, Never>?
    /// How long after the fingers lift to wait for momentum to begin; it follows
    /// the lift within a frame or two.
    private static let momentumGrace: Duration = .milliseconds(70)
    /// How far the pointer must travel with the button down before a drag starts.
    private static let dragThreshold: CGFloat = 3

    // The island panel is never key, so the first click must already count.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        // The island collapsed (or the tab left) mid-gesture: the gesture's end
        // would never reach the view, and a leftover fraction would later override
        // the model's minute.
        guard newWindow == nil else { return }
        pendingSettle?.cancel()
        pendingSettle = nil
        press = nil
        isDragging = false
        picker?.reset()
    }

    override func scrollWheel(with event: NSEvent) {
        guard let picker else { return }
        if event.phase.isEmpty, event.momentumPhase.isEmpty {
            // A wheel: a notch that would move content left or up brings the
            // next minute, as the trackpad's ticks move left for larger ones.
            let delta = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) ? event.scrollingDeltaX : event.scrollingDeltaY
            if delta != 0 {
                picker.step(by: delta < 0 ? 1 : -1)
            }
            return
        }
        // Only the horizontal part: a mostly vertical swipe barely moves it.
        if event.scrollingDeltaX != 0 {
            let points = event.hasPreciseScrollingDeltas ? event.scrollingDeltaX : event.scrollingDeltaX * MinuteRuler.spacing
            picker.move(by: points)
        }
        // Momentum carries the ruler on from where it is, fraction included, and
        // it settles where the momentum ends. Fingers that lift settle it only
        // when no momentum begins within `momentumGrace`.
        pendingSettle?.cancel()
        pendingSettle = nil
        if event.phase.contains(.cancelled)
            || event.momentumPhase.contains(.ended) || event.momentumPhase.contains(.cancelled) {
            picker.settle()
        } else if event.phase.contains(.ended) {
            pendingSettle = Task { [weak self] in
                try? await Task.sleep(for: Self.momentumGrace)
                guard !Task.isCancelled, let self else { return }
                self.pendingSettle = nil
                self.picker?.settle()
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard let picker else { return }
        press = (x: convert(event.locationInWindow, from: nil).x, position: picker.position)
        isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let picker, let press else { return }
        let travel = convert(event.locationInWindow, from: nil).x - press.x
        if !isDragging {
            guard abs(travel) >= Self.dragThreshold else { return }
            isDragging = true
        }
        picker.move(to: MinuteRuler.position(press.position, movedBy: travel))
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            press = nil
            isDragging = false
        }
        guard let picker, let press else { return }
        if isDragging {
            picker.settle()
        } else {
            let x = convert(event.locationInWindow, from: nil).x
            picker.pick(MinuteRuler.minute(atOffset: x - bounds.midX, from: press.position))
        }
    }
}

import Foundation
import NotchKit
import NotchUI
import SwiftUI

/// The clock and a countdown timer. The timer has a tab right of the notch, where
/// a ruler picks the minutes while idle; the clock is a Home module whose card
/// opens that tab, and the island's right-click menu starts and controls the
/// timer. While a timer counts down or rings, its tab reports itself active, so
/// the header's folded right-side button shows its ring or bell. Its ring and
/// time show as wings beside the notch for a few seconds of the collapsed island
/// after starting, then as a band of light around the island that shrinks with
/// the time left. When it runs out a bell rings until dismissed.
@MainActor
public final class ClockFeature: NotchFeature {
    public let id = "clock"
    public var title: String { localized(en: "Timer", zh: "计时器") }
    public let symbol = "timer"
    public let tabPlacement = NotchTabPlacement.trailing
    /// While a timer counts down or rings.
    public var isTabActive: Bool { model.phase != .idle }

    static let countdownActivityID = "countdown"
    static let countdownRimActivityID = "countdown-rim"
    static let finishedActivityID = "finished"
    /// The band's: above Now Playing (`.normal`), below the brief notices (`.high`).
    static let countdownPriority = NotchActivity.Priority(60)
    /// The countdown wings', just above the band, which shows once they expire.
    static let countdownWingsPriority = NotchActivity.Priority(61)
    /// Seconds the countdown wings show on the collapsed island after a start.
    static let wingsDuration: TimeInterval = 5

    let model: TimerModel
    private weak var context: (any NotchContext)?

    public convenience init() {
        self.init(defaults: .standard)
    }

    /// `defaults` holds the remembered duration; tests pass a domain of their own.
    init(defaults: UserDefaults) {
        model = TimerModel(defaults: defaults)
    }

    public func activate(context: any NotchContext) {
        self.context = context
        model.onEvent = { [weak self] event in
            self?.follow(event)
        }
    }

    public func deactivate() {
        model.onEvent = nil
        model.reset()
        dismissCountdown()
        context?.dismiss(activityID: Self.finishedActivityID)
        context = nil
    }

    public func makeExpandedView() -> AnyView? {
        AnyView(TimerTab(model: model, picker: TimerPicker(model: model)))
    }

    public func makeTabIcon() -> AnyView? {
        AnyView(TimerTabIcon(model: model))
    }

    public func makeHomeModules() -> [NotchHomeModule] {
        [TimeModule.makeModule(timer: model) { [weak self] in
            self?.showTimer()
        }]
    }

    public var menuItems: [NotchMenuItem] {
        let items: [NotchMenuItem]
        switch model.phase {
        case .idle:
            items = CountdownTimer.presetMinutes.map { minutes in
                .button(presetTitle(minutes: minutes)) { [model] in
                    model.start(minutes: minutes)
                }
            } + [
                .divider,
                // The tab's picker.
                .button(localized(en: "Custom…", zh: "自定义…"), symbol: "slider.horizontal.3") { [weak self] in
                    self?.context?.requestExpand()
                },
            ]
        case .counting(let timer):
            items = [
                timer.isPaused
                    ? .button(localized(en: "Resume", zh: "继续"), symbol: "play.fill") { [model] in
                        model.togglePause()
                    }
                    : .button(localized(en: "Pause", zh: "暂停"), symbol: "pause.fill") { [model] in
                        model.togglePause()
                    },
                .button(localized(en: "Add 1 Minute", zh: "加 1 分钟"), symbol: "plus") { [model] in
                    model.addMinute()
                },
                .button(localized(en: "Cancel Timer", zh: "取消计时"), symbol: "xmark") { [model] in
                    model.cancel()
                },
                .divider,
                .button(localized(en: "Show Timer…", zh: "显示计时器…"), symbol: "timer") { [weak self] in
                    self?.context?.requestExpand()
                },
            ]
        case .finished:
            items = [
                .button(localized(en: "Stop Alert", zh: "停止提醒"), symbol: "bell.slash") { [model] in
                    model.stopAlert()
                },
                .button(localized(en: "Restart", zh: "再来一次"), symbol: "arrow.counterclockwise") { [model] in
                    model.restart()
                },
            ]
        }
        return [.submenu(localized(en: "Timer", zh: "计时器"), symbol: "timer", items: items)]
    }

    /// Timers that start at once without touching the remembered duration, and
    /// the ringing state, for checking the wings, band, tab, and bell.
    public var debugItems: [NotchMenuItem] {
        var items: [NotchMenuItem] = [
            .button(localized(en: "Start a 10-Second Timer", zh: "开始 10 秒计时"), symbol: "timer") { [model] in
                model.start(duration: 10, remembering: false)
            },
            .button(localized(en: "Start a 5-Minute Timer", zh: "开始 5 分钟计时"), symbol: "timer") { [model] in
                model.start(duration: 5 * 60, remembering: false)
            },
            // The long h:mm:ss layout of the wings and the tab.
            .button(localized(en: "Start a 1-Hour 5-Minute Timer", zh: "开始 1 小时 5 分钟计时"), symbol: "timer") { [model] in
                model.start(duration: 65 * 60, remembering: false)
            },
            .button(localized(en: "Ring Now", zh: "立刻响铃"), symbol: "bell.fill") { [model] in
                model.startFinished()
            },
        ]
        if model.phase != .idle {
            items.append(.divider)
            items.append(.button(localized(en: "Cancel Timer", zh: "取消计时"), symbol: "xmark") { [model] in
                // Each does nothing unless the timer is in its phase.
                model.cancel()
                model.stopAlert()
            })
        }
        return items
    }

    /// Opens the timer's tab: its picker while idle, else the timer.
    private func showTimer() {
        // The card shows only in the open panel, so this switches tabs.
        withAnimation(NotchTheme.tabSwitchAnimation) {
            context?.requestExpand()
        }
    }

    private func follow(_ event: TimerModel.Event) {
        switch event {
        case .started:
            context?.dismiss(activityID: Self.finishedActivityID)
            dismissCountdown()
            // Presented once per start: the wings and the band observe the model,
            // so pausing and adding time update them in place. Presenting again
            // would replace the views and restart their transitions.
            presentRim()
            // Over the band until they expire. They hold while the island is
            // open, so a timer started from the tab's picker shows them once
            // the island closes.
            let remaining = if case .counting(let timer) = model.phase { timer.remaining(at: Date()) } else { 0.0 }
            context?.present(NotchActivity(
                id: Self.countdownActivityID,
                priority: Self.countdownWingsPriority,
                duration: Self.wingsDuration,
                wingWidth: CountdownWings.width(remaining: remaining),
                leadingWingWidth: CountdownWings.leadingWidth,
                holdsWhileExpanded: true
            ) { [model] in
                CountdownWingLeading(model: model) { [weak self] in
                    self?.context?.requestExpand()
                }
            } trailing: { [model] in
                CountdownWingTrailing(model: model, timeWidth: CountdownWings.timeWidth(remaining: remaining)) { [weak self] in
                    self?.context?.requestExpand()
                }
            })
        case .finished:
            dismissCountdown()
            context?.present(NotchActivity(
                id: Self.finishedActivityID,
                priority: .high,
                wingWidth: finishedWingWidth
            ) { [model] in
                FinishedWingLeading(stop: model.stopAlert)
            } trailing: { [model] in
                FinishedWingTrailing(stop: model.stopAlert)
            })
        case .ended:
            dismissCountdown()
            context?.dismiss(activityID: Self.finishedActivityID)
        }
    }

    /// The band around the island, under the countdown wings: the share of the
    /// time left, dimmed while paused.
    private func presentRim() {
        context?.present(NotchActivity(
            id: Self.countdownRimActivityID,
            priority: Self.countdownPriority,
            rim: NotchActivityRim(
                color: timerColor,
                fraction: { [model] now in
                    guard case .counting(let timer) = model.phase else { return 0 }
                    return timer.progress(at: now)
                },
                isDimmed: { [model] in
                    guard case .counting(let timer) = model.phase else { return false }
                    return timer.isPaused
                }
            )
        ))
    }

    /// Removes the countdown's wings and band.
    private func dismissCountdown() {
        context?.dismiss(activityID: Self.countdownActivityID)
        context?.dismiss(activityID: Self.countdownRimActivityID)
    }
}

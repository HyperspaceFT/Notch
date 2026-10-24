import Foundation
import NotchKit
import NotchUI
import SwiftUI

/// The clock and a countdown timer. No tab: the clock is a Home module whose
/// card opens the timer's panel (a detail), and the island's right-click menu
/// starts and controls the timer. While a timer counts down its ring and time
/// show as wings beside the notch; when it runs out a bell rings until dismissed.
@MainActor
public final class ClockFeature: NotchFeature {
    public let id = "clock"
    public var title: String { localized(en: "Clock", zh: "时钟") }
    public let symbol = "clock"

    static let countdownActivityID = "countdown"
    static let finishedActivityID = "finished"
    /// Above Now Playing (`.normal`), below the brief notices (`.high`).
    static let countdownPriority = NotchActivity.Priority(60)

    private let model: TimerModel
    private weak var context: (any NotchContext)?

    public init() {
        model = TimerModel(defaults: .standard)
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
        context?.dismiss(activityID: Self.countdownActivityID)
        context?.dismiss(activityID: Self.finishedActivityID)
        context = nil
    }

    public func makeHomeModules() -> [NotchHomeModule] {
        [TimeModule.makeModule(timer: model) { [weak self] in
            self?.openPanel()
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
                .button(localized(en: "Custom…", zh: "自定义…"), symbol: "slider.horizontal.3") { [weak self] in
                    self?.openPanel()
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
                    self?.openPanel()
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

    /// Opens the island on the timer's panel, in whatever state the timer is.
    private func openPanel() {
        context?.requestExpand(detail: AnyView(TimerPanel(model: model) { [weak self] in
            // Back to the tabs, on the one shown before: Home when the panel came
            // from the clock card, which now shows the countdown.
            self?.context?.requestExpand()
        }))
    }

    private func follow(_ event: TimerModel.Event) {
        switch event {
        case .started:
            context?.dismiss(activityID: Self.finishedActivityID)
            // Presented once per start: the wings observe the model, so pausing and
            // adding time update them in place. Presenting again would replace the
            // views and restart their transitions.
            context?.present(NotchActivity(
                id: Self.countdownActivityID,
                priority: Self.countdownPriority,
                wingWidth: countdownWingWidth
            ) { [model] in
                CountdownWingLeading(model: model) { [weak self] in
                    self?.openPanel()
                }
            } trailing: { [model] in
                CountdownWingTrailing(model: model) { [weak self] in
                    self?.openPanel()
                }
            })
        case .finished:
            context?.dismiss(activityID: Self.countdownActivityID)
            context?.present(NotchActivity(
                id: Self.finishedActivityID,
                priority: .high,
                wingWidth: countdownWingWidth
            ) { [model] in
                FinishedWingLeading(stop: model.stopAlert)
            } trailing: { [model] in
                FinishedWingTrailing(stop: model.stopAlert)
            })
        case .ended:
            context?.dismiss(activityID: Self.countdownActivityID)
            context?.dismiss(activityID: Self.finishedActivityID)
        }
    }
}

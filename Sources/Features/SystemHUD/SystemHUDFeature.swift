import NotchKit
import NotchUI
import Observation
import SwiftUI

/// Replaces the macOS volume and brightness HUD: intercepts the media keys,
/// changes the level itself, and shows it as an activity beside the notch.
/// Keys whose target Notch cannot control pass through to the system unchanged.
@MainActor
public final class SystemHUDFeature: NotchFeature {
    public let id = "system-hud"
    public var title: String { localized(en: "Volume & Brightness", zh: "音量与亮度") }
    public let symbol = "speaker.wave.2.fill"

    /// How long the level activity stays visible after the last key press.
    static let activityDuration: TimeInterval = 1.5
    /// How often Accessibility access is checked again while it is missing.
    static let accessPollInterval: Duration = .seconds(2)

    private let settings = SystemHUDSettings.shared
    private let model = LevelHUDModel()
    private var tap: MediaKeyTap?
    private var accessPoll: Task<Void, Never>?
    /// The volume Notch set last; see `LevelStep.origin`.
    private var lastSetVolume: Float?
    /// Bumped on activate and deactivate; an observation armed under another
    /// generation is stale and does nothing when it fires.
    private var observationGeneration = 0
    private weak var context: (any NotchContext)?

    public init() {}

    public func activate(context: any NotchContext) {
        self.context = context
        observationGeneration += 1
        followSettings(generation: observationGeneration)
    }

    public func deactivate() {
        // `withObservationTracking` cannot be cancelled; the new generation makes
        // its pending change handler a no-op.
        observationGeneration += 1
        stopInterception()
        context = nil
    }

    /// Starts or stops interception to match `isEnabled`, again on every change.
    private func followSettings(generation: Int) {
        guard generation == observationGeneration else { return }
        let isEnabled = withObservationTracking {
            settings.isEnabled
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.followSettings(generation: generation)
            }
        }
        if isEnabled {
            startInterception()
        } else {
            stopInterception()
        }
    }

    private func startInterception() {
        guard tap == nil else { return }
        settings.refreshAccessibilityAccess()
        if settings.hasAccessibilityAccess, startTap() {
            accessPoll?.cancel()
            accessPoll = nil
            return
        }
        if !settings.hasAccessibilityAccess {
            settings.promptForAccessibilityAccessOnce()
        }
        // Also polls while trusted but the tap failed, to retry creating it.
        startPolling()
    }

    private func stopInterception() {
        tap?.stop()
        tap = nil
        accessPoll?.cancel()
        accessPoll = nil
    }

    private func startTap() -> Bool {
        let tap = MediaKeyTap { [weak self] key, step in
            self?.handle(key, step: step) ?? false
        }
        guard tap.start() else { return false }
        self.tap = tap
        return true
    }

    private func startPolling() {
        guard accessPoll == nil else { return }
        accessPoll = Task { [weak self] in
            while true {
                try? await Task.sleep(for: Self.accessPollInterval)
                guard !Task.isCancelled, let self else { return }
                settings.refreshAccessibilityAccess()
                if settings.hasAccessibilityAccess, tap == nil, startTap() {
                    accessPoll = nil
                    return
                }
            }
        }
    }

    /// Acts on a key down; `false` lets the system handle the key instead.
    private func handle(_ event: MediaKeyEvent, step: Float) -> Bool {
        switch event.key {
        case .soundUp, .soundDown:
            guard
                let output = SystemVolume.defaultOutput(),
                output.canSetVolume,
                let current = output.volume
            else { return false }
            if output.isMuted == true {
                output.setMuted(false)
            }
            let origin = LevelStep.origin(current: current, lastSet: lastSetVolume, step: step)
            let level = event.key == .soundUp
                ? LevelStep.up(from: origin, step: step)
                : LevelStep.down(from: origin, step: step)
            output.setVolume(level)
            lastSetVolume = level
            show(.volume, level: level, isMuted: level == 0)

        case .mute:
            guard
                let output = SystemVolume.defaultOutput(),
                output.canSetMute,
                var isMuted = output.isMuted
            else { return false }
            // Holding the key would otherwise toggle it on and off.
            if !event.isRepeat {
                isMuted.toggle()
                output.setMuted(isMuted)
            }
            let level = output.volume ?? 0
            show(.volume, level: level, isMuted: isMuted || level == 0)

        case .brightnessUp, .brightnessDown:
            guard let display = DisplayBrightness.builtIn() else { return false }
            let level = event.key == .brightnessUp
                ? LevelStep.up(from: display.brightness, step: step)
                : LevelStep.down(from: display.brightness, step: step)
            display.setBrightness(level)
            show(.brightness, level: level, isMuted: false)
        }
        return true
    }

    private func show(_ kind: LevelHUDModel.Kind, level: Float, isMuted: Bool) {
        model.kind = kind
        model.level = Double(level)
        model.isMuted = isMuted
        // Presenting the same id again replaces it in place and restarts its timer;
        // the wings observe `model`, so they update rather than appear anew.
        context?.present(NotchActivity(
            id: "level",
            priority: .high,
            duration: Self.activityDuration
        ) { [model] in
            LevelHUDLeading(model: model)
        } trailing: { [model] in
            LevelHUDTrailing(model: model)
        })
    }
}

@MainActor
@Observable
final class LevelHUDModel {
    enum Kind {
        case volume
        case brightness
    }

    var kind = Kind.volume
    /// 0…1.
    var level: Double = 0
    var isMuted = false

    var progress: Double { isMuted ? 0 : level }
}

private struct LevelHUDLeading: View {
    let model: LevelHUDModel

    var body: some View {
        symbol
            .foregroundStyle(NotchTheme.primaryText)
            .contentTransition(.symbolEffect(.replace))
            .animation(.snappy(duration: 0.2), value: model.kind)
            .animation(.snappy(duration: 0.2), value: model.isMuted)
    }

    /// One `Image` whose symbol changes, not one view per branch, so the
    /// replace transition animates between symbols.
    private var symbol: Image {
        switch model.kind {
        case .volume:
            model.isMuted
                ? Image(systemName: "speaker.slash.fill")
                : Image(systemName: "speaker.wave.3.fill", variableValue: model.level)
        case .brightness:
            Image(systemName: "sun.max.fill")
        }
    }
}

/// A ring filling clockwise from 12 o'clock with the level.
private struct LevelHUDTrailing: View {
    let model: LevelHUDModel

    private static let diameter: CGFloat = 18
    private static let lineWidth: CGFloat = 3

    var body: some View {
        ZStack {
            Circle()
                .stroke(NotchTheme.primaryText.opacity(0.2), lineWidth: Self.lineWidth)
            Circle()
                .trim(from: 0, to: model.progress)
                .stroke(NotchTheme.primaryText, style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        // The stroke is centred on the path, so inset it to keep the outer edge at the diameter.
        .padding(Self.lineWidth / 2)
        .frame(width: Self.diameter, height: Self.diameter)
        .animation(.snappy(duration: 0.2), value: model.progress)
    }
}

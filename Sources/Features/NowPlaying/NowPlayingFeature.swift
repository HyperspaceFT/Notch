import NotchKit
import NotchUI
import SwiftUI

/// Shows the track the system is playing, from any app (a browser tab, Music,
/// Spotify, ...), as an activity beside the notch: its cover on the left, a pulse
/// that plays and pauses it on the right. It stays for a while after a pause, then
/// leaves. No tab in the expanded panel.
///
/// With "Read Now Playing from Any App" on (`NowPlayingSettings`, off by default),
/// the track comes from the bundled MediaRemote adapter. Otherwise, or where the
/// adapter cannot run, Music and Spotify are read through their own scripting
/// dictionaries instead.
@MainActor
public final class NowPlayingFeature: NotchFeature {
    public let id = "now-playing"
    public var title: String { localized(en: "Now Playing", zh: "正在播放") }
    public let symbol = "music.note"

    static let activityID = "track"

    private let scripting = PlayerScripting()
    private let settings = NowPlayingSettings.shared
    private let model: NowPlayingModel
    /// The MediaRemote adapter's stream; `nil` when it is not in use.
    private var mediaRemote: MediaRemoteMonitor?
    private var systemSnapshot: PlaybackSnapshot?
    /// The scripting fallback; `nil` while the adapter's stream is in use.
    private var monitor: NowPlayingMonitor?
    private var snapshots: [SupportedPlayer: PlaybackSnapshot] = [:]
    private var presence = PresenceTracker()
    private var isPresented = false
    /// Hides a paused track once its linger runs out.
    private var lingerTask: Task<Void, Never>?
    /// Bumped on activate and deactivate; work that finishes under another
    /// generation is stale and does nothing.
    private var generation = 0
    private weak var context: (any NotchContext)?

    public init() {
        model = NowPlayingModel(scripting: scripting)
    }

    public func activate(context: any NotchContext) {
        self.context = context
        generation += 1
        model.onToggle = { [weak self] shown in
            self?.toggle(shown)
        }
        followSettings(generation: generation)
    }

    public func deactivate() {
        // Also turns the pending settings change handler into a no-op:
        // `withObservationTracking` cannot be cancelled.
        generation += 1
        stopSources()
        lingerTask?.cancel()
        lingerTask = nil
        if isPresented {
            context?.dismiss(activityID: Self.activityID)
        }
        isPresented = false
        snapshots = [:]
        presence = PresenceTracker()
        model.onToggle = nil
        model.reset()
        context = nil
    }

    public func makeExpandedView() -> AnyView? { nil }

    /// Picks the source to match `usesMediaRemote`, again on every change.
    private func followSettings(generation: Int) {
        guard generation == self.generation else { return }
        let usesMediaRemote = withObservationTracking {
            settings.usesMediaRemote
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.followSettings(generation: generation)
            }
        }
        stopSources()
        if usesMediaRemote, let adapter = MediaRemoteAdapter.bundled() {
            let mediaRemote = MediaRemoteMonitor(adapter: adapter) { [weak self] snapshot in
                self?.systemChanged(snapshot)
            } onUnavailable: { [weak self] in
                self?.mediaRemoteUnavailable()
            }
            self.mediaRemote = mediaRemote
            mediaRemote.start()
        } else {
            startScripting()
        }
        // What the previous source said no longer counts.
        update()
    }

    private func stopSources() {
        mediaRemote?.stop()
        mediaRemote = nil
        systemSnapshot = nil
        monitor?.stop()
        monitor = nil
        snapshots = [:]
    }

    private func startScripting() {
        let monitor = NowPlayingMonitor(scripting: scripting) { [weak self] player, snapshot in
            self?.playerChanged(player, snapshot)
        }
        self.monitor = monitor
        monitor.start()
    }

    private func systemChanged(_ snapshot: PlaybackSnapshot?) {
        systemSnapshot = snapshot
        update()
    }

    /// The adapter cannot run on this Mac: read Music and Spotify directly instead.
    private func mediaRemoteUnavailable() {
        mediaRemote?.stop()
        mediaRemote = nil
        systemSnapshot = nil
        startScripting()
        update()
    }

    private func playerChanged(_ player: SupportedPlayer, _ snapshot: PlaybackSnapshot?) {
        snapshots[player] = snapshot
        update()
    }

    private func toggle(_ shown: PlaybackSnapshot) {
        // The model already flipped its copy; follow it until the player answers.
        guard let player = shown.player else {
            toggleSystemPlayback()
            return
        }
        snapshots[player]?.isPlaying.toggle()
        update()
        monitor?.toggle(player)
    }

    private func toggleSystemPlayback() {
        systemSnapshot?.isPlaying.toggle()
        update()
        guard let mediaRemote else { return }
        Task {
            await mediaRemote.togglePlayPause()
        }
    }

    private func update() {
        let current = systemSnapshot
            ?? PlaybackSnapshot.current(from: snapshots, preferring: model.snapshot?.player)
        presence.update(current, now: Date())
        model.show(current)
        followPresence()
    }

    private func followPresence() {
        let now = Date()
        let isVisible = presence.isVisible(at: now)
        if isVisible, !isPresented {
            isPresented = true
            // Presented once per appearance: the wings observe the model, so later
            // track, cover, and play-state changes update them in place. Presenting
            // again would replace the views and restart their transitions.
            context?.present(NotchActivity(id: Self.activityID, priority: .normal) { [model] in
                NowPlayingSleeve(model: model)
            } trailing: { [model] in
                NowPlayingPulse(model: model)
            })
        } else if !isVisible, isPresented {
            isPresented = false
            context?.dismiss(activityID: Self.activityID)
        }

        lingerTask?.cancel()
        lingerTask = nil
        guard isVisible, let hideDate = presence.hideDate else { return }
        let generation = generation
        lingerTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(hideDate.timeIntervalSince(now), 0)))
            guard !Task.isCancelled, let self, generation == self.generation else { return }
            lingerTask = nil
            followPresence()
        }
    }
}

import NotchKit
import NotchUI
import SwiftUI

/// Shows the track the system is playing, from any app (a browser tab, Music,
/// Spotify, ...), as an activity beside the notch: its cover on the left, a pulse
/// that plays and pauses it on the right. It stays for a while after a pause, then
/// leaves. While any track is known, playing or paused, a tab in the expanded
/// panel shows it in full, with its progress and the transport controls.
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
    public var isTabAvailable: Bool { model.hasTrack }

    static let activityID = "track"

    private let scripting = PlayerScripting()
    private let settings = NowPlayingSettings.shared
    private let model: NowPlayingModel
    /// The MediaRemote adapter's stream; `nil` when it is not in use.
    private var mediaRemote: MediaRemoteMonitor?
    private var systemSnapshot: PlaybackSnapshot?
    /// The Debug pane's sample track, shown over every real source until it is
    /// stopped; commands on it change only it.
    private var sampleSnapshot: PlaybackSnapshot?
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
        model.onCommand = { [weak self] command, shown in
            self?.perform(command, shown: shown)
        }
        model.onOpenDetail = { [weak self] in
            self?.context?.requestExpand()
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
        sampleSnapshot = nil
        presence = PresenceTracker()
        model.onCommand = nil
        model.onOpenDetail = nil
        model.reset()
        context = nil
    }

    public func makeExpandedView() -> AnyView? {
        AnyView(NowPlayingDetailView(model: model))
    }

    /// A sample track over the real ones, for checking the wings, the cover's
    /// flight into the tab, and the tab; its controls act on the sample alone.
    public var debugItems: [NotchMenuItem] {
        var items: [NotchMenuItem] = [
            .button(localized(en: "Play a Sample Track", zh: "播放示例曲目"), symbol: "play.fill") { [weak self] in
                self?.showSample(NowPlayingSample.track(now: Date()))
            },
            .button(localized(en: "Sample with a Long Title", zh: "长标题示例"), symbol: "text.append") { [weak self] in
                self?.showSample(NowPlayingSample.longTitle(now: Date()))
            },
        ]
        if model.isShowingSample {
            items.append(contentsOf: [
                .button(localized(en: "Pause the Sample", zh: "暂停示例曲目"), symbol: "pause.fill") { [weak self] in
                    self?.pauseSample()
                },
                .divider,
                .button(localized(en: "Stop the Sample", zh: "停止示例"), symbol: "stop.fill") { [weak self] in
                    self?.showSample(nil)
                },
            ])
        }
        return items
    }

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

    private func perform(_ command: PlaybackCommand, shown: PlaybackSnapshot) {
        // The model already changed its copy; follow it until the player answers.
        let now = Date()
        // The sample is all that shows while there is one: nothing reaches a real player.
        if let sample = sampleSnapshot {
            switch command {
            case .next, .previous:
                sampleSnapshot = NowPlayingSample.other(than: sample, now: now)
            case .playPause, .seek:
                sampleSnapshot?.apply(command, at: now)
            }
            update()
            return
        }
        guard let player = shown.player else {
            performOnSystemPlayer(command, at: now)
            return
        }
        snapshots[player]?.apply(command, at: now)
        update()
        monitor?.perform(command, on: player)
    }

    private func performOnSystemPlayer(_ command: PlaybackCommand, at now: Date) {
        systemSnapshot?.apply(command, at: now)
        update()
        guard let mediaRemote else { return }
        Task {
            await mediaRemote.perform(command)
        }
    }

    /// Shows `sample` over the real sources; `nil` shows them again.
    private func showSample(_ sample: PlaybackSnapshot?) {
        sampleSnapshot = sample
        update()
    }

    private func pauseSample() {
        guard sampleSnapshot?.isPlaying == true else { return }
        sampleSnapshot?.setPlaying(false, at: Date())
        update()
    }

    private func update() {
        let current = Self.shown(
            sample: sampleSnapshot,
            system: systemSnapshot,
            players: snapshots,
            preferring: model.snapshot?.player
        )
        presence.update(current, now: Date())
        model.show(current, isSample: sampleSnapshot != nil)
        followPresence()
    }

    /// The snapshot to show: the Debug pane's sample while there is one, else
    /// the system's, else the scripted players' (`PlaybackSnapshot.current`).
    static func shown(
        sample: PlaybackSnapshot?,
        system: PlaybackSnapshot?,
        players: [SupportedPlayer: PlaybackSnapshot],
        preferring preferred: SupportedPlayer?
    ) -> PlaybackSnapshot? {
        sample ?? system ?? PlaybackSnapshot.current(from: players, preferring: preferred)
    }

    private func followPresence() {
        let now = Date()
        let isVisible = presence.isVisible(at: now)
        if isVisible, !isPresented {
            isPresented = true
            // Presented once per appearance: the wings observe the model, so later
            // track, cover, and play-state changes update them in place. Presenting
            // again would replace the views and restart their transitions.
            // The cover and the wave fly into the tab and back (`notchMorphHero`).
            context?.present(NotchActivity(
                id: Self.activityID,
                priority: .normal,
                wingWidth: nowPlayingWingWidth,
                morphsIntoTab: true
            ) { [model] in
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

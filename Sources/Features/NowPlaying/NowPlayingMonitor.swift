import AppKit
import Foundation

/// Follows what each supported player plays and calls `onChange` on the main
/// actor with every fresh reading (`nil` = nothing playing).
///
/// The players' distributed notifications say right away that something changed,
/// without any permission; Apple events then read the authoritative state. A poll
/// every `pollInterval` catches what a missed notification would leave stale.
/// While the user has not allowed Apple events, the notifications' own text is
/// all there is, so it stands in for the read.
@MainActor
final class NowPlayingMonitor {
    static let pollInterval: Duration = .seconds(3)
    /// Players post several notifications for one change; read once they settle.
    static let debounce: Duration = .milliseconds(150)

    private let scripting: PlayerScripting
    private let onChange: @MainActor (SupportedPlayer, PlaybackSnapshot?) -> Void
    private var receiver: DistributedNotificationReceiver?
    private var terminationObserver: NSObjectProtocol?
    private var poll: Task<Void, Never>?
    private var debounces: [SupportedPlayer: Task<Void, Never>] = [:]
    /// Players with a read on the scripting queue, and those to read again once it
    /// is back, so a slow player (or a pending Automation prompt) does not pile up reads.
    private var reading: Set<SupportedPlayer> = []
    private var readAgain: Set<SupportedPlayer> = []
    /// The last notification's text per player, for when Apple events are refused.
    private var notified: [SupportedPlayer: PlaybackSnapshot] = [:]
    /// Per player, bumped by every `toggle`: a read that started before one still
    /// carries the old play state and is dropped, so it cannot undo what the user just did.
    private var toggleEpochs: [SupportedPlayer: Int] = [:]
    /// Bumped on start and stop; a read that returns under another generation is dropped.
    private var generation = 0

    init(scripting: PlayerScripting, onChange: @escaping @MainActor (SupportedPlayer, PlaybackSnapshot?) -> Void) {
        self.scripting = scripting
        self.onChange = onChange
    }

    isolated deinit {
        stop()
    }

    func start() {
        guard poll == nil else { return }
        generation += 1

        let receiver = DistributedNotificationReceiver { [weak self] player, info in
            Task { @MainActor in
                self?.notificationArrived(from: player, info: info)
            }
        }
        receiver.register()
        self.receiver = receiver

        // A quit player posts nothing; drop its track at once rather than at the next poll.
        terminationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard let player = app?.bundleIdentifier.flatMap(SupportedPlayer.init(bundleIdentifier:)) else { return }
            Task { @MainActor in
                self?.refreshSoon(player)
            }
        }

        poll = Task { [weak self] in
            while true {
                try? await Task.sleep(for: Self.pollInterval)
                guard !Task.isCancelled, let self else { return }
                refreshAll()
            }
        }
        refreshAll()
    }

    private func refreshAll() {
        for player in SupportedPlayer.allCases {
            refresh(player)
        }
    }

    func stop() {
        generation += 1
        receiver?.unregister()
        receiver = nil
        if let terminationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(terminationObserver)
        }
        terminationObserver = nil
        poll?.cancel()
        poll = nil
        for task in debounces.values {
            task.cancel()
        }
        debounces = [:]
        reading = []
        readAgain = []
        notified = [:]
        toggleEpochs = [:]
    }

    /// Plays or pauses `player`, then reads it again to show what it really did.
    /// The command is queued at once, ahead of every later read, so only reads
    /// already under way can still report the old state; those are dropped.
    func toggle(_ player: SupportedPlayer) {
        guard poll != nil, player.isRunning else { return }
        toggleEpochs[player, default: 0] += 1
        let generation = generation
        scripting.toggle(player) { [weak self] in
            Task { @MainActor in
                guard let self, generation == self.generation else { return }
                self.refreshSoon(player)
            }
        }
    }

    /// Reads `player` again shortly, once a burst of changes has settled.
    func refreshSoon(_ player: SupportedPlayer) {
        debounces[player]?.cancel()
        debounces[player] = Task { [weak self] in
            try? await Task.sleep(for: Self.debounce)
            guard !Task.isCancelled, let self else { return }
            debounces[player] = nil
            refresh(player)
        }
    }

    private func notificationArrived(from player: SupportedPlayer, info: [String: String]) {
        guard poll != nil else { return }
        notified[player] = PlaybackSnapshot(player: player, notificationInfo: info)
        refreshSoon(player)
    }

    private func refresh(_ player: SupportedPlayer) {
        guard player.isRunning else {
            notified[player] = nil
            onChange(player, nil)
            return
        }
        guard !reading.contains(player) else {
            readAgain.insert(player)
            return
        }
        reading.insert(player)
        let generation = generation
        let epoch = toggleEpochs[player, default: 0]
        Task { [weak self, scripting] in
            let read = await scripting.readState(of: player)
            guard let self, generation == self.generation else { return }
            reading.remove(player)
            // A toggle came in while this was reading: its own refresh follows.
            if epoch == toggleEpochs[player, default: 0] {
                switch read {
                case .snapshot(let snapshot):
                    onChange(player, snapshot)
                case .notAuthorized:
                    onChange(player, notified[player])
                case .unavailable:
                    break
                }
            }
            if readAgain.remove(player) != nil {
                refresh(player)
            }
        }
    }
}

/// Receives the players' distributed notifications. The selector-based API is
/// used for its `.deliverImmediately`: AppKit suspends distributed notifications
/// for inactive apps, and Notch, an accessory app, is almost never active.
/// Delivery is not promised on any particular thread, so `onNotify` gets only
/// plain values and hops to the main actor itself.
private final class DistributedNotificationReceiver: NSObject {
    private let onNotify: @Sendable (SupportedPlayer, [String: String]) -> Void

    init(onNotify: @escaping @Sendable (SupportedPlayer, [String: String]) -> Void) {
        self.onNotify = onNotify
    }

    func register() {
        for player in SupportedPlayer.allCases {
            DistributedNotificationCenter.default().addObserver(
                self,
                selector: #selector(received(_:)),
                name: player.distributedNotificationName,
                object: nil,
                suspensionBehavior: .deliverImmediately
            )
        }
    }

    func unregister() {
        DistributedNotificationCenter.default().removeObserver(self)
    }

    @objc private func received(_ notification: Notification) {
        guard let player = SupportedPlayer(notificationName: notification.name) else { return }
        var info: [String: String] = [:]
        for key in ["Player State", "Name", "Artist", "Album"] {
            if let value = notification.userInfo?[key] {
                info[key] = "\(value)"
            }
        }
        onNotify(player, info)
    }
}

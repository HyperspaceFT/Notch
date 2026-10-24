import AppKit
import Foundation

/// The players Now Playing can read through their own scripting dictionary, with
/// Apple events. This is the fallback for when the MediaRemote adapter (see
/// `MediaRemoteAdapter`), which reports whatever app plays, cannot run; a player
/// without a dictionary (NetEase Cloud Music) cannot be read this way. Adding a
/// scriptable player means a case here with its bundle id, notification, and
/// `codes` from its .sdef.
enum SupportedPlayer: String, CaseIterable, Sendable {
    case music
    case spotify

    var bundleIdentifier: String {
        switch self {
        case .music: "com.apple.Music"
        case .spotify: "com.spotify.client"
        }
    }

    var displayName: String {
        switch self {
        case .music: "Music"
        case .spotify: "Spotify"
        }
    }

    /// Posted by the player whenever playback or the track changes.
    var distributedNotificationName: Notification.Name {
        switch self {
        case .music: Notification.Name("com.apple.Music.playerInfo")
        case .spotify: Notification.Name("com.spotify.client.PlaybackStateChanged")
        }
    }

    init?(bundleIdentifier: String) {
        guard let player = Self.allCases.first(where: { $0.bundleIdentifier == bundleIdentifier }) else { return nil }
        self = player
    }

    init?(notificationName: Notification.Name) {
        guard let player = Self.allCases.first(where: { $0.distributedNotificationName == notificationName }) else {
            return nil
        }
        self = player
    }

    /// Scripting a player that is not running could launch it, so every event is
    /// sent only after this says yes. It is asked again on the scripting queue
    /// right before sending, since a read can wait behind others there (a player
    /// quitting after that answers -600, which reads as nothing playing).
    var isRunning: Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).contains { !$0.isTerminated }
    }

    /// The four-character codes of the player's scripting dictionary.
    struct Codes: Sendable {
        /// The track's own id: Music's persistent ID, Spotify's id.
        var trackID: FourCharCode
        /// Spotify's cover address (its `artwork` property is never set); Music
        /// hands out the image itself instead, see `artworkClass`.
        var artworkURL: FourCharCode?
        /// Music's artwork element of a track, and its raw image data property.
        var artworkClass: FourCharCode?
        var artworkData: FourCharCode?
        /// Event class and id of the playpause command.
        var playPause: (eventClass: FourCharCode, eventID: FourCharCode)
        /// Event class and id of the next track command.
        var nextTrack: (eventClass: FourCharCode, eventID: FourCharCode)
        /// Event class and id of the command that goes back: Music's `back track`,
        /// which restarts the track unless it is near its start, as its own button
        /// does, and Spotify's `previous track`.
        var previousTrack: (eventClass: FourCharCode, eventID: FourCharCode)
    }

    var codes: Codes {
        switch self {
        case .music:
            Codes(
                trackID: fourCharCode("pPIS"),
                artworkURL: nil,
                artworkClass: fourCharCode("cArt"),
                artworkData: fourCharCode("pPCT"),
                playPause: (fourCharCode("hook"), fourCharCode("PlPs")),
                nextTrack: (fourCharCode("hook"), fourCharCode("Next")),
                previousTrack: (fourCharCode("hook"), fourCharCode("Back"))
            )
        case .spotify:
            Codes(
                trackID: fourCharCode("ID  "),
                artworkURL: fourCharCode("aUrl"),
                artworkClass: nil,
                artworkData: nil,
                playPause: (fourCharCode("spfy"), fourCharCode("PlPs")),
                nextTrack: (fourCharCode("spfy"), fourCharCode("Next")),
                previousTrack: (fourCharCode("spfy"), fourCharCode("Prev"))
            )
        }
    }

    /// Seconds from the track `duration` the player reports. Spotify's dictionary
    /// says seconds, but it answers in milliseconds; Music answers in seconds.
    func durationSeconds(fromReported value: Double) -> TimeInterval {
        switch self {
        case .music: value
        case .spotify: value / 1000
        }
    }
}

/// What a player's `player state` says, from its enumerator code (shared by
/// Music and Spotify).
enum PlayerState: Sendable, Equatable {
    case playing
    case paused
    /// Stopped, or anything else.
    case none

    init(enumCode: FourCharCode) {
        switch enumCode {
        case fourCharCode("kPSP"): self = .playing
        case fourCharCode("kPSp"): self = .paused
        default: self = .none
        }
    }
}

/// The four ASCII characters of an Apple event code as one number, e.g. "core".
func fourCharCode(_ text: String) -> FourCharCode {
    text.utf8.prefix(4).reduce(0) { $0 << 8 | FourCharCode($1) }
}

/// Reads and controls the players with raw Apple events (`core/getd`, `core/setd`
/// for the position, and the players' playpause and track commands), sent from serial background queues with a reply
/// timeout, so the main thread never blocks. Not `NSAppleScript`: it is
/// main-thread-only, and run off the main thread it stalled for many seconds,
/// past its own `with timeout`. Descriptors stay on the queue; only plain values
/// come back.
///
/// Each player has its own queue for state reads and commands, so a player that
/// hangs cannot hold up the other and a command is ordered against the reads
/// around it, and a second queue for artwork, which can be slow and is not urgent.
final class PlayerScripting: Sendable {
    enum StateRead: Sendable, Equatable {
        /// What the player is playing; `nil` for nothing.
        case snapshot(PlaybackSnapshot?)
        /// The user has not allowed Notch to control the player (-1743).
        case notAuthorized
        /// No answer this time (a timeout or an unexpected error); keep what was known.
        case unavailable
    }

    static let stateTimeout: TimeInterval = 2
    static let artworkTimeout: TimeInterval = 5

    private struct Queues: Sendable {
        let state: DispatchQueue
        let artwork: DispatchQueue

        init(player: SupportedPlayer) {
            let label = "io.github.hyperspaceft.notch.now-playing.scripting.\(player.rawValue)"
            state = DispatchQueue(label: label, qos: .utility)
            artwork = DispatchQueue(label: label + ".artwork", qos: .utility)
        }
    }

    private let musicQueues = Queues(player: .music)
    private let spotifyQueues = Queues(player: .spotify)

    private func queues(for player: SupportedPlayer) -> Queues {
        switch player {
        case .music: musicQueues
        case .spotify: spotifyQueues
        }
    }

    /// Gate on `SupportedPlayer.isRunning` before calling; it is checked again
    /// when the read gets its turn.
    func readState(of player: SupportedPlayer) async -> StateRead {
        await run(on: queues(for: player).state) {
            guard player.isRunning else { return .snapshot(nil) }
            do throws(EventError) {
                return .snapshot(try Self.readSnapshot(of: player))
            } catch {
                return Self.stateRead(forError: error.code)
            }
        }
    }

    /// The image bytes of Music's current track, with that track's persistent ID
    /// so a reply that arrives after a track change can be told apart. `nil` when
    /// it has no artwork or the read failed. Gate on `isRunning` before calling.
    func readMusicArtwork() async -> (trackID: String, data: Data)? {
        await run(on: musicQueues.artwork) {
            let player = SupportedPlayer.music
            guard player.isRunning else { return nil }
            let codes = player.codes
            guard let artworkClass = codes.artworkClass, let artworkData = codes.artworkData else { return nil }
            let track = Self.property(fourCharCode("pTrk"), of: .null())
            let artwork = Self.element(artworkClass, index: 1, of: track)
            guard
                let trackID = try? Self.get(Self.property(codes.trackID, of: track), from: player, timeout: Self.artworkTimeout)
                    .flatMap(Self.text), !trackID.isEmpty,
                let data = try? Self.get(Self.property(artworkData, of: artwork), from: player, timeout: Self.artworkTimeout)?
                    .data, !data.isEmpty
            else { return nil }
            return (trackID, data)
        }
    }

    /// Plays or pauses, skips, or seeks. The command is queued before this returns,
    /// behind the player's reads already waiting and ahead of every later one, so a
    /// read started afterwards sees its effect. A refusal or timeout does nothing;
    /// the next read shows the real state. `completion` runs on the queue once the
    /// command has been answered or given up. Gate on `isRunning` before calling;
    /// it is checked again when the command gets its turn.
    func perform(_ command: PlaybackCommand, on player: SupportedPlayer, completion: @escaping @Sendable () -> Void) {
        queues(for: player).state.async {
            if player.isRunning {
                _ = try? Self.send(Self.event(for: command, to: player), timeout: Self.stateTimeout)
            }
            completion()
        }
    }

    /// The meaning of an Apple event error for a state read. None of these is
    /// worth logging: they are the normal states of a player and of the
    /// Automation permission, and a poll would repeat them every few seconds.
    static func stateRead(forError code: Int) -> StateRead {
        switch code {
        // No such object (no current track); application not running or quit
        // while the event was underway: nothing is playing.
        case -1728, -600, -609:
            .snapshot(nil)
        // Not authorized: the caller falls back to what the notifications said.
        case -1743:
            .notAuthorized
        // -1712 (timeout) and anything unexpected: skip this read.
        default:
            .unavailable
        }
    }

    private func run<Value: Sendable>(on queue: DispatchQueue, _ work: @escaping @Sendable () -> Value) async -> Value {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: work())
            }
        }
    }

    // MARK: Apple events (on the queue)

    /// An Apple event error, as the OSStatus it carries.
    private struct EventError: Error {
        var code: Int
    }

    /// Player state first; then the current track's fields, one event each. The
    /// title failing with -1728 means there is no current track (Music can report
    /// paused with none); any other field missing just stays empty. The position
    /// and length come last and never fail the read: a track is worth showing
    /// without a progress bar.
    private static func readSnapshot(of player: SupportedPlayer) throws(EventError) -> PlaybackSnapshot? {
        let codes = player.codes
        let stateReply = try get(property(fourCharCode("pPlS"), of: .null()), from: player, timeout: stateTimeout)
        let state = stateReply.map { PlayerState(enumCode: $0.enumCodeValue) } ?? .none
        guard state != .none else { return nil }

        let track = property(fourCharCode("pTrk"), of: .null())
        /// The field's text; `nil` when the track does not have it (-1728).
        func field(_ code: FourCharCode) throws(EventError) -> String? {
            do throws(EventError) {
                return try get(property(code, of: track), from: player, timeout: stateTimeout).flatMap(text)
            } catch {
                guard error.code == -1728 else { throw error }
                return nil
            }
        }
        let title: String
        do throws(EventError) {
            title = try get(property(fourCharCode("pnam"), of: track), from: player, timeout: stateTimeout)
                .flatMap(text) ?? ""
        } catch {
            guard error.code == -1728 else { throw error }
            return nil
        }
        let artist = try field(fourCharCode("pArt"))
        let album = try field(fourCharCode("pAlb"))
        let trackID = try field(codes.trackID)
        var artworkURL: String?
        if let code = codes.artworkURL {
            artworkURL = try field(code)
        }
        /// A timing value; `nil` when the player cannot give it, so the track still
        /// shows, without a progress bar. Only a timeout fails the read, which then
        /// keeps what is shown rather than dropping the bar until the next poll.
        func timing(_ specifier: NSAppleEventDescriptor) throws(EventError) -> Double? {
            do throws(EventError) {
                return try get(specifier, from: player, timeout: stateTimeout).flatMap(number)
            } catch {
                guard error.code != -1712 else { throw error }
                return nil
            }
        }
        let duration = try timing(property(fourCharCode("pDur"), of: track))
            .map(player.durationSeconds(fromReported:))
        // `player position` belongs to the application, not the track. Its moment
        // is when the answer arrived; the event's own travel time is far below what
        // the progress bar shows.
        let position = try timing(property(fourCharCode("pPos"), of: .null()))
            .map { PlaybackPosition(elapsed: $0, date: Date()) }
        return PlaybackSnapshot(
            player: player,
            isPlaying: state == .playing,
            title: title,
            artist: artist,
            album: album,
            trackID: trackID,
            artworkURL: artworkURL,
            duration: duration,
            position: position
        )
    }

    /// The event that carries `command` to `player`. Seeking sets the
    /// application's `player position` (`core/setd` with the new value as `data`).
    private static func event(for command: PlaybackCommand, to player: SupportedPlayer) -> NSAppleEventDescriptor {
        let codes = player.codes
        let code: (eventClass: FourCharCode, eventID: FourCharCode)
        switch command {
        case .playPause:
            code = codes.playPause
        case .next:
            code = codes.nextTrack
        case .previous:
            code = codes.previousTrack
        case .seek(let seconds):
            let set = event(fourCharCode("core"), fourCharCode("setd"), to: player)
            set.setParam(property(fourCharCode("pPos"), of: .null()), forKeyword: fourCharCode("----"))
            set.setParam(NSAppleEventDescriptor(double: seconds), forKeyword: fourCharCode("data"))
            return set
        }
        return event(code.eventClass, code.eventID, to: player)
    }

    /// Text of a reply value; `nil` for `missing value` or anything not text.
    private static func text(_ descriptor: NSAppleEventDescriptor) -> String? {
        guard descriptor.descriptorType != fourCharCode("msng") else { return nil }
        return descriptor.stringValue
    }

    /// A reply value as a number; `nil` for `missing value` or anything that is
    /// not one. Coerced first: `doubleValue` alone reads 0 for what it cannot convert.
    private static func number(_ descriptor: NSAppleEventDescriptor) -> Double? {
        guard descriptor.descriptorType != fourCharCode("msng") else { return nil }
        return descriptor.coerce(toDescriptorType: fourCharCode("doub"))?.doubleValue
    }

    /// Sends `core/getd` for `specifier`; the reply's direct object, if any.
    private static func get(
        _ specifier: NSAppleEventDescriptor,
        from player: SupportedPlayer,
        timeout: TimeInterval
    ) throws(EventError) -> NSAppleEventDescriptor? {
        let event = event(fourCharCode("core"), fourCharCode("getd"), to: player)
        event.setParam(specifier, forKeyword: fourCharCode("----"))
        let reply = try send(event, timeout: timeout)
        return reply.paramDescriptor(forKeyword: fourCharCode("----"))
    }

    private static func event(
        _ eventClass: FourCharCode,
        _ eventID: FourCharCode,
        to player: SupportedPlayer
    ) -> NSAppleEventDescriptor {
        NSAppleEventDescriptor.appleEvent(
            withEventClass: eventClass,
            eventID: eventID,
            targetDescriptor: NSAppleEventDescriptor(bundleIdentifier: player.bundleIdentifier),
            // kAutoGenerateReturnID, kAnyTransactionID.
            returnID: -1,
            transactionID: 0
        )
    }

    private static func send(_ event: NSAppleEventDescriptor, timeout: TimeInterval) throws(EventError) -> NSAppleEventDescriptor {
        let reply: NSAppleEventDescriptor
        do {
            reply = try event.sendEvent(options: [.waitForReply], timeout: timeout)
        } catch {
            throw EventError(code: (error as NSError).code)
        }
        // The application's own error, when it reports one in the reply rather than the send.
        if let status = reply.paramDescriptor(forKeyword: fourCharCode("errn"))?.int32Value, status != 0 {
            throw EventError(code: Int(status))
        }
        return reply
    }

    /// `<property code> of <container>`.
    private static func property(_ code: FourCharCode, of container: NSAppleEventDescriptor) -> NSAppleEventDescriptor {
        specifier(
            want: fourCharCode("prop"),
            form: fourCharCode("prop"),
            selector: NSAppleEventDescriptor(typeCode: code),
            container: container
        )
    }

    /// `<class> <index> of <container>` (1-based).
    private static func element(_ elementClass: FourCharCode, index: Int32, of container: NSAppleEventDescriptor) -> NSAppleEventDescriptor {
        specifier(
            want: elementClass,
            form: fourCharCode("indx"),
            selector: NSAppleEventDescriptor(int32: index),
            container: container
        )
    }

    /// An object specifier: a record of want/form/seld/from coerced to 'obj '.
    /// The application itself is the null container.
    private static func specifier(
        want: FourCharCode,
        form: FourCharCode,
        selector: NSAppleEventDescriptor,
        container: NSAppleEventDescriptor
    ) -> NSAppleEventDescriptor {
        let record = NSAppleEventDescriptor.record()
        record.setDescriptor(NSAppleEventDescriptor(typeCode: want), forKeyword: fourCharCode("want"))
        record.setDescriptor(NSAppleEventDescriptor(enumCode: form), forKeyword: fourCharCode("form"))
        record.setDescriptor(selector, forKeyword: fourCharCode("seld"))
        record.setDescriptor(container, forKeyword: fourCharCode("from"))
        return record.coerce(toDescriptorType: fourCharCode("obj ")) ?? record
    }
}

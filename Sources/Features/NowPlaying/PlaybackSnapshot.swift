import Foundation

/// What the user asks the playing app to do.
enum PlaybackCommand: Sendable, Equatable {
    case playPause
    case next
    /// The player's own previous command (for Music its back button, which
    /// restarts the track unless it is near its start).
    case previous
    /// To this many seconds into the track.
    case seek(TimeInterval)
}

/// Where playback stood at a known moment; the position now is worked out from
/// it (`PlaybackSnapshot.elapsed(at:)`) rather than read again and again.
struct PlaybackPosition: Sendable, Equatable {
    /// Seconds into the track at `date`.
    var elapsed: TimeInterval
    var date: Date
    /// Seconds of track per second of time while playing.
    var rate: Double = 1
}

/// What one player is playing, as last read. A player with nothing to show (stopped,
/// no current track, no title) has no snapshot at all.
struct PlaybackSnapshot: Sendable, Equatable {
    /// The app playing: a scripted player, or whatever app the system reports.
    var bundleIdentifier: String
    /// Set when the snapshot was read through that player's AppleScript dictionary;
    /// `nil` when the system's now-playing information named the app.
    var player: SupportedPlayer?
    var isPlaying: Bool
    var title: String
    var artist: String?
    var album: String?
    /// The player's own id for the track, when it gave one.
    var trackID: String?
    /// Spotify's cover image address; Music hands out the image itself instead.
    var artworkURL: String?
    /// The cover's image bytes, when the system's now-playing information carried them.
    var artworkData: Data?
    /// Stable identity of the track across reads, see `trackKey(player:id:title:artist:album:)`.
    var trackKey: String
    /// Length of the track in seconds; `nil` when unknown or not positive (a live stream).
    var duration: TimeInterval?
    /// The position as last read; `nil` when the player did not say.
    var position: PlaybackPosition?

    /// `nil` when `title` is empty: a track without a name is nothing worth showing.
    init?(
        player: SupportedPlayer,
        isPlaying: Bool,
        title: String,
        artist: String? = nil,
        album: String? = nil,
        trackID: String? = nil,
        artworkURL: String? = nil,
        duration: TimeInterval? = nil,
        position: PlaybackPosition? = nil
    ) {
        self.init(
            bundleIdentifier: player.bundleIdentifier,
            player: player,
            isPlaying: isPlaying,
            title: title,
            artist: artist,
            album: album,
            trackID: trackID,
            artworkURL: artworkURL,
            artworkData: nil,
            duration: duration,
            position: position
        )
    }

    /// What the system's now-playing information says `bundleIdentifier` plays.
    init?(
        bundleIdentifier: String,
        isPlaying: Bool,
        title: String,
        artist: String? = nil,
        album: String? = nil,
        artworkData: Data? = nil,
        duration: TimeInterval? = nil,
        position: PlaybackPosition? = nil
    ) {
        self.init(
            bundleIdentifier: bundleIdentifier,
            player: nil,
            isPlaying: isPlaying,
            title: title,
            artist: artist,
            album: album,
            trackID: nil,
            artworkURL: nil,
            artworkData: artworkData,
            duration: duration,
            position: position
        )
    }

    private init?(
        bundleIdentifier: String,
        player: SupportedPlayer?,
        isPlaying: Bool,
        title: String,
        artist: String?,
        album: String?,
        trackID: String?,
        artworkURL: String?,
        artworkData: Data?,
        duration: TimeInterval?,
        position: PlaybackPosition?
    ) {
        guard !title.isEmpty else { return nil }
        self.bundleIdentifier = bundleIdentifier
        self.player = player
        self.isPlaying = isPlaying
        self.title = title
        self.artist = artist.flatMap { $0.isEmpty ? nil : $0 }
        self.album = album.flatMap { $0.isEmpty ? nil : $0 }
        self.trackID = trackID.flatMap { $0.isEmpty ? nil : $0 }
        self.artworkURL = artworkURL.flatMap { $0.isEmpty ? nil : $0 }
        self.artworkData = artworkData.flatMap { $0.isEmpty ? nil : $0 }
        self.duration = duration.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        self.position = position.flatMap { $0.elapsed.isFinite && $0.rate.isFinite ? $0 : nil }
        trackKey = Self.trackKey(
            bundleIdentifier: bundleIdentifier,
            id: self.trackID,
            title: title,
            artist: self.artist,
            album: self.album
        )
    }

    /// Reads the text the player broadcasts with its distributed notification
    /// ("Player State", "Name", "Artist", "Album"). Only a fallback for when Apple
    /// events are not allowed, so it leaves out the id: the notifications spell it
    /// differently from the Apple event reads, and the key would change between the two.
    init?(player: SupportedPlayer, notificationInfo info: [String: String]) {
        let state = info["Player State"]?.lowercased()
        guard state == "playing" || state == "paused" else { return nil }
        self.init(
            player: player,
            isPlaying: state == "playing",
            title: info["Name"] ?? "",
            artist: info["Artist"],
            album: info["Album"]
        )
    }

    /// "<bundle>|<id>", or "<bundle>|<title>|<artist>|<album>" without an id.
    static func trackKey(bundleIdentifier: String, id: String?, title: String, artist: String?, album: String?) -> String {
        if let id, !id.isEmpty {
            return "\(bundleIdentifier)|\(id)"
        }
        return "\(bundleIdentifier)|\(title)|\(artist ?? "")|\(album ?? "")"
    }

    /// 64-bit FNV-1a of the UTF-8 bytes. Unlike `hashValue`, which Swift seeds
    /// anew on every launch, it stays the same, so a song keeps its rhythm.
    static func stableHash(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash
    }

    /// How far into the track playback is at `now`: the anchor's position, moved on
    /// by the time since while playing, frozen while paused, and kept within the
    /// track. `nil` without an anchor.
    func elapsed(at now: Date) -> TimeInterval? {
        guard let position else { return nil }
        var elapsed = position.elapsed
        if isPlaying {
            elapsed += now.timeIntervalSince(position.date) * position.rate
        }
        return min(max(elapsed, 0), duration ?? .infinity)
    }

    /// Plays or pauses, with the anchor moved to `now` at the position reached, so
    /// the position neither jumps nor keeps running while paused.
    mutating func setPlaying(_ playing: Bool, at now: Date) {
        if let elapsed = elapsed(at: now), let position {
            self.position = PlaybackPosition(elapsed: elapsed, date: now, rate: position.rate)
        }
        isPlaying = playing
    }

    /// What `command` is expected to do, shown before the player confirms it.
    /// Skipping changes nothing here: the next reading brings the new track.
    mutating func apply(_ command: PlaybackCommand, at now: Date) {
        switch command {
        case .playPause:
            setPlaying(!isPlaying, at: now)
        case .seek(let seconds):
            position = PlaybackPosition(
                elapsed: min(max(seconds, 0), duration ?? .infinity),
                date: now,
                rate: position?.rate ?? 1
            )
        case .next, .previous:
            break
        }
    }

    /// Readings closer than this to where the shown anchor puts playback keep that
    /// anchor: the time an Apple event takes moves every poll's anchor a little,
    /// and each would otherwise nudge the progress bar back and forth.
    static let positionTolerance: TimeInterval = 1

    /// `self`, with `previous`'s position anchor when that one already says where
    /// playback is (same track, play state, length, and rate, within
    /// `positionTolerance`), so a poll that only re-reads the position compares
    /// equal and changes nothing on screen.
    func steadied(against previous: PlaybackSnapshot?) -> PlaybackSnapshot {
        guard
            let previous,
            previous.trackKey == trackKey,
            previous.isPlaying == isPlaying,
            previous.duration == duration,
            let anchor = previous.position,
            let position,
            anchor.rate == position.rate,
            // At the later of the two anchors: at the earlier one, the shown
            // prediction can clamp to 0 and seem to agree with a reading that
            // is really far behind (a seek the app ignored).
            let expected = previous.elapsed(at: max(anchor.date, position.date)),
            let read = elapsed(at: max(anchor.date, position.date)),
            abs(expected - read) < Self.positionTolerance
        else { return self }
        var steadied = self
        steadied.position = anchor
        return steadied
    }

    /// The snapshot to show out of every player's: `preferred` (the one shown now)
    /// while it plays, else any playing one, else `preferred` paused, else any.
    /// A paused one is left to `PresenceTracker` to show or hide.
    static func current(
        from snapshots: [SupportedPlayer: PlaybackSnapshot],
        preferring preferred: SupportedPlayer?
    ) -> PlaybackSnapshot? {
        if let preferred, let snapshot = snapshots[preferred], snapshot.isPlaying { return snapshot }
        if let playing = SupportedPlayer.allCases.lazy.compactMap({ snapshots[$0] }).first(where: \.isPlaying) {
            return playing
        }
        if let preferred, let snapshot = snapshots[preferred] { return snapshot }
        return SupportedPlayer.allCases.lazy.compactMap { snapshots[$0] }.first
    }
}

/// Decides whether the track shows beside the notch: while it plays, and for
/// `pausedLinger` after it was paused, so a quick pause does not make it vanish.
/// A track that was already paused when first seen (never seen playing) stays hidden.
struct PresenceTracker: Sendable, Equatable {
    static let pausedLinger: TimeInterval = 3

    private(set) var snapshot: PlaybackSnapshot?
    /// When the shown player went from playing to paused.
    private(set) var pausedSince: Date?

    mutating func update(_ new: PlaybackSnapshot?, now: Date) {
        defer { snapshot = new }
        guard let new, !new.isPlaying else {
            pausedSince = nil
            return
        }
        guard let old = snapshot, old.bundleIdentifier == new.bundleIdentifier else {
            pausedSince = nil
            return
        }
        if old.isPlaying {
            pausedSince = now
        }
        // Paused before as well: the linger keeps counting from the first pause,
        // also across a track skipped while paused.
    }

    func isVisible(at now: Date) -> Bool {
        guard let snapshot, !snapshot.title.isEmpty else { return false }
        if snapshot.isPlaying { return true }
        guard let pausedSince else { return false }
        return now.timeIntervalSince(pausedSince) < Self.pausedLinger
    }

    /// When a paused track's linger runs out; `nil` while playing or hidden.
    var hideDate: Date? {
        guard snapshot?.isPlaying == false, let pausedSince else { return nil }
        return pausedSince.addingTimeInterval(Self.pausedLinger)
    }
}

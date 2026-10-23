import Foundation

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

    /// `nil` when `title` is empty: a track without a name is nothing worth showing.
    init?(
        player: SupportedPlayer,
        isPlaying: Bool,
        title: String,
        artist: String? = nil,
        album: String? = nil,
        trackID: String? = nil,
        artworkURL: String? = nil
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
            artworkData: nil
        )
    }

    /// What the system's now-playing information says `bundleIdentifier` plays.
    init?(
        bundleIdentifier: String,
        isPlaying: Bool,
        title: String,
        artist: String? = nil,
        album: String? = nil,
        artworkData: Data? = nil
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
            artworkData: artworkData
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
        artworkData: Data?
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
    static let pausedLinger: TimeInterval = 30

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

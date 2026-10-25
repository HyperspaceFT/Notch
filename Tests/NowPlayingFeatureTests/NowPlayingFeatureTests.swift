import Foundation
import Testing
@testable import NowPlayingFeature

struct PlaybackSnapshotTests {
    @Test func emptyTitleMeansNothingPlaying() {
        #expect(PlaybackSnapshot(player: .music, isPlaying: true, title: "") == nil)
        #expect(PlaybackSnapshot(player: .music, isPlaying: true, title: "", artist: "Artist", trackID: "ID") == nil)
    }

    @Test func playerStateEnumeratorsMapToPlayingPausedOrNone() {
        // Enumerators from Music's and Spotify's .sdef: kPSP playing, kPSp paused, kPSS stopped.
        #expect(PlayerState(enumCode: fourCharCode("kPSP")) == .playing)
        #expect(PlayerState(enumCode: fourCharCode("kPSp")) == .paused)
        #expect(PlayerState(enumCode: fourCharCode("kPSS")) == .none)
        #expect(PlayerState(enumCode: 0) == .none)
    }

    @Test func fourCharCodePacksASCIIBigEndian() {
        #expect(fourCharCode("core") == 0x636f_7265)
        #expect(fourCharCode("ID  ") == 0x4944_2020)
    }

    @Test func emptyOptionalFieldsAreDropped() throws {
        let snapshot = try #require(PlaybackSnapshot(
            player: .music,
            isPlaying: false,
            title: "Song",
            artist: "Artist",
            album: "",
            trackID: "ABC123",
            artworkURL: ""
        ))
        #expect(!snapshot.isPlaying)
        #expect(snapshot.title == "Song")
        #expect(snapshot.artist == "Artist")
        #expect(snapshot.album == nil)
        #expect(snapshot.trackKey == "com.apple.Music|ABC123")
        #expect(snapshot.artworkURL == nil)
    }

    @Test func keepsSpotifyArtworkAddress() throws {
        let snapshot = try #require(PlaybackSnapshot(
            player: .spotify,
            isPlaying: true,
            title: "Song",
            artist: "Artist",
            album: "Album",
            trackID: "spotify:track:1",
            artworkURL: "https://i.scdn.co/image/x"
        ))
        #expect(snapshot.isPlaying)
        #expect(snapshot.trackKey == "com.spotify.client|spotify:track:1")
        #expect(snapshot.artworkURL == "https://i.scdn.co/image/x")
    }

    @Test func keyFallsBackToTitleArtistAlbumWithoutAnID() throws {
        let snapshot = try #require(PlaybackSnapshot(player: .music, isPlaying: true, title: "Song", artist: "Artist", trackID: ""))
        #expect(snapshot.trackKey == "com.apple.Music|Song|Artist|")
    }

    @Test func notificationTextIsAFallbackSnapshot() throws {
        let snapshot = try #require(PlaybackSnapshot(
            player: .spotify,
            notificationInfo: ["Player State": "Playing", "Name": "Song", "Artist": "Artist", "Album": "Album"]
        ))
        #expect(snapshot.isPlaying)
        #expect(snapshot.title == "Song")
        #expect(PlaybackSnapshot(player: .music, notificationInfo: ["Player State": "Stopped", "Name": "Song"]) == nil)
    }

    @Test func stableHashIsFNV1a() {
        // Published FNV-1a 64-bit test vectors.
        #expect(PlaybackSnapshot.stableHash("") == 0xcbf2_9ce4_8422_2325)
        #expect(PlaybackSnapshot.stableHash("a") == 0xaf63_dc4c_8601_ec8c)
        #expect(PlaybackSnapshot.stableHash("foobar") == 0x8594_4171_f739_67e8)
    }

    @Test func prefersTheShownPlayerWhilePlayingElseAnyPlayingOne() throws {
        let music = try #require(PlaybackSnapshot(player: .music, isPlaying: false, title: "A"))
        let spotify = try #require(PlaybackSnapshot(player: .spotify, isPlaying: true, title: "B"))
        #expect(PlaybackSnapshot.current(from: [.music: music, .spotify: spotify], preferring: .music) == spotify)
        #expect(PlaybackSnapshot.current(from: [.music: music], preferring: .music) == music)
        #expect(PlaybackSnapshot.current(from: [:], preferring: .music) == nil)
    }

    @Test func eventErrorsMapToStates() {
        #expect(PlayerScripting.stateRead(forError: -1728) == .snapshot(nil))
        #expect(PlayerScripting.stateRead(forError: -600) == .snapshot(nil))
        #expect(PlayerScripting.stateRead(forError: -609) == .snapshot(nil))
        #expect(PlayerScripting.stateRead(forError: -1743) == .notAuthorized)
        #expect(PlayerScripting.stateRead(forError: -1712) == .unavailable)
    }
}

struct PresenceTrackerTests {
    let start = Date(timeIntervalSinceReferenceDate: 1_000)

    func snapshot(playing: Bool, title: String = "Song") -> PlaybackSnapshot? {
        PlaybackSnapshot(player: .music, isPlaying: playing, title: title, trackID: "1")
    }

    @Test func playingTrackIsVisible() {
        var tracker = PresenceTracker()
        tracker.update(snapshot(playing: true), now: start)
        #expect(tracker.isVisible(at: start))
        #expect(tracker.hideDate == nil)
    }

    @Test func pausedTrackLingersThreeSecondsThenHides() {
        var tracker = PresenceTracker()
        tracker.update(snapshot(playing: true), now: start)
        tracker.update(snapshot(playing: false), now: start + 5)
        #expect(tracker.isVisible(at: start + 5))
        #expect(tracker.isVisible(at: start + 7.9))
        #expect(!tracker.isVisible(at: start + 8))
        #expect(tracker.hideDate == start + 8)
    }

    @Test func laterPausedReadingsDoNotRestartTheLinger() {
        var tracker = PresenceTracker()
        tracker.update(snapshot(playing: true), now: start)
        tracker.update(snapshot(playing: false), now: start)
        tracker.update(snapshot(playing: false), now: start + 2)
        #expect(!tracker.isVisible(at: start + 4))
    }

    @Test func resumingWithinTheLingerStaysVisible() {
        var tracker = PresenceTracker()
        tracker.update(snapshot(playing: true), now: start)
        tracker.update(snapshot(playing: false), now: start + 1)
        tracker.update(snapshot(playing: true), now: start + 2)
        #expect(tracker.isVisible(at: start + 100))
        #expect(tracker.hideDate == nil)
    }

    @Test func nothingPlayingHidesImmediately() {
        var tracker = PresenceTracker()
        tracker.update(snapshot(playing: true), now: start)
        tracker.update(nil, now: start + 1)
        #expect(!tracker.isVisible(at: start + 1))
    }

    @Test func untitledTrackIsHidden() {
        var tracker = PresenceTracker()
        tracker.update(snapshot(playing: true, title: ""), now: start)
        #expect(!tracker.isVisible(at: start))
    }
}

struct PulseRhythmTests {
    @Test func sameSeedAndTimeGiveTheSameLevels() {
        let a = PulseRhythm(seed: 42)
        let b = PulseRhythm(seed: 42)
        for time in stride(from: 0.0, through: 5, by: 0.37) {
            #expect(a.levels(at: time, count: 5) == b.levels(at: time, count: 5))
        }
    }

    @Test func differentSeedsDiffer() {
        let a = PulseRhythm(seed: 1)
        let b = PulseRhythm(seed: 2)
        let times = stride(from: 0.0, through: 5, by: 0.25)
        #expect(times.contains { a.levels(at: $0, count: 5) != b.levels(at: $0, count: 5) })
    }

    @Test func levelsStayWithinZeroAndOne() {
        for seed: UInt64 in [0, 1, 7, 0xdead_beef, .max] {
            let rhythm = PulseRhythm(seed: seed)
            for time in stride(from: 0.0, through: 30, by: 0.013) {
                let levels = rhythm.levels(at: time, count: 5)
                #expect(levels.count == 5)
                #expect(levels.allSatisfy { (0...1).contains($0) })
            }
        }
    }

    @Test func tempoIsBetween93And129BPM() {
        for seed in UInt64(0)..<200 {
            let tempo = PulseRhythm(seed: seed &* 0x9e37_79b9).tempo
            #expect(tempo >= 93 && tempo <= 129)
        }
    }
}

struct ArtworkPaletteTests {
    func pixels(_ colors: [(r: UInt8, g: UInt8, b: UInt8, count: Int)]) -> [UInt8] {
        colors.flatMap { color in
            Array(repeating: [color.r, color.g, color.b, 255], count: color.count).flatMap { $0 }
        }
    }

    /// Distance on the hue circle, 0…0.5.
    func hueDistance(_ a: Double, _ b: Double) -> Double {
        let distance = abs(a - b).truncatingRemainder(dividingBy: 1)
        return min(distance, 1 - distance)
    }

    @Test func grayCoverGivesLightGrays() {
        let bytes = pixels([(128, 128, 128, 400)])
        let palette = ArtworkPalette.extract(fromRGBA: bytes, width: 20, height: 20)
        #expect(palette.primary.saturation < 0.1)
        #expect(palette.secondary.saturation < 0.1)
        #expect(palette.primary.brightness >= 0.8)
        #expect(palette.secondary.brightness >= 0.8)
    }

    @Test func mostlyRedWithSomeBlue() {
        let bytes = pixels([(230, 30, 30, 300), (30, 60, 230, 100)])
        let palette = ArtworkPalette.extract(fromRGBA: bytes, width: 20, height: 20)
        #expect(hueDistance(palette.primary.hue, 0) < 0.04)
        // Pure blue is at 240°.
        #expect(hueDistance(palette.secondary.hue, 240.0 / 360) < 0.06)
    }

    @Test func darkSaturatedCoverIsBrightenedForTheBlackIsland() {
        let bytes = pixels([(100, 10, 10, 400)])
        let palette = ArtworkPalette.extract(fromRGBA: bytes, width: 20, height: 20)
        #expect(palette.primary.brightness >= 0.8)
        #expect(palette.secondary.brightness >= 0.8)
        #expect(palette.primary.saturation <= 0.85)
    }

    @Test func singleHueGetsANeighbouringSecondColor() {
        let bytes = pixels([(30, 200, 60, 400)])
        let palette = ArtworkPalette.extract(fromRGBA: bytes, width: 20, height: 20)
        let shift = hueDistance(palette.primary.hue, palette.secondary.hue)
        #expect(abs(shift - 25.0 / 360) < 0.01)
    }
}

@MainActor
struct NowPlayingSettingsTests {
    private func freshDefaults() -> UserDefaults {
        let suite = "NowPlayingSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func mediaRemoteIsOffUntilTurnedOn() {
        #expect(!NowPlayingSettings(defaults: freshDefaults()).usesMediaRemote)
    }

    @Test func switchIsRemembered() {
        let defaults = freshDefaults()
        NowPlayingSettings(defaults: defaults).usesMediaRemote = true
        #expect(NowPlayingSettings(defaults: defaults).usesMediaRemote)
    }
}

struct PlaybackPositionTests {
    let start = Date(timeIntervalSinceReferenceDate: 1_000)

    func snapshot(playing: Bool, elapsed: TimeInterval? = 30, duration: TimeInterval? = 200, rate: Double = 1) -> PlaybackSnapshot? {
        PlaybackSnapshot(
            player: .music,
            isPlaying: playing,
            title: "Song",
            trackID: "1",
            duration: duration,
            position: elapsed.map { PlaybackPosition(elapsed: $0, date: start, rate: rate) }
        )
    }

    @Test func advancesWhilePlaying() throws {
        let playing = try #require(snapshot(playing: true))
        #expect(playing.elapsed(at: start) == 30)
        #expect(playing.elapsed(at: start + 12.5) == 42.5)
        let double = try #require(snapshot(playing: true, rate: 2))
        #expect(double.elapsed(at: start + 10) == 50)
    }

    @Test func frozenWhilePaused() throws {
        let paused = try #require(snapshot(playing: false))
        #expect(paused.elapsed(at: start + 100) == 30)
    }

    @Test func clampedToTheTrack() throws {
        let playing = try #require(snapshot(playing: true))
        #expect(playing.elapsed(at: start + 500) == 200)
        // A clock that reads earlier than the anchor's.
        #expect(playing.elapsed(at: start - 60) == 0)
        // Without a length only the start bounds it.
        let live = try #require(snapshot(playing: true, duration: nil))
        #expect(live.elapsed(at: start + 500) == 530)
    }

    @Test func nothingWithoutAnAnchor() throws {
        let unknown = try #require(snapshot(playing: true, elapsed: nil))
        #expect(unknown.elapsed(at: start) == nil)
    }

    @Test func zeroOrMissingLengthIsUnknown() throws {
        #expect(try #require(snapshot(playing: true, duration: 0)).duration == nil)
        #expect(try #require(snapshot(playing: true, duration: -1)).duration == nil)
        #expect(try #require(snapshot(playing: true, duration: .infinity)).duration == nil)
    }

    @Test func pausingFreezesWherePlaybackGotTo() throws {
        var snapshot = try #require(snapshot(playing: true))
        snapshot.setPlaying(false, at: start + 10)
        #expect(!snapshot.isPlaying)
        #expect(snapshot.elapsed(at: start + 60) == 40)
        snapshot.setPlaying(true, at: start + 60)
        #expect(snapshot.elapsed(at: start + 65) == 45)
    }

    @Test func seekReanchorsWithinTheTrack() throws {
        var snapshot = try #require(snapshot(playing: true))
        snapshot.apply(.seek(120), at: start + 5)
        #expect(snapshot.elapsed(at: start + 5) == 120)
        #expect(snapshot.elapsed(at: start + 7) == 122)
        snapshot.apply(.seek(999), at: start + 5)
        #expect(snapshot.elapsed(at: start + 5) == 200)
        snapshot.apply(.seek(-3), at: start + 5)
        #expect(snapshot.elapsed(at: start + 5) == 0)
    }

    @Test func skippingLeavesTheSnapshotAlone() throws {
        let original = try #require(snapshot(playing: true))
        var snapshot = original
        snapshot.apply(.next, at: start + 5)
        snapshot.apply(.previous, at: start + 5)
        #expect(snapshot == original)
    }

    @Test func spotifyReportsItsLengthInMilliseconds() {
        #expect(SupportedPlayer.spotify.durationSeconds(fromReported: 215_000) == 215)
        #expect(SupportedPlayer.spotify.durationSeconds(fromReported: 1_500) == 1.5)
        #expect(SupportedPlayer.music.durationSeconds(fromReported: 215.4) == 215.4)
    }
}

struct SteadyPositionTests {
    let start = Date(timeIntervalSinceReferenceDate: 1_000)

    func snapshot(playing: Bool = true, trackID: String = "1", elapsed: TimeInterval, at date: Date) -> PlaybackSnapshot? {
        PlaybackSnapshot(
            player: .spotify,
            isPlaying: playing,
            title: "Song",
            trackID: trackID,
            duration: 200,
            position: PlaybackPosition(elapsed: elapsed, date: date)
        )
    }

    @Test func positionWhereTheAnchorPutsItKeepsTheAnchor() throws {
        let shown = try #require(snapshot(elapsed: 10, at: start))
        let read = try #require(snapshot(elapsed: 13.3, at: start + 3))
        // Equal, so the model writes nothing and nothing redraws.
        #expect(read.steadied(against: shown) == shown)
    }

    @Test func pausedRereadKeepsTheAnchor() throws {
        let shown = try #require(snapshot(playing: false, elapsed: 10, at: start))
        let read = try #require(snapshot(playing: false, elapsed: 10, at: start + 30))
        #expect(read.steadied(against: shown) == shown)
    }

    @Test func anOlderReadingFarBehindIsTaken() throws {
        // The user seeked to 30 s; the app ignored it and still reports its own
        // anchor from two minutes earlier. Compared at that old moment, the shown
        // anchor clamps to 0 and would seem to agree.
        let shown = try #require(snapshot(elapsed: 30, at: start + 120))
        let read = try #require(snapshot(elapsed: 0, at: start))
        #expect(read.steadied(against: shown) == read)
    }

    @Test func aJumpIsTaken() throws {
        let shown = try #require(snapshot(elapsed: 10, at: start))
        let read = try #require(snapshot(elapsed: 60, at: start + 3))
        #expect(read.steadied(against: shown) == read)
    }

    @Test func aNewPlayStateOrTrackIsTaken() throws {
        let shown = try #require(snapshot(elapsed: 10, at: start))
        let paused = try #require(snapshot(playing: false, elapsed: 13, at: start + 3))
        #expect(paused.steadied(against: shown) == paused)
        let other = try #require(snapshot(trackID: "2", elapsed: 13, at: start + 3))
        #expect(other.steadied(against: shown) == other)
        #expect(other.steadied(against: nil) == other)
    }

    @Test func positionDoesNotChangeTheTrackKey() throws {
        let a = try #require(snapshot(elapsed: 10, at: start))
        let b = try #require(snapshot(elapsed: 90, at: start + 50))
        #expect(a.trackKey == b.trackKey)
    }
}

struct PlaybackTimeTests {
    @Test func formatsMinutesAndHours() {
        #expect(PlaybackTime.format(0) == "0:00")
        #expect(PlaybackTime.format(59) == "0:59")
        #expect(PlaybackTime.format(61) == "1:01")
        #expect(PlaybackTime.format(3599) == "59:59")
        #expect(PlaybackTime.format(3600) == "1:00:00")
        #expect(PlaybackTime.format(3661) == "1:01:01")
        #expect(PlaybackTime.format(-5) == "0:00")
    }

    @Test func remainingCarriesAMinusSign() {
        let labels = PlaybackTime.labels(elapsed: 42, duration: 215)
        #expect(labels.elapsed == "0:42")
        #expect(labels.remaining == "-2:53")
        let long = PlaybackTime.labels(elapsed: 5, duration: 4000)
        #expect(long.remaining == "-1:06:35")
        let end = PlaybackTime.labels(elapsed: 300, duration: 215)
        #expect(end.elapsed == "3:35")
        #expect(end.remaining == "-0:00")
    }

    /// Seconds back from "m:ss", "h:mm:ss", or either with a leading minus.
    func seconds(_ label: String) -> Int {
        label.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
            .split(separator: ":")
            .reduce(0) { $0 * 60 + Int($1)! }
    }

    @Test func elapsedAndRemainingAlwaysAddUpToTheLength() {
        for duration in [215.0, 215.4, 215.5, 215.6, 59.99, 3600.5] {
            let total = Int(duration.rounded())
            for step in 0...Int(duration * 20) {
                let elapsed = Double(step) / 20
                let labels = PlaybackTime.labels(elapsed: elapsed, duration: duration)
                #expect(seconds(labels.elapsed) + seconds(labels.remaining) == total, "at \(elapsed) of \(duration)")
            }
        }
    }

    @Test func wholeSecondsTurnOverTogether() {
        let before = PlaybackTime.labels(elapsed: 41.999, duration: 215)
        let at = PlaybackTime.labels(elapsed: 42, duration: 215)
        #expect(before.elapsed == "0:41")
        #expect(before.remaining == "-2:54")
        #expect(at.elapsed == "0:42")
        #expect(at.remaining == "-2:53")
    }

    @Test func nonFiniteTimesShowZero() {
        let labels = PlaybackTime.labels(elapsed: .nan, duration: 100)
        #expect(labels.elapsed == "0:00")
        #expect(labels.remaining == "-1:40")
    }
}

@MainActor
struct NowPlayingModelTests {
    @Test func openingTheDetailAsksTheFeature() {
        let model = NowPlayingModel(scripting: PlayerScripting())
        var requests = 0
        model.onOpenDetail = { requests += 1 }
        model.openDetail()
        #expect(requests == 1)

        // Without a feature listening, nothing happens.
        model.onOpenDetail = nil
        model.openDetail()
        #expect(requests == 1)
    }
}

import AppKit
import Foundation
import Testing
@testable import NowPlayingFeature

struct MediaRemoteUpdateTests {
    /// What `get` printed for a Bilibili video playing in a browser.
    static let getOutput = """
    {
      "playbackRate" : 1,
      "album" : "",
      "elapsedTime" : 0,
      "timestamp" : "2026-10-23T20:06:36Z",
      "bundleIdentifier" : "ai.perplexity.comet",
      "processIdentifier" : 673,
      "title" : "ZywOo：全是信息枪，信息怎么来的先别管",
      "artworkMimeType" : "image\\/jpeg",
      "duration" : 166,
      "artist" : "",
      "contentItemIdentifier" : "A7B885A3-B05B-480A-9AF5-683E2BF0AA53",
      "playing" : true
    }
    """

    func state(applying lines: String...) -> MediaRemoteState {
        var state = MediaRemoteState()
        for line in lines {
            if let update = MediaRemoteUpdate(streamLine: line) {
                state.apply(update)
            }
        }
        return state
    }

    @Test func getOutputOfABrowserTabBecomesASnapshot() throws {
        let update = try #require(MediaRemoteUpdate(getOutput: Data(Self.getOutput.utf8)))
        var state = MediaRemoteState()
        state.apply(update)
        let snapshot = try #require(state.snapshot)
        #expect(snapshot.bundleIdentifier == "ai.perplexity.comet")
        #expect(snapshot.player == nil)
        #expect(snapshot.title == "ZywOo：全是信息枪，信息怎么来的先别管")
        #expect(snapshot.isPlaying)
        // Empty strings are no artist and no album.
        #expect(snapshot.artist == nil)
        #expect(snapshot.album == nil)
        #expect(snapshot.artworkData == nil)
    }

    @Test func fullLineReplacesEverything() throws {
        let state = state(
            applying: #"{"type":"data","diff":false,"payload":{"bundleIdentifier":"a","title":"One","playing":true}}"#,
            #"{"type":"data","diff":false,"payload":{"bundleIdentifier":"b","title":"Two"}}"#
        )
        let snapshot = try #require(state.snapshot)
        #expect(snapshot.bundleIdentifier == "b")
        #expect(snapshot.title == "Two")
        // `playing` is gone with the old payload.
        #expect(!snapshot.isPlaying)
    }

    @Test func diffLineChangesOnlyTheKeysItNames() throws {
        let state = state(
            applying: #"{"type":"data","diff":false,"payload":{"bundleIdentifier":"a","title":"One","artist":"Me","playing":true}}"#,
            #"{"type":"data","diff":true,"payload":{"playing":false}}"#
        )
        let snapshot = try #require(state.snapshot)
        #expect(snapshot.title == "One")
        #expect(snapshot.artist == "Me")
        #expect(!snapshot.isPlaying)
    }

    @Test func nullInADiffRemovesTheKey() throws {
        let state = state(
            applying: #"{"type":"data","diff":false,"payload":{"bundleIdentifier":"a","title":"One","artist":"Me","playing":true}}"#,
            #"{"type":"data","diff":true,"payload":{"artist":null}}"#
        )
        let snapshot = try #require(state.snapshot)
        #expect(snapshot.title == "One")
        #expect(snapshot.artist == nil)
    }

    @Test func emptyPayloadMeansNothingPlaying() {
        let state = state(
            applying: #"{"type":"data","diff":false,"payload":{"bundleIdentifier":"a","title":"One","playing":true}}"#,
            #"{"type":"data","diff":false,"payload":{}}"#
        )
        #expect(state.snapshot == nil)
    }

    @Test func titleRemovedByADiffMeansNothingPlaying() {
        let state = state(
            applying: #"{"type":"data","diff":false,"payload":{"bundleIdentifier":"a","title":"One","playing":true}}"#,
            #"{"type":"data","diff":true,"payload":{"title":null}}"#
        )
        #expect(state.snapshot == nil)
    }

    @Test func parentApplicationWinsOverTheHelperProcess() throws {
        let state = state(
            applying: #"{"type":"data","diff":false,"payload":{"bundleIdentifier":"com.google.Chrome.helper","parentApplicationBundleIdentifier":"com.google.Chrome","title":"Clip","playing":true}}"#
        )
        #expect(try #require(state.snapshot).bundleIdentifier == "com.google.Chrome")
    }

    @Test func artworkIsDecodedFromBase64() throws {
        let bytes = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A])
        let line = #"{"type":"data","diff":false,"payload":{"bundleIdentifier":"a","title":"One","artworkData":"\#(bytes.base64EncodedString())\n"}}"#
        let snapshot = try #require(state(applying: line).snapshot)
        #expect(snapshot.artworkData == bytes)
    }

    @Test func valueOfTheWrongTypeInADiffIsRemoved() throws {
        let state = state(
            applying: #"{"type":"data","diff":false,"payload":{"bundleIdentifier":"a","title":"One","artist":"Me","artworkData":"AAEC"}}"#,
            // Not base64, and not text: the previous track's must not stay.
            #"{"type":"data","diff":true,"payload":{"artworkData":"%%%","artist":7}}"#
        )
        let snapshot = try #require(state.snapshot)
        #expect(snapshot.title == "One")
        #expect(snapshot.artist == nil)
        #expect(snapshot.artworkData == nil)
    }

    @Test func microsecondTimesBecomeLengthAndPosition() throws {
        let state = state(
            applying: #"{"type":"data","diff":false,"payload":{"bundleIdentifier":"a","title":"One","playing":true,"durationMicros":215000000,"elapsedTimeMicros":12500000,"timestampEpochMicros":1700000000000000,"playbackRate":1}}"#
        )
        let snapshot = try #require(state.snapshot)
        #expect(snapshot.duration == 215)
        #expect(snapshot.position == PlaybackPosition(elapsed: 12.5, date: Date(timeIntervalSince1970: 1_700_000_000), rate: 1))
    }

    @Test func diffWithoutTimesKeepsThem() throws {
        let state = state(
            applying: #"{"type":"data","diff":false,"payload":{"bundleIdentifier":"a","title":"One","playing":true,"durationMicros":215000000,"elapsedTimeMicros":12500000,"timestampEpochMicros":1700000000000000,"playbackRate":1}}"#,
            #"{"type":"data","diff":true,"payload":{"artist":"Me"}}"#
        )
        let snapshot = try #require(state.snapshot)
        #expect(snapshot.duration == 215)
        #expect(snapshot.position?.elapsed == 12.5)
        #expect(snapshot.position?.date == Date(timeIntervalSince1970: 1_700_000_000))
    }

    @Test func diffSetsAndClearsTimes() throws {
        let start = #"{"type":"data","diff":false,"payload":{"bundleIdentifier":"a","title":"One","playing":true,"durationMicros":215000000,"elapsedTimeMicros":12500000,"timestampEpochMicros":1700000000000000}}"#
        let moved = state(
            applying: start,
            #"{"type":"data","diff":true,"payload":{"elapsedTimeMicros":60000000,"timestampEpochMicros":1700000010000000}}"#
        )
        #expect(moved.snapshot?.position == PlaybackPosition(elapsed: 60, date: Date(timeIntervalSince1970: 1_700_000_010)))
        #expect(moved.snapshot?.duration == 215)

        let cleared = state(
            applying: start,
            #"{"type":"data","diff":true,"payload":{"durationMicros":null,"elapsedTimeMicros":null}}"#
        )
        let snapshot = try #require(cleared.snapshot)
        #expect(snapshot.duration == nil)
        // A time without its moment is no position.
        #expect(snapshot.position == nil)
    }

    @Test func pausedRateOfZeroLeavesTheRateToThePlayState() throws {
        let state = state(
            applying: #"{"type":"data","diff":false,"payload":{"bundleIdentifier":"a","title":"One","playing":false,"elapsedTimeMicros":5000000,"timestampEpochMicros":1700000000000000,"playbackRate":0}}"#
        )
        var snapshot = try #require(state.snapshot)
        #expect(snapshot.position?.rate == 1)
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(snapshot.elapsed(at: date + 10) == 5)
        snapshot.isPlaying = true
        #expect(snapshot.elapsed(at: date + 10) == 15)
    }

    @Test func getOutputWithMicrosGivesTheTimes() throws {
        let output = #"{"bundleIdentifier":"a","title":"One","playing":true,"durationMicros":166000000,"elapsedTimeMicros":0,"timestampEpochMicros":1700000000000000}"#
        let update = try #require(MediaRemoteUpdate(getOutput: Data(output.utf8)))
        #expect(update.duration == .set(166))
        #expect(update.elapsedTime == .set(0))
        #expect(update.timestamp == .set(Date(timeIntervalSince1970: 1_700_000_000)))
        #expect(update.playbackRate == .keep)
    }

    @Test func linesThatAreNotDataAreIgnored() {
        #expect(MediaRemoteUpdate(streamLine: "") == nil)
        #expect(MediaRemoteUpdate(streamLine: "not json") == nil)
        #expect(MediaRemoteUpdate(streamLine: #"{"type":"error","message":"x"}"#) == nil)
        #expect(MediaRemoteUpdate(streamLine: #"{"type":"error","payload":{"title":"x"}}"#) == nil)
        #expect(MediaRemoteUpdate(getOutput: Data("null".utf8)) == nil)
        #expect(MediaRemoteUpdate(getOutput: Data()) == nil)
    }
}

struct SystemSnapshotTests {
    @Test func keyIsAppTitleArtistAlbum() throws {
        let snapshot = try #require(PlaybackSnapshot(bundleIdentifier: "com.apple.Safari", isPlaying: true, title: "Clip", artist: "A"))
        #expect(snapshot.trackKey == "com.apple.Safari|Clip|A|")
        #expect(snapshot.player == nil)
    }

    @Test func emptyTitleOrArtworkIsNothing() throws {
        #expect(PlaybackSnapshot(bundleIdentifier: "a", isPlaying: true, title: "") == nil)
        let snapshot = try #require(PlaybackSnapshot(bundleIdentifier: "a", isPlaying: true, title: "T", artworkData: Data()))
        #expect(snapshot.artworkData == nil)
    }

    @Test func scriptedSnapshotKeepsItsPlayerAndKey() throws {
        let snapshot = try #require(PlaybackSnapshot(player: .music, isPlaying: true, title: "T", trackID: "1"))
        #expect(snapshot.player == .music)
        #expect(snapshot.bundleIdentifier == "com.apple.Music")
        #expect(snapshot.trackKey == "com.apple.Music|1")
    }

    @Test func switchingAppsRestartsThePresence() throws {
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        let browser = { (playing: Bool) in PlaybackSnapshot(bundleIdentifier: "browser", isPlaying: playing, title: "Clip") }
        let other = PlaybackSnapshot(bundleIdentifier: "other", isPlaying: false, title: "Song")
        var tracker = PresenceTracker()
        tracker.update(browser(true), now: start)
        tracker.update(other, now: start + 1)
        // A paused track of another app, never seen playing, stays hidden.
        #expect(!tracker.isVisible(at: start + 1))
        tracker.update(browser(true), now: start + 2)
        tracker.update(browser(false), now: start + 3)
        #expect(tracker.isVisible(at: start + 20))
        #expect(!tracker.isVisible(at: start + 34))
    }
}

struct MediaRemoteAdapterTests {
    @Test func runsTheScriptThroughSystemPerl() {
        let adapter = MediaRemoteAdapter(
            script: URL(fileURLWithPath: "/app/Contents/Resources/mediaremote-adapter.pl"),
            framework: URL(fileURLWithPath: "/app/Contents/Frameworks/MediaRemoteAdapter.framework")
        )
        let process = adapter.makeProcess(["send", "2"])
        #expect(process.executableURL?.path == "/usr/bin/perl")
        #expect(process.arguments == [
            "/app/Contents/Resources/mediaremote-adapter.pl",
            "/app/Contents/Frameworks/MediaRemoteAdapter.framework",
            "send",
            "2",
        ])
    }

    @Test func isMissingOutsideAnAppBundle() throws {
        let empty = FileManager.default.temporaryDirectory.appendingPathComponent("adapter-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: empty) }
        let bundle = try #require(Bundle(url: empty))
        #expect(MediaRemoteAdapter.bundled(in: bundle) == nil)
    }
}

@MainActor
struct SystemArtworkTests {
    /// A solid red PNG of `side` points.
    func png(side: Int = 8) throws -> Data {
        let context = try #require(CGContext(
            data: nil,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    func waitForCover(of model: NowPlayingModel) async {
        for _ in 0..<100 where model.cover == nil {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    @Test func coverComesFromTheSystemsImageBytes() async throws {
        let model = NowPlayingModel(scripting: PlayerScripting())
        let snapshot = try #require(PlaybackSnapshot(
            bundleIdentifier: "test.browser",
            isPlaying: true,
            title: "Clip",
            artworkData: try png()
        ))
        model.show(snapshot)
        await waitForCover(of: model)
        #expect(model.cover != nil)
        #expect(model.coverKey == snapshot.trackKey)
        // Red, not the gray fallback.
        #expect(model.palette?.primary.saturation ?? 0 > 0.1)
    }

    @Test func coverArrivingAfterTheTitleReplacesTheStandIn() async throws {
        let model = NowPlayingModel(scripting: PlayerScripting())
        let withoutCover = try #require(PlaybackSnapshot(bundleIdentifier: "test.browser", isPlaying: true, title: "Clip"))
        model.show(withoutCover)
        var withCover = withoutCover
        withCover.artworkData = try png()
        model.show(withCover)
        await waitForCover(of: model)
        for _ in 0..<100 where (model.palette?.primary.saturation ?? 0) < 0.1 {
            try? await Task.sleep(for: .milliseconds(20))
        }
        #expect(model.coverKey == withCover.trackKey)
        #expect(model.palette?.primary.saturation ?? 0 > 0.1)
    }

    @Test func toggleHandsTheFlippedSnapshotToTheFeature() throws {
        let model = NowPlayingModel(scripting: PlayerScripting())
        var received: (command: PlaybackCommand, snapshot: PlaybackSnapshot)?
        model.onCommand = { received = ($0, $1) }
        model.show(try #require(PlaybackSnapshot(bundleIdentifier: "test.browser", isPlaying: true, title: "Clip")))
        model.togglePlayPause()
        #expect(received?.command == .playPause)
        #expect(received?.snapshot.isPlaying == false)
        #expect(received?.snapshot.player == nil)
        #expect(model.isPlaying == false)
    }

    @Test func seekMovesTheShownPositionAtOnce() throws {
        let model = NowPlayingModel(scripting: PlayerScripting())
        var received: (command: PlaybackCommand, snapshot: PlaybackSnapshot)?
        model.onCommand = { received = ($0, $1) }
        model.show(try #require(PlaybackSnapshot(
            bundleIdentifier: "test.browser",
            isPlaying: false,
            title: "Clip",
            duration: 200,
            position: PlaybackPosition(elapsed: 10, date: Date())
        )))
        model.seek(to: 120)
        #expect(received?.command == .seek(120))
        #expect(model.snapshot?.elapsed(at: Date()) == 120)
        #expect(received?.snapshot.elapsed(at: Date()) == 120)
    }

    @Test func skippingChangesNothingOnScreen() throws {
        let model = NowPlayingModel(scripting: PlayerScripting())
        var commands: [PlaybackCommand] = []
        model.onCommand = { command, _ in commands.append(command) }
        let shown = try #require(PlaybackSnapshot(bundleIdentifier: "test.browser", isPlaying: true, title: "Clip"))
        model.show(shown)
        model.next()
        model.previous()
        #expect(commands == [.next, .previous])
        #expect(model.snapshot == shown)
    }

    @Test func tabFollowsWhetherATrackIsKnownWhileTheWingsKeepTheLastOne() async throws {
        let model = NowPlayingModel(scripting: PlayerScripting(), trackGrace: .milliseconds(20))
        #expect(!model.hasTrack)
        let shown = try #require(PlaybackSnapshot(bundleIdentifier: "test.browser", isPlaying: true, title: "Clip"))
        model.show(shown)
        #expect(model.hasTrack)
        model.show(nil)
        try await Task.sleep(for: .milliseconds(200))
        #expect(!model.hasTrack)
        #expect(model.snapshot == shown)
    }

    @Test func aBriefGapKeepsTheTab() async throws {
        let model = NowPlayingModel(scripting: PlayerScripting(), trackGrace: .milliseconds(100))
        let shown = try #require(PlaybackSnapshot(bundleIdentifier: "test.browser", isPlaying: true, title: "Clip"))
        model.show(shown)
        // A stream restart: nothing for a moment, then the track again.
        model.show(nil)
        #expect(model.hasTrack)
        model.show(shown)
        try await Task.sleep(for: .milliseconds(300))
        #expect(model.hasTrack)
    }

    @Test func readingThatOnlyMovesThePositionOnKeepsTheShownSnapshot() throws {
        let model = NowPlayingModel(scripting: PlayerScripting())
        let start = Date()
        let first = try #require(PlaybackSnapshot(
            player: .music,
            isPlaying: true,
            title: "Song",
            trackID: "1",
            duration: 200,
            position: PlaybackPosition(elapsed: 10, date: start)
        ))
        model.show(first)
        // Three seconds on, read 0.2 s behind where the anchor puts it.
        var later = first
        later.position = PlaybackPosition(elapsed: 12.8, date: start + 3)
        model.show(later)
        #expect(model.snapshot == first)
    }
}

/// Records what a `MediaRemoteMonitor` reports.
@MainActor
final class MonitorRecorder {
    var snapshots: [PlaybackSnapshot?] = []
    var isUnavailable = false

    var latest: PlaybackSnapshot? { snapshots.last ?? nil }

    func eventually(_ timeout: Duration = .seconds(5), _ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            guard ContinuousClock.now < deadline else { return false }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return true
    }
}

/// Drives the real monitor against a stub perl script standing in for the adapter:
/// perl runs `<script> <framework> <function> ...`, so the stub sees the function
/// as its second argument. The vendored adapter itself is never run by the tests.
@MainActor
struct MediaRemoteMonitorTests {
    static let playingLine = #"{"type":"data","diff":false,"payload":{"bundleIdentifier":"helper","parentApplicationBundleIdentifier":"parent","title":"One","playing":true,"artworkData":"AAEC"}}"#

    func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("adapter-stub-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func stub(_ body: String, in directory: URL) throws -> MediaRemoteAdapter {
        let script = directory.appendingPathComponent("stub.pl")
        let source = "use strict; use warnings; $| = 1;\nmy $function = $ARGV[1] // '';\n" + body
        try source.write(to: script, atomically: true, encoding: .utf8)
        return MediaRemoteAdapter(script: script, framework: directory)
    }

    func monitor(_ adapter: MediaRemoteAdapter, recorder: MonitorRecorder) -> MediaRemoteMonitor {
        MediaRemoteMonitor(
            adapter: adapter,
            restartDelay: .milliseconds(10),
            settleDelay: .milliseconds(10),
            onChange: { recorder.snapshots.append($0) },
            onUnavailable: { recorder.isUnavailable = true }
        )
    }

    @Test func streamsSnapshotsAndStopEndsThePerlProcess() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let pidFile = directory.appendingPathComponent("pid")
        let adapter = try stub("""
        if ($function eq 'stream') {
            open(my $pid, '>', '\(pidFile.path)') or die; print $pid $$; close $pid;
            print q(\(Self.playingLine)), "\\n";
            sleep 60;
        }
        """, in: directory)
        let recorder = MonitorRecorder()
        let monitor = monitor(adapter, recorder: recorder)
        monitor.start()
        #expect(await recorder.eventually { recorder.latest?.title == "One" })
        #expect(recorder.latest?.bundleIdentifier == "parent")
        let pid = try #require(Int32(try String(contentsOf: pidFile, encoding: .utf8)))
        #expect(kill(pid, 0) == 0)

        monitor.stop()
        #expect(await recorder.eventually(.seconds(3)) { kill(pid, 0) != 0 })
        #expect(!recorder.isUnavailable)
    }

    @Test func givesUpAfterThreeQuickExits() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let adapter = try stub("exit 1;\n", in: directory)
        let recorder = MonitorRecorder()
        let monitor = monitor(adapter, recorder: recorder)
        monitor.start()
        #expect(await recorder.eventually { recorder.isUnavailable })
        // Nothing playing is reported once per ended stream.
        #expect(recorder.snapshots.count == MediaRemoteMonitor.maximumQuickExits)
        #expect(recorder.snapshots.allSatisfy { $0 == nil })
        monitor.stop()
    }

    @Test func readBackOfAnIgnoredCommandCorrectsOnlyThePlayState() async throws {
        // Paused, the click does nothing, and `get` (without a cover, naming the helper
        // process) says paused again: the held "playing" must give way, the rest stay.
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let paused = Self.playingLine.replacingOccurrences(of: #""playing":true"#, with: #""playing":false"#)
        let adapter = try stub("""
        if ($function eq 'stream') { print q(\(paused)), "\\n"; sleep 60; }
        elsif ($function eq 'get') { print q({"bundleIdentifier":"helper","title":"One","playing":false}), "\\n"; }
        """, in: directory)
        let recorder = MonitorRecorder()
        let monitor = monitor(adapter, recorder: recorder)
        monitor.start()
        #expect(await recorder.eventually { recorder.latest?.title == "One" })
        let before = recorder.snapshots.count

        await monitor.togglePlayPause()
        #expect(recorder.snapshots.count == before + 1)
        let latest = try #require(recorder.latest)
        #expect(!latest.isPlaying)
        #expect(latest.bundleIdentifier == "parent")
        #expect(latest.artworkData != nil)
        monitor.stop()
    }

    @Test func readBackOfAnObeyedCommandPublishesNothing() async throws {
        // The feature already shows the flipped state; the monitor holds it too.
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let adapter = try stub("""
        if ($function eq 'stream') { print q(\(Self.playingLine)), "\\n"; sleep 60; }
        elsif ($function eq 'get') { print q({"bundleIdentifier":"helper","title":"One","playing":false}), "\\n"; }
        """, in: directory)
        let recorder = MonitorRecorder()
        let monitor = monitor(adapter, recorder: recorder)
        monitor.start()
        #expect(await recorder.eventually { recorder.latest?.isPlaying == true })
        let before = recorder.snapshots.count

        await monitor.togglePlayPause()
        #expect(recorder.snapshots.count == before)
        monitor.stop()
    }

    @Test func readBackIsDroppedOnceTheStreamHasSpoken() async throws {
        // The app obeys: the stream says paused soon after the click, while `get` is
        // slow and still says playing.
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let adapter = try stub("""
        if ($function eq 'stream') {
            print q(\(Self.playingLine)), "\\n";
            sleep 1;
            print q({"type":"data","diff":true,"payload":{"playing":false}}), "\\n";
            sleep 60;
        } elsif ($function eq 'get') {
            sleep 2;
            print q({"bundleIdentifier":"helper","title":"One","playing":true}), "\\n";
        }
        """, in: directory)
        let recorder = MonitorRecorder()
        let monitor = monitor(adapter, recorder: recorder)
        monitor.start()
        #expect(await recorder.eventually { recorder.latest?.isPlaying == true })

        await monitor.togglePlayPause()
        #expect(recorder.latest?.isPlaying == false)
        monitor.stop()
    }

    @Test func seekSendsMicrosecondsAndTakesThePositionReadBack() async throws {
        // The stream runs with --micros; the app ignores the seek, and `get` says
        // where it still is: the held position must give way to that.
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let seekFile = directory.appendingPathComponent("seek")
        let timed = #"{"type":"data","diff":false,"payload":{"bundleIdentifier":"a","title":"One","playing":false,"durationMicros":200000000,"elapsedTimeMicros":10000000,"timestampEpochMicros":1700000000000000}}"#
        let adapter = try stub("""
        if ($function eq 'stream') {
            if (grep { $_ eq '--micros' } @ARGV) { print q(\(timed)), "\\n"; }
            sleep 60;
        } elsif ($function eq 'seek') {
            open(my $out, '>', '\(seekFile.path)') or die; print $out $ARGV[2]; close $out;
        } elsif ($function eq 'get' && grep { $_ eq '--micros' } @ARGV) {
            print q({"bundleIdentifier":"a","title":"One","playing":false,"elapsedTimeMicros":10000000,"timestampEpochMicros":1700000000000000}), "\\n";
        }
        """, in: directory)
        let recorder = MonitorRecorder()
        let monitor = monitor(adapter, recorder: recorder)
        monitor.start()
        #expect(await recorder.eventually { recorder.latest?.title == "One" })
        let before = recorder.snapshots.count

        await monitor.seek(to: 90.5)
        #expect(try String(contentsOf: seekFile, encoding: .utf8) == "90500000")
        #expect(recorder.snapshots.count == before + 1)
        let latest = try #require(recorder.latest)
        #expect(latest.position?.elapsed == 10)
        #expect(latest.duration == 200)
        monitor.stop()
    }

    @Test func togglingAStoppedMonitorChangesNothing() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let adapter = try stub(#"print q({"title":"One","playing":false}), "\\n";"# + "\n", in: directory)
        let recorder = MonitorRecorder()
        let monitor = monitor(adapter, recorder: recorder)
        await monitor.togglePlayPause()
        #expect(recorder.snapshots.isEmpty)
    }
}

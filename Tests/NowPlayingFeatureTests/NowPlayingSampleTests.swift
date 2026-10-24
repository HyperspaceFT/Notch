import Foundation
import Testing
@testable import NowPlayingFeature

@MainActor
struct NowPlayingSampleTests {
    private let now = Date(timeIntervalSinceReferenceDate: 0)

    @Test func theSampleShowsOverEveryRealSource() throws {
        let sample = try #require(NowPlayingSample.track(now: now))
        let system = try #require(PlaybackSnapshot(bundleIdentifier: "com.example.player", isPlaying: true, title: "Real"))
        let music = try #require(PlaybackSnapshot(player: .music, isPlaying: true, title: "Music"))
        let shown = NowPlayingFeature.shown(sample: sample, system: system, players: [.music: music], preferring: .music)
        #expect(shown == sample)
    }

    @Test func withoutTheSampleTheRealSourcesShowAgain() throws {
        let system = try #require(PlaybackSnapshot(bundleIdentifier: "com.example.player", isPlaying: true, title: "Real"))
        let music = try #require(PlaybackSnapshot(player: .music, isPlaying: true, title: "Music"))
        #expect(NowPlayingFeature.shown(sample: nil, system: system, players: [.music: music], preferring: nil) == system)
        #expect(NowPlayingFeature.shown(sample: nil, system: nil, players: [.music: music], preferring: nil) == music)
        #expect(NowPlayingFeature.shown(sample: nil, system: nil, players: [:], preferring: nil) == nil)
    }

    @Test func samplesPlayWithACoverALengthAndAMovingPosition() throws {
        for sample in [NowPlayingSample.track(now: now), NowPlayingSample.longTitle(now: now)] {
            let sample = try #require(sample)
            #expect(sample.isPlaying)
            #expect(sample.player == nil)
            #expect(sample.artworkData != nil)
            let duration = try #require(sample.duration)
            let start = try #require(sample.elapsed(at: now))
            #expect(sample.elapsed(at: now.addingTimeInterval(5)) == start + 5)
            #expect(start < duration)
        }
    }

    @Test func coverIsAnImageTheArtworkPathReads() throws {
        let data = try #require(NowPlayingSample.cover(hue: 0.6, symbol: "music.note"))
        let artwork = try #require(ArtworkProcessor.process(data))
        #expect(artwork.image.width == ArtworkProcessor.displaySize)
    }

    @Test func skippingSwitchesToTheOtherSampleFromItsStart() throws {
        var track = try #require(NowPlayingSample.track(now: now))
        track.setPlaying(false, at: now)
        let later = now.addingTimeInterval(10)
        let other = try #require(NowPlayingSample.other(than: track, now: later))
        #expect(other.trackKey == NowPlayingSample.longTitle(now: later)?.trackKey)
        #expect(!other.isPlaying)
        #expect(other.elapsed(at: later) == 0)
        let back = try #require(NowPlayingSample.other(than: other, now: later))
        #expect(back.trackKey == track.trackKey)
    }

    @Test func theSampleFlagFollowsShowingAndStoppingASample() throws {
        let model = NowPlayingModel(scripting: PlayerScripting())
        let sample = try #require(PlaybackSnapshot(bundleIdentifier: "com.example.sample", isPlaying: true, title: "Sample"))
        #expect(!model.isShowingSample)
        model.show(sample, isSample: true)
        #expect(model.isShowingSample)
        // A skip or a pause shows the next sample reading the same way.
        model.show(sample, isSample: true)
        #expect(model.isShowingSample)
        // Stopping the sample shows the real sources again, or nothing.
        model.show(nil)
        #expect(!model.isShowingSample)
        model.show(sample, isSample: true)
        model.show(sample)
        #expect(!model.isShowingSample)
    }

    @Test func resettingEndsTheSample() throws {
        let model = NowPlayingModel(scripting: PlayerScripting())
        let sample = try #require(PlaybackSnapshot(bundleIdentifier: "com.example.sample", isPlaying: true, title: "Sample"))
        model.show(sample, isSample: true)
        model.reset()
        #expect(!model.isShowingSample)
    }
}

import AppKit
import ImageIO
import Observation
import SwiftUI

/// What the wings show: the current track, its cover and colors, and its rhythm.
@MainActor
@Observable
final class NowPlayingModel {
    /// The track shown; kept after playback ends so the wings do not go blank
    /// while they leave.
    private(set) var snapshot: PlaybackSnapshot?
    private(set) var isPlaying = false
    /// The cover, else the player's icon, else `nil` (a placeholder is drawn).
    private(set) var cover: NSImage?
    /// The track `cover` belongs to. Changes together with `cover`, so the flip to
    /// a new track shows the new cover rather than the old one or a placeholder.
    private(set) var coverKey: String?
    private(set) var palette: Palette?
    private(set) var rhythm = PulseRhythm(seed: 0)
    var isPulseHovered = false

    /// Asks the app that plays the shown track to play or pause; set by the feature.
    @ObservationIgnored var onToggle: (@MainActor (PlaybackSnapshot) -> Void)?

    @ObservationIgnored private let scripting: PlayerScripting
    @ObservationIgnored private var artworkTask: Task<Void, Never>?
    /// Processed covers by Spotify address or Music track key, newest last. Covers
    /// that came with the system's now-playing information are not cached: they
    /// arrive as bytes, and one track's cover can arrive after its title.
    @ObservationIgnored private var artworkCache: [(key: String, artwork: ProcessedArtwork)] = []
    @ObservationIgnored private var iconCache: [String: ProcessedArtwork] = [:]

    static let artworkCacheLimit = 12
    /// Spotify's image server rarely takes long; past this the icon stands in.
    static let artworkRequestTimeout: TimeInterval = 10

    init(scripting: PlayerScripting) {
        self.scripting = scripting
    }

    func show(_ new: PlaybackSnapshot?) {
        guard let new else {
            if isPlaying { isPlaying = false }
            return
        }
        let isNewTrack = new.trackKey != snapshot?.trackKey
        let isNewArtwork = new.artworkData != snapshot?.artworkData
        if snapshot != new { snapshot = new }
        if isPlaying != new.isPlaying { isPlaying = new.isPlaying }
        if isNewTrack {
            rhythm = PulseRhythm(seed: PlaybackSnapshot.stableHash(new.trackKey))
        }
        if isNewTrack || isNewArtwork {
            loadArtwork(for: new)
        }
    }

    /// Flips play and pause on screen at once; the next reading corrects it if
    /// the player did not follow.
    func togglePlayPause() {
        guard var snapshot else { return }
        snapshot.isPlaying.toggle()
        self.snapshot = snapshot
        isPlaying = snapshot.isPlaying
        onToggle?(snapshot)
    }

    func reset() {
        artworkTask?.cancel()
        artworkTask = nil
        artworkCache = []
        snapshot = nil
        isPlaying = false
        cover = nil
        coverKey = nil
        palette = nil
        isPulseHovered = false
    }

    private func loadArtwork(for snapshot: PlaybackSnapshot) {
        artworkTask?.cancel()
        let key = snapshot.trackKey
        let cacheKey = snapshot.player == nil ? nil : snapshot.artworkURL ?? key
        if let cacheKey, let cached = artworkCache.first(where: { $0.key == cacheKey })?.artwork {
            artworkTask = nil
            apply(cached, for: key)
            return
        }
        artworkTask = Task { [weak self, scripting] in
            let data = await Self.artwork(of: snapshot, scripting: scripting)
            let processed: ProcessedArtwork? = if let data {
                await Task.detached(priority: .utility) { ArtworkProcessor.process(data) }.value
            } else {
                nil
            }
            guard !Task.isCancelled, let self, self.snapshot?.trackKey == key else { return }
            if let processed {
                if let cacheKey {
                    remember(processed, as: cacheKey)
                }
                apply(processed, for: key)
            } else {
                await applyIcon(ofApp: snapshot.bundleIdentifier, for: key)
            }
        }
    }

    private static func artwork(of snapshot: PlaybackSnapshot, scripting: PlayerScripting) async -> Data? {
        switch snapshot.player {
        case .music:
            await musicArtwork(scripting: scripting, trackID: snapshot.trackID)
        case .spotify:
            await download(snapshot.artworkURL)
        case nil:
            snapshot.artworkData
        }
    }

    private static func musicArtwork(scripting: PlayerScripting, trackID: String?) async -> Data? {
        guard SupportedPlayer.music.isRunning, let artwork = await scripting.readMusicArtwork() else { return nil }
        // The track changed between the state read and this one.
        guard trackID == nil || artwork.trackID == trackID else { return nil }
        return artwork.data
    }

    private static func download(_ address: String?) async -> Data? {
        guard let address, let url = URL(string: address), url.scheme == "https" else { return nil }
        let request = URLRequest(url: url, timeoutInterval: artworkRequestTimeout)
        guard
            let (data, response) = try? await URLSession.shared.data(for: request),
            (response as? HTTPURLResponse)?.statusCode == 200
        else { return nil }
        return data
    }

    /// Without a cover: the app's icon, else nothing (the view's placeholder).
    private func applyIcon(ofApp bundleIdentifier: String, for key: String) async {
        if let cached = iconCache[bundleIdentifier] {
            apply(cached, for: key)
            return
        }
        guard
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier),
            let image = Self.cgImage(of: NSWorkspace.shared.icon(forFile: url.path))
        else {
            apply(nil, for: key)
            return
        }
        let processed = await Task.detached(priority: .utility) { ArtworkProcessor.process(image) }.value
        iconCache[bundleIdentifier] = processed
        // A cover for the same track may have replaced this load meanwhile.
        guard !Task.isCancelled, snapshot?.trackKey == key else { return }
        apply(processed, for: key)
    }

    private func apply(_ artwork: ProcessedArtwork?, for key: String) {
        cover = artwork.map { NSImage(cgImage: $0.image, size: .zero) }
        palette = artwork?.palette
        coverKey = key
    }

    private func remember(_ artwork: ProcessedArtwork, as key: String) {
        artworkCache.removeAll { $0.key == key }
        artworkCache.append((key, artwork))
        if artworkCache.count > Self.artworkCacheLimit {
            artworkCache.removeFirst()
        }
    }

    private static func cgImage(of icon: NSImage) -> CGImage? {
        var rect = CGRect(x: 0, y: 0, width: ArtworkProcessor.displaySize, height: ArtworkProcessor.displaySize)
        return icon.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }
}

/// A cover scaled down for the wing, with its palette.
struct ProcessedArtwork: Sendable {
    var image: CGImage
    var palette: Palette
}

/// Decodes and measures covers; called off the main thread.
enum ArtworkProcessor {
    /// Pixel size of the displayed cover: a 24 pt cover at 2x with room for the glow.
    static let displaySize = 96
    /// The palette is read from a tiny copy; more pixels add nothing.
    static let paletteSize = 20

    static func process(_ data: Data) -> ProcessedArtwork? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: displaySize,
        ]
        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }
        return process(image)
    }

    static func process(_ image: CGImage) -> ProcessedArtwork {
        ProcessedArtwork(image: image, palette: palette(of: image))
    }

    private static func palette(of image: CGImage) -> Palette {
        let side = paletteSize
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: side,
                height: side,
                bitsPerComponent: 8,
                bytesPerRow: side * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        }
        return ArtworkPalette.extract(fromRGBA: bytes, width: side, height: side)
    }
}

extension HSBColor {
    var color: Color {
        Color(hue: hue, saturation: saturation, brightness: brightness)
    }
}

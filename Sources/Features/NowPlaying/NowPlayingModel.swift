import AppKit
import ImageIO
import Observation
import SwiftUI

/// What the wings and the tab show: the current track, its cover and colors, its
/// rhythm, and the app that plays it.
@MainActor
@Observable
final class NowPlayingModel {
    /// The track shown; kept after playback ends so the wings do not go blank
    /// while they leave.
    private(set) var snapshot: PlaybackSnapshot?
    /// Whether a source reports a track, unlike `snapshot`, which stays. It
    /// outlasts a gap of up to `trackGrace` (a stream restarting, a source
    /// switch), so the tab does not vanish and send the open panel back to Home.
    private(set) var hasTrack = false
    private(set) var isPlaying = false
    /// Whether the shown track is the Debug pane's sample. Observable, so the pane
    /// redraws with its sample-only actions; the sample's controls reach no real app.
    private(set) var isShowingSample = false
    /// The cover, else the player's icon, else `nil` (a placeholder is drawn).
    private(set) var cover: NSImage?
    /// The track `cover` belongs to. Changes together with `cover`, so the flip to
    /// a new track shows the new cover rather than the old one or a placeholder.
    private(set) var coverKey: String?
    private(set) var palette: Palette?
    private(set) var rhythm = PulseRhythm(seed: 0)
    /// The playing app's name and icon, for the tab.
    private(set) var appName: String?
    private(set) var appIcon: NSImage?
    var isPulseHovered = false

    /// Hands a command for the app that plays the shown track to the feature, with
    /// the snapshot as already changed on screen; set by the feature.
    @ObservationIgnored var onCommand: (@MainActor (PlaybackCommand, PlaybackSnapshot) -> Void)?
    /// Opens the expanded panel on the Now Playing tab; set by the feature.
    @ObservationIgnored var onOpenDetail: (@MainActor () -> Void)?

    @ObservationIgnored private let scripting: PlayerScripting
    @ObservationIgnored private var artworkTask: Task<Void, Never>?
    @ObservationIgnored private let trackGrace: Duration
    /// Clears `hasTrack` once a gap has lasted `trackGrace`.
    @ObservationIgnored private var trackLoss: Task<Void, Never>?
    /// Processed covers by Spotify address or Music track key, newest last. Covers
    /// that came with the system's now-playing information are not cached: they
    /// arrive as bytes, and one track's cover can arrive after its title.
    @ObservationIgnored private var artworkCache: [(key: String, artwork: ProcessedArtwork)] = []
    @ObservationIgnored private var iconCache: [String: ProcessedArtwork] = [:]

    static let artworkCacheLimit = 12
    /// Spotify's image server rarely takes long; past this the icon stands in.
    static let artworkRequestTimeout: TimeInterval = 10

    init(scripting: PlayerScripting, trackGrace: Duration = .seconds(3)) {
        self.scripting = scripting
        self.trackGrace = trackGrace
    }

    func show(_ new: PlaybackSnapshot?, isSample: Bool = false) {
        if isShowingSample != isSample { isShowingSample = isSample }
        guard let reading = new else {
            if isPlaying { isPlaying = false }
            if hasTrack, trackLoss == nil {
                trackLoss = Task { [weak self, trackGrace] in
                    try? await Task.sleep(for: trackGrace)
                    guard !Task.isCancelled, let self else { return }
                    trackLoss = nil
                    hasTrack = false
                }
            }
            return
        }
        trackLoss?.cancel()
        trackLoss = nil
        if !hasTrack { hasTrack = true }
        // A reading that only moved the position on as expected keeps the shown
        // anchor, so it compares equal and nothing redraws.
        let new = reading.steadied(against: snapshot)
        let isNewTrack = new.trackKey != snapshot?.trackKey
        let isNewArtwork = new.artworkData != snapshot?.artworkData
        if new.bundleIdentifier != snapshot?.bundleIdentifier {
            showApp(new.bundleIdentifier, player: new.player)
        }
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
        perform(.playPause)
    }

    func next() {
        perform(.next)
    }

    func previous() {
        perform(.previous)
    }

    /// Moves the shown position at once; the next reading corrects it if the
    /// player did not follow.
    func seek(to seconds: TimeInterval) {
        perform(.seek(seconds))
    }

    private func perform(_ command: PlaybackCommand) {
        guard var snapshot else { return }
        snapshot.apply(command, at: Date())
        self.snapshot = snapshot
        isPlaying = snapshot.isPlaying
        onCommand?(command, snapshot)
    }

    /// Shows the track in full, in the tab; the wing's cover asks for it.
    func openDetail() {
        onOpenDetail?()
    }

    /// Brings the app that plays the shown track to the front; nothing when it
    /// is not running, so a click never launches anything. A sample claims a real
    /// app (Music) but plays in none, so it brings nothing to the front.
    func showPlayingApp() {
        guard
            !isShowingSample,
            let bundleIdentifier = snapshot?.bundleIdentifier,
            let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
                .first(where: { !$0.isTerminated }),
            let url = app.bundleURL
        else { return }
        // Opening the running app activates it. `activate()` would not: Notch is
        // an accessory app that is almost never active, and macOS lets only the
        // active app hand activation over.
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }

    func reset() {
        artworkTask?.cancel()
        artworkTask = nil
        artworkCache = []
        snapshot = nil
        trackLoss?.cancel()
        trackLoss = nil
        hasTrack = false
        isPlaying = false
        isShowingSample = false
        appName = nil
        appIcon = nil
        cover = nil
        coverKey = nil
        palette = nil
        isPulseHovered = false
    }

    private func showApp(_ bundleIdentifier: String, player: SupportedPlayer?) {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first
        let url = running?.bundleURL ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
        appName = running?.localizedName
            ?? url.map { FileManager.default.displayName(atPath: $0.path) }.map { name in
                name.hasSuffix(".app") ? String(name.dropLast(4)) : name
            }
            ?? player?.displayName
        appIcon = running?.icon ?? url.map { NSWorkspace.shared.icon(forFile: $0.path) }
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

/// A cover scaled down for the tab's large cover (the wing draws it smaller), with its palette.
struct ProcessedArtwork: Sendable {
    var image: CGImage
    var palette: Palette
}

/// Decodes and measures covers; called off the main thread.
enum ArtworkProcessor {
    /// Pixel size of the displayed cover: the tab's cover, about 130 pt, at 2x
    /// (the wing's 24 pt one is drawn from the same image).
    static let displaySize = 288
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

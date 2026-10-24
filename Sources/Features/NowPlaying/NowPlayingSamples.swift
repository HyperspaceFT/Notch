import AppKit
import NotchKit

/// Sample tracks for the Debug pane, as the system's now-playing information
/// would report them, with covers drawn here rather than downloaded.
enum NowPlayingSample {
    /// The app the samples claim to play in: its name and icon show in the tab.
    static let bundleIdentifier = "com.apple.Music"

    /// A playing track of usual length, 42 seconds in at `now`.
    @MainActor static func track(now: Date) -> PlaybackSnapshot? {
        PlaybackSnapshot(
            bundleIdentifier: bundleIdentifier,
            isPlaying: true,
            title: localized(en: "Midnight Drive", zh: "午夜驾驶"),
            artist: localized(en: "The Sample Band", zh: "示例乐队"),
            album: localized(en: "City Lights", zh: "城市灯火"),
            artworkData: cover(hue: 0.62, symbol: "music.note"),
            duration: 214,
            position: PlaybackPosition(elapsed: 42, date: now)
        )
    }

    /// A playing track whose title, artist, and album all run long.
    @MainActor static func longTitle(now: Date) -> PlaybackSnapshot? {
        PlaybackSnapshot(
            bundleIdentifier: bundleIdentifier,
            isPlaying: true,
            title: localized(
                en: "A Very Long Song Title That Keeps Going Well Past the Edge of the Island (Extended Mix)",
                zh: "一首标题特别特别长、一直延伸到灵动岛边缘之外的示例歌曲（加长混音版）"
            ),
            artist: localized(
                en: "The Sample Orchestra featuring Several Guest Singers",
                zh: "示例管弦乐团与多位特邀歌手"
            ),
            album: localized(
                en: "Songs for Checking How Long Names Are Cut Short, Volume Two",
                zh: "用来检查长名称如何截断的歌曲集 第二辑"
            ),
            artworkData: cover(hue: 0.08, symbol: "waveform"),
            duration: 427,
            position: PlaybackPosition(elapsed: 3, date: now)
        )
    }

    /// The sample after `snapshot` (for next and previous): the other of the
    /// two, from its start, playing or paused as `snapshot` was.
    @MainActor static func other(than snapshot: PlaybackSnapshot, now: Date) -> PlaybackSnapshot? {
        let usual = track(now: now)
        var other = snapshot.trackKey == usual?.trackKey ? longTitle(now: now) : usual
        other?.position = PlaybackPosition(elapsed: 0, date: now)
        other?.isPlaying = snapshot.isPlaying
        return other
    }

    /// A square diagonal gradient of `hue` with `symbol` in white on it, as PNG.
    static func cover(hue: Double, symbol: String) -> Data? {
        let side = 600
        guard
            let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: side,
                pixelsHigh: side,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            ),
            let context = NSGraphicsContext(bitmapImageRep: bitmap)
        else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        let bounds = NSRect(x: 0, y: 0, width: side, height: side)
        NSGradient(
            starting: NSColor(hue: hue, saturation: 0.75, brightness: 0.95, alpha: 1),
            ending: NSColor(hue: (hue + 0.12).truncatingRemainder(dividingBy: 1), saturation: 0.85, brightness: 0.45, alpha: 1)
        )?.draw(in: bounds, angle: -45)
        let configuration = NSImage.SymbolConfiguration(pointSize: CGFloat(side) * 0.4, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) {
            let size = image.size
            image.draw(in: NSRect(
                x: (CGFloat(side) - size.width) / 2,
                y: (CGFloat(side) - size.height) / 2,
                width: size.width,
                height: size.height
            ))
        }
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.representation(using: .png, properties: [:])
    }
}

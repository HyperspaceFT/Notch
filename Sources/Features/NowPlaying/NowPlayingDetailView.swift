import NotchKit
import NotchUI
import SwiftUI

/// The Now Playing tab: the cover on the left; on the right the playing app, the
/// track, its progress, and the transport controls.
struct NowPlayingDetailView: View {
    let model: NowPlayingModel
    @Environment(\.notchTabMorph) private var morph

    /// The panel keeps every tab's view in place and shows one; the clocks of
    /// this one stop while another is shown.
    private var isShown: Bool {
        guard let morph else { return true }
        return morph.tabID == morph.shownTabID
    }

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 16) {
                NowPlayingCover(model: model, side: proxy.size.height)
                VStack(alignment: .leading, spacing: 0) {
                    appLine
                    Spacer(minLength: 6)
                    titles
                    Spacer(minLength: 6)
                    if let snapshot = model.snapshot, let duration = snapshot.duration, snapshot.position != nil {
                        PlaybackProgressBar(model: model, snapshot: snapshot, duration: duration, isActive: isShown)
                        Spacer(minLength: 6)
                    }
                    controls
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
    }

    private var appLine: some View {
        HStack(spacing: 6) {
            if let icon = model.appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 14, height: 14)
            }
            Text(model.appName ?? "")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(NotchTheme.secondaryText)
                .lineLimit(1)
            Spacer(minLength: 8)
            WaveStrands(model: model, isActive: isShown)
                .frame(width: 22, height: 12)
                .animation(.spring(duration: 0.6, bounce: 0.25), value: model.isPlaying)
                .accessibilityHidden(true)
        }
    }

    private var titles: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(model.snapshot?.title ?? "")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(NotchTheme.primaryText)
                .lineLimit(1)
                .truncationMode(.tail)
            if let byline {
                Text(byline)
                    .font(.system(size: 12))
                    .foregroundStyle(NotchTheme.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }

    /// "artist — album", or whichever of the two there is.
    private var byline: String? {
        let parts = [model.snapshot?.artist, model.snapshot?.album].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " — ")
    }

    private var controls: some View {
        HStack(spacing: 14) {
            GlassIconButton(symbol: "backward.fill", help: localized(en: "Previous", zh: "上一首")) {
                model.previous()
            }
            .accessibilityLabel(localized(en: "Previous", zh: "上一首"))
            PlayPauseButton(model: model)
            GlassIconButton(symbol: "forward.fill", help: localized(en: "Next", zh: "下一首")) {
                model.next()
            }
            .accessibilityLabel(localized(en: "Next", zh: "下一首"))
        }
        .frame(maxWidth: .infinity)
    }
}

/// The cover, large: it glows in its own colors while playing, sinks back while
/// paused, and flips over when the track changes, like the wing's. A click
/// brings the playing app to the front.
private struct NowPlayingCover: View {
    let model: NowPlayingModel
    let side: CGFloat

    private static let cornerRadius: CGFloat = 12

    var body: some View {
        Button {
            model.showPlayingApp()
        } label: {
            ZStack {
                // One view per cover, as in the wing, so the flip runs between them.
                cover
                    .id(model.coverKey)
                    .transition(.flip)
            }
            .animation(.smooth(duration: 0.24), value: model.coverKey)
            .frame(width: side, height: side)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private var cover: some View {
        let isPlaying = model.isPlaying
        let shape = RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
        return ZStack {
            if NotchAppearance.shared.isLightAndColorEnabled, let cover = model.cover {
                Image(nsImage: cover)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: side, height: side)
                    .clipShape(shape)
                    .scaleEffect(1.04)
                    .blur(radius: 16)
                    .opacity(isPlaying ? 0.55 : 0)
                    .allowsHitTesting(false)
            }
            Group {
                if let cover = model.cover {
                    Image(nsImage: cover)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    ZStack {
                        Color.white.opacity(0.12)
                        Image(systemName: "music.note")
                            .font(.system(size: side * 0.36, weight: .semibold))
                            .foregroundStyle(NotchTheme.primaryText)
                    }
                }
            }
            .frame(width: side, height: side)
            .clipShape(shape)
            .scaleEffect(isPlaying ? 1 : 0.92)
            .saturation(isPlaying ? 1 : 0.4)
            .opacity(isPlaying ? 1 : 0.75)
        }
        .animation(.smooth(duration: 0.35), value: isPlaying)
    }

    private var accessibilityLabel: String {
        guard let name = model.appName else { return localized(en: "Cover", zh: "封面") }
        return localized(en: "Cover, opens \(name)", zh: "封面，打开\(name)")
    }
}

/// The main button, larger than its neighbours and tinted like a selected
/// `GlassIconButton`.
private struct PlayPauseButton: View {
    let model: NowPlayingModel

    var body: some View {
        let label = model.isPlaying ? localized(en: "Pause", zh: "暂停") : localized(en: "Play", zh: "播放")
        Button {
            model.togglePlayPause()
        } label: {
            Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(NotchTheme.primaryText)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 36, height: 36)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.tint(.white.opacity(0.18)).interactive(), in: .circle)
        .help(label)
        .accessibilityLabel(label)
    }
}

/// Elapsed time, a thin bar, and the time left. Clicking or dragging on the bar
/// shows the position under the pointer and seeks there on release.
private struct PlaybackProgressBar: View {
    let model: NowPlayingModel
    let snapshot: PlaybackSnapshot
    let duration: TimeInterval
    let isActive: Bool
    /// Share of the track under the pointer while the bar is held; `nil` otherwise.
    /// Gesture state rather than `@State`, which needs a macro plugin the Command
    /// Line Tools do not ship; it also clears itself when the drag ends.
    @GestureState private var dragFraction: Double?

    /// Step of the accessibility increment and decrement actions.
    private static let accessibilityStep: TimeInterval = 10

    var body: some View {
        // Four times a second is enough for the seconds to turn over on time; the
        // bar moves less than a point between frames on a track of a few minutes.
        TimelineView(.animation(minimumInterval: 0.25, paused: !snapshot.isPlaying || !isActive || dragFraction != nil)) { timeline in
            // Coming out of a pause, the timeline can first hand over the date it
            // stopped at, older than an anchor set since (a seek, a resume).
            let now = max(timeline.date, snapshot.position?.date ?? timeline.date)
            let elapsed = dragFraction.map { $0 * duration } ?? snapshot.elapsed(at: now) ?? 0
            let labels = PlaybackTime.labels(elapsed: elapsed, duration: duration)
            HStack(spacing: 8) {
                Text(labels.elapsed)
                    .fixedSize()
                bar(fraction: elapsed / duration)
                Text(labels.remaining)
                    .fixedSize()
            }
            .font(.system(size: 10, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(NotchTheme.secondaryText)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(localized(en: "Playback position", zh: "播放进度"))
            .accessibilityValue("\(labels.elapsed), \(labels.remaining)")
            .accessibilityAdjustableAction { direction in
                let current = snapshot.elapsed(at: Date()) ?? 0
                switch direction {
                case .increment: model.seek(to: min(current + Self.accessibilityStep, duration))
                case .decrement: model.seek(to: max(current - Self.accessibilityStep, 0))
                @unknown default: break
                }
            }
        }
    }

    private func bar(fraction: Double) -> some View {
        let isDragging = dragFraction != nil
        return GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.18))
                Capsule()
                    .fill(fillStyle)
                    .frame(width: width * min(max(fraction, 0), 1))
            }
            .frame(height: isDragging ? 6 : 4)
            .frame(maxHeight: .infinity)
            // The whole row's height takes the click, not only the thin bar.
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($dragFraction) { value, state, _ in
                        state = Self.fraction(of: value.location.x, in: width)
                    }
                    .onEnded { value in
                        if let fraction = Self.fraction(of: value.location.x, in: width) {
                            model.seek(to: fraction * duration)
                        }
                    }
            )
            .animation(.snappy(duration: 0.15), value: isDragging)
        }
        .frame(height: 14)
    }

    private var fillStyle: Color {
        guard NotchAppearance.shared.isLightAndColorEnabled, let palette = model.palette else {
            return NotchTheme.primaryText
        }
        return palette.primary.color
    }

    private static func fraction(of x: CGFloat, in width: CGFloat) -> Double? {
        guard width > 0 else { return nil }
        return min(max(Double(x / width), 0), 1)
    }
}

/// The time labels beside the progress bar.
enum PlaybackTime {
    /// "m:ss", or "h:mm:ss" from an hour on, of whole seconds.
    static func format(_ seconds: Int) -> String {
        let seconds = max(seconds, 0)
        let hours = seconds / 3600
        let minutes = seconds % 3600 / 60
        let rest = seconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, rest)
        }
        return String(format: "%d:%02d", minutes, rest)
    }

    /// The elapsed whole seconds, and what is left of the length (rounded to whole
    /// seconds) after them as "-m:ss". Both come from the same whole seconds, so
    /// they always add up to the length: rounding each on its own would show the
    /// two a second apart, or overlapping, for part of every second.
    static func labels(elapsed: TimeInterval, duration: TimeInterval) -> (elapsed: String, remaining: String) {
        // Kept far inside `Int`'s range, which converting a larger value would trap on.
        let limit: TimeInterval = 1_000_000_000
        let total = duration.isFinite ? Int(min(max(duration, 0), limit).rounded()) : 0
        let whole = elapsed.isFinite ? Int(min(max(elapsed, 0), limit).rounded(.down)) : 0
        let done = min(whole, total)
        return (format(done), "-" + format(total - done))
    }
}

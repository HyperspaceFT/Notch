import NotchKit
import NotchUI
import SwiftUI

/// Width of each Now Playing wing, narrower than the standard one: the cover and
/// the wave each sit centered in it, as far from the notch as from the island's
/// edge, which also keeps them clear of the rounded bottom corners.
let nowPlayingWingWidth: CGFloat = 38

/// While the pointer rests on the island, it grows (`NotchTheme.hoverGrowth`) and
/// the cover and the wave move out with it, by half the growth, so each stays
/// centered in its grown wing. `outward` is -1 on the left, 1 on the right.
private func hoverShift(isHovered: Bool, outward: CGFloat) -> CGSize {
    guard isHovered else { return .zero }
    return CGSize(width: NotchTheme.hoverGrowth.width / 2 * outward, height: NotchTheme.hoverGrowth.height / 2)
}

/// Left wing: the cover, like a record sleeve. It glows in its own colors while
/// playing, sinks back while paused, and flips over when the track changes.
struct NowPlayingSleeve: View {
    let model: NowPlayingModel
    @Environment(\.notchIsHovered) private var isIslandHovered

    private static let maximumSide: CGFloat = 24
    private static let cornerRadius: CGFloat = 6

    var body: some View {
        GeometryReader { proxy in
            let side = max(min(Self.maximumSide, proxy.size.height - 10), 0)
            ZStack {
                // One view per cover: a new track inserts a new one and
                // removes the old, and the transition flips between them.
                sleeve(side: side)
                    .id(model.coverKey)
                    .transition(.flip)
            }
            .animation(.smooth(duration: 0.24), value: model.coverKey)
            .offset(hoverShift(isHovered: isIslandHovered, outward: -1))
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private func sleeve(side: CGFloat) -> some View {
        let isPlaying = model.isPlaying
        let shape = RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
        return ZStack {
            if NotchAppearance.shared.isLightAndColorEnabled, let cover = model.cover {
                Image(nsImage: cover)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: side, height: side)
                    .clipShape(shape)
                    .scaleEffect(1.25)
                    .blur(radius: 6)
                    .opacity(isPlaying ? 0.5 : 0)
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
                            .font(.system(size: side * 0.5, weight: .semibold))
                            .foregroundStyle(NotchTheme.primaryText)
                    }
                }
            }
            .frame(width: side, height: side)
            .clipShape(shape)
            .scaleEffect(isPlaying ? 1 : 0.88)
            .saturation(isPlaying ? 1 : 0.4)
            .opacity(isPlaying ? 1 : 0.7)
        }
        .animation(.smooth(duration: 0.35), value: isPlaying)
        .accessibilityLabel(model.snapshot.map { [$0.title, $0.artist].compactMap { $0 }.joined(separator: " – ") } ?? "")
    }
}

private struct FlipModifier: ViewModifier {
    let angle: Double

    func body(content: Content) -> some View {
        content
            .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
            .opacity(abs(angle) >= 90 ? 0 : 1)
    }
}

extension AnyTransition {
    /// The old cover turns away to its edge, then the new one turns in from the other side.
    static var flip: AnyTransition {
        .asymmetric(
            insertion: .modifier(active: FlipModifier(angle: -90), identity: FlipModifier(angle: 0))
                .animation(.smooth(duration: 0.24).delay(0.22)),
            removal: .modifier(active: FlipModifier(angle: 90), identity: FlipModifier(angle: 0))
        )
    }
}

/// Right wing: three thin strands of a wave, braided around one line and swinging
/// to the track's own made-up beat (see `PulseRhythm`), in the cover's colors.
/// Pausing calms them into a single flat line; hovering turns them into a play or
/// pause button, which they are.
struct NowPlayingPulse: View {
    let model: NowPlayingModel
    @Environment(\.notchIsHovered) private var isIslandHovered

    var body: some View {
        Button {
            model.togglePlayPause()
        } label: {
            WaveIcon(model: model)
        }
        .buttonStyle(PulseButtonStyle())
        .offset(hoverShift(isHovered: isIslandHovered, outward: 1))
        .onHover { model.isPulseHovered = $0 }
        .accessibilityLabel(model.isPlaying ? localized(en: "Pause", zh: "暂停") : localized(en: "Play", zh: "播放"))
    }
}

private struct WaveIcon: View {
    let model: NowPlayingModel

    static let width: CGFloat = 22
    static let height: CGFloat = 16

    var body: some View {
        let isPlaying = model.isPlaying
        let isHovered = model.isPulseHovered
        ZStack {
            WaveStrands(model: model)
                .blur(radius: isHovered ? 4 : 0)
                .opacity(isHovered ? 0 : 1)

            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(symbolStyle)
                .contentTransition(.symbolEffect(.replace))
                .scaleEffect(isHovered ? 1 : 0.6)
                .opacity(isHovered ? 1 : 0)
        }
        .frame(width: Self.width, height: Self.height)
        // The whole wave region takes the click, not only the strands themselves.
        .contentShape(Rectangle())
        .animation(.spring(duration: 0.6, bounce: 0.25), value: isPlaying)
        .animation(.smooth(duration: 0.2), value: isHovered)
    }

    private var symbolStyle: AnyShapeStyle {
        guard NotchAppearance.shared.isLightAndColorEnabled, let palette = model.palette else {
            return AnyShapeStyle(NotchTheme.primaryText)
        }
        return AnyShapeStyle(palette.primary.color)
    }
}

/// The three strands themselves, filling the frame they are given; the wing's
/// wave and the tab's small copy. They swing while playing and lie flat while
/// paused; the caller animates the change. `isActive` false stops the clock
/// too, for a copy that is not on screen.
struct WaveStrands: View {
    let model: NowPlayingModel
    var isActive = true

    var body: some View {
        let isPlaying = model.isPlaying
        let rhythm = model.rhythm
        let styles = strandStyles
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !isPlaying || !isActive)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let levels = rhythm.levels(at: time, count: WaveStrand.voices.count)
            ZStack {
                ForEach(WaveStrand.voices.indices, id: \.self) { index in
                    WaveStrand(
                        voice: WaveStrand.voices[index],
                        level: levels[index],
                        time: time,
                        tempo: rhythm.tempo,
                        amplitude: isPlaying ? 1 : 0
                    )
                    .stroke(styles[index], style: StrokeStyle(lineWidth: WaveStrand.lineWidth, lineCap: .round))
                    // Where strands cross they add up and glow, as light does on black.
                    .blendMode(.plusLighter)
                }
            }
        }
    }

    /// Front to back: the cover's main color, its second color, then a soft white;
    /// without Light and Color, white at falling strengths.
    private var strandStyles: [Color] {
        guard NotchAppearance.shared.isLightAndColorEnabled, let palette = model.palette else {
            return [NotchTheme.primaryText, NotchTheme.primaryText.opacity(0.55), NotchTheme.primaryText.opacity(0.3)]
        }
        return [palette.primary.color, palette.secondary.color, NotchTheme.primaryText.opacity(0.45)]
    }
}

/// One strand: a sine wave pinned to the middle line at both ends (its swing
/// tapers to nothing there), travelling sideways as time passes. `level` is how
/// hard the beat pushes it right now; `amplitude` animates it between swinging (1)
/// and lying flat (0), so a pause eases all strands into one line.
private struct WaveStrand: Shape {
    struct Voice {
        /// Whole waves across the width.
        var cycles: Double
        /// Radians per beat the wave travels; negative runs leftward.
        var speed: Double
        /// Share of the full height this strand may swing.
        var reach: Double
        var phase: Double
    }

    static let voices = [
        Voice(cycles: 1, speed: 1.6, reach: 1, phase: 0),
        Voice(cycles: 1.5, speed: -1.1, reach: 0.8, phase: 2.1),
        Voice(cycles: 0.75, speed: 2.3, reach: 0.6, phase: 4.2),
    ]
    static let lineWidth: CGFloat = 1.6
    private static let samples = 28

    var voice: Voice
    var level: Double
    var time: TimeInterval
    var tempo: Double
    var amplitude: Double

    var animatableData: Double {
        get { amplitude }
        set { amplitude = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let swing = (rect.height - Self.lineWidth) / 2 * voice.reach * level * amplitude
        let phase = voice.phase + voice.speed * time * tempo / 60
        var path = Path()
        for sample in 0...Self.samples {
            let u = Double(sample) / Double(Self.samples)
            let taper = pow(sin(.pi * u), 2)
            let y = rect.midY + swing * taper * sin(2 * .pi * voice.cycles * u + phase)
            let point = CGPoint(x: rect.minX + rect.width * u, y: y)
            if sample == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        return path
    }
}

/// A small press-in, so the click is felt.
private struct PulseButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.85 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

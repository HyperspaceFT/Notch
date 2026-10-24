import NotchKit
import NotchUI
import SwiftUI

/// Width of each Now Playing wing, narrower than the standard one: the cover and
/// the wave each sit centered in it, as far from the notch as from the island's
/// edge, which also keeps them clear of the rounded bottom corners.
let nowPlayingWingWidth: CGFloat = 38

/// Ids of the views that fly between the wings and the tab (`notchMorphSlot`,
/// `notchMorphHero`).
enum NowPlayingMorph {
    static let cover = "now-playing.cover"
    static let wave = "now-playing.wave"
}

/// While the pointer rests on the island, it grows (`NotchTheme.hoverGrowth`) and
/// the cover and the wave move out with it, by half the growth, so each stays
/// centered in its grown wing. `outward` is -1 on the left, 1 on the right.
private func hoverShift(isHovered: Bool, outward: CGFloat) -> CGSize {
    guard isHovered else { return .zero }
    return CGSize(width: NotchTheme.hoverGrowth.width / 2 * outward, height: NotchTheme.hoverGrowth.height / 2)
}

private extension View {
    /// Moves this view, centered in its wing, by `hoverShift`. Padding rather
    /// than `offset`: the morph slot inside must move in layout for its hero to
    /// follow it.
    func hoverShifted(isHovered: Bool, outward: CGFloat) -> some View {
        let shift = hoverShift(isHovered: isHovered, outward: outward)
        return padding(.leading, max(shift.width, 0) * 2)
            .padding(.trailing, max(-shift.width, 0) * 2)
            .padding(.top, shift.height * 2)
    }
}

/// Left wing: the cover, like a record sleeve. It glows in its own colors while
/// playing, sinks back while paused, and flips over when the track changes. A
/// click opens the tab, and the cover flies to its place there and back again
/// (`NowPlayingCoverHero`); the wing only holds its place.
struct NowPlayingSleeve: View {
    let model: NowPlayingModel
    @Environment(\.notchIsHovered) private var isIslandHovered

    private static let maximumSide: CGFloat = 24

    var body: some View {
        GeometryReader { proxy in
            let side = max(min(Self.maximumSide, proxy.size.height - 10), 0)
            Color.clear
                .frame(width: side, height: side)
                .notchMorphSlot(NowPlayingMorph.cover, role: .wing)
                .overlay {
                    NowPlayingCoverHero(model: model)
                        .notchMorphHero(NowPlayingMorph.cover)
                }
                .hoverShifted(isHovered: isIslandHovered, outward: -1)
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}

/// The cover that flies between the wing and the tab, at whatever size its
/// place has. A click opens the tab while the island is closed, and brings the
/// playing app to the front once it is open, as the tab's own cover does.
private struct NowPlayingCoverHero: View {
    let model: NowPlayingModel
    @Environment(\.notchActivityMorph) private var morph

    var body: some View {
        let isExpanded = morph?.state.isExpanded ?? false
        Button {
            if isExpanded {
                model.showPlayingApp()
            } else {
                model.openDetail()
            }
        } label: {
            GeometryReader { proxy in
                NowPlayingArtwork(model: model, side: min(proxy.size.width, proxy.size.height))
                    .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isExpanded ? model.coverAccessibilityLabel : trackLabel)
    }

    private var trackLabel: String {
        model.snapshot.map { [$0.title, $0.artist].compactMap { $0 }.joined(separator: " – ") } ?? ""
    }
}

/// The cover, square at `side`: it glows in its own colors while playing, sinks
/// back while paused, and flips over when the track changes. Its corners, glow,
/// and pause pose scale from the wing's small cover to the tab's large one, so
/// the cover keeps its look at every size it passes through in flight.
struct NowPlayingArtwork: View {
    let model: NowPlayingModel
    let side: CGFloat

    /// The wing's cover.
    private static let smallSide: CGFloat = 22
    /// About the tab's cover; larger sizes look like it.
    private static let largeSide: CGFloat = 130

    var body: some View {
        ZStack {
            // One view per cover: a new track inserts a new one and
            // removes the old, and the transition flips between them.
            cover
                .id(model.coverKey)
                .transition(.flip)
        }
        .animation(.smooth(duration: 0.24), value: model.coverKey)
    }

    /// `small` at the wing's size, `large` at the tab's, and in between.
    private func scaled(_ small: CGFloat, _ large: CGFloat) -> CGFloat {
        let progress = min(max((side - Self.smallSide) / (Self.largeSide - Self.smallSide), 0), 1)
        return small + (large - small) * progress
    }

    private var cover: some View {
        let isPlaying = model.isPlaying
        let shape = RoundedRectangle(cornerRadius: scaled(6, 12), style: .continuous)
        return ZStack {
            if NotchAppearance.shared.isLightAndColorEnabled, let cover = model.cover {
                Image(nsImage: cover)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: side, height: side)
                    .clipShape(shape)
                    .scaleEffect(scaled(1.25, 1.04))
                    .blur(radius: scaled(6, 16))
                    .opacity(isPlaying ? scaled(0.5, 0.55) : 0)
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
                            .font(.system(size: side * scaled(0.5, 0.36), weight: .semibold))
                            .foregroundStyle(NotchTheme.primaryText)
                    }
                }
            }
            .frame(width: side, height: side)
            .clipShape(shape)
            .scaleEffect(isPlaying ? 1 : scaled(0.88, 0.92))
            .saturation(isPlaying ? 1 : 0.4)
            .opacity(isPlaying ? 1 : scaled(0.7, 0.75))
        }
        .animation(.smooth(duration: 0.35), value: isPlaying)
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
/// pause button, which they are. The wave flies into the tab with the cover
/// (`NowPlayingWaveHero`); the wing only holds its place.
struct NowPlayingPulse: View {
    let model: NowPlayingModel
    @Environment(\.notchIsHovered) private var isIslandHovered

    var body: some View {
        Color.clear
            .frame(width: WaveIcon.width, height: WaveIcon.height)
            .notchMorphSlot(NowPlayingMorph.wave, role: .wing)
            .overlay {
                NowPlayingWaveHero(model: model)
                    .notchMorphHero(NowPlayingMorph.wave)
            }
            .hoverShifted(isHovered: isIslandHovered, outward: 1)
    }
}

/// The wave that flies between the wing and the tab: a play or pause button while
/// the island is closed, only the strands once it is open (the tab has its own
/// play button).
private struct NowPlayingWaveHero: View {
    let model: NowPlayingModel
    @Environment(\.notchActivityMorph) private var morph

    var body: some View {
        let isExpanded = morph?.state.isExpanded ?? false
        Button {
            model.togglePlayPause()
        } label: {
            WaveIcon(model: model, isButton: !isExpanded, isActive: morph?.state.showsHeroes ?? true)
        }
        .buttonStyle(PulseButtonStyle())
        .onHover { model.isPulseHovered = $0 }
        .allowsHitTesting(!isExpanded)
        .accessibilityHidden(isExpanded)
        .accessibilityLabel(model.isPlaying ? localized(en: "Pause", zh: "暂停") : localized(en: "Play", zh: "播放"))
        // Opening the island takes the pointer off the wave without an exit
        // event reaching it, which would leave the glyph up on the way back.
        .onChange(of: isExpanded) {
            if isExpanded {
                model.isPulseHovered = false
            }
        }
        // Nor does one reach it when the wings leave under the pointer (another
        // activity takes their place).
        .onDisappear {
            model.isPulseHovered = false
        }
    }
}

private struct WaveIcon: View {
    let model: NowPlayingModel
    /// Whether the wave is a button, which hovering turns into its glyph.
    let isButton: Bool
    let isActive: Bool

    /// The wing's wave.
    static let width: CGFloat = 22
    static let height: CGFloat = 16

    var body: some View {
        let isPlaying = model.isPlaying
        let isHovered = model.isPulseHovered && isButton
        ZStack {
            WaveStrands(model: model, isActive: isActive)
                .blur(radius: isHovered ? 4 : 0)
                .opacity(isHovered ? 0 : 1)

            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(symbolStyle)
                .contentTransition(.symbolEffect(.replace))
                .scaleEffect(isHovered ? 1 : 0.6)
                .opacity(isHovered ? 1 : 0)
        }
        // Whatever frame the wave flies through.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

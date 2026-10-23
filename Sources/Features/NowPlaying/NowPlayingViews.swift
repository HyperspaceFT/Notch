import NotchKit
import NotchUI
import SwiftUI

/// Room between the wings' content and the island's outer edge, so the rounded
/// bottom corners never clip it (also while the hover ring has not grown yet).
private let outerInset: CGFloat = 10

/// Left wing: the cover, like a record sleeve. It glows in its own colors while
/// playing, sinks back while paused, and flips over when the track changes.
struct NowPlayingSleeve: View {
    let model: NowPlayingModel

    private static let maximumSide: CGFloat = 24
    private static let cornerRadius: CGFloat = 6

    var body: some View {
        GeometryReader { proxy in
            let side = max(min(Self.maximumSide, proxy.size.height - 10), 0)
            HStack(spacing: 0) {
                ZStack {
                    // One view per cover: a new track inserts a new one and
                    // removes the old, and the transition flips between them.
                    sleeve(side: side)
                        .id(model.coverKey)
                        .transition(.flip)
                }
                .animation(.smooth(duration: 0.24), value: model.coverKey)
                Spacer(minLength: 0)
            }
            .padding(.leading, outerInset)
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

private extension AnyTransition {
    /// The old cover turns away to its edge, then the new one turns in from the other side.
    static var flip: AnyTransition {
        .asymmetric(
            insertion: .modifier(active: FlipModifier(angle: -90), identity: FlipModifier(angle: 0))
                .animation(.smooth(duration: 0.24).delay(0.22)),
            removal: .modifier(active: FlipModifier(angle: 90), identity: FlipModifier(angle: 0))
        )
    }
}

/// Right wing: five bars dancing to the track's own made-up rhythm (see
/// `PulseRhythm`), in the cover's colors. Pausing settles them into a row of
/// dots; hovering turns them into a play or pause button, which they are.
struct NowPlayingPulse: View {
    let model: NowPlayingModel

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            Button {
                model.togglePlayPause()
            } label: {
                PulseIcon(model: model)
            }
            .buttonStyle(PulseButtonStyle())
            .onHover { model.isPulseHovered = $0 }
            .accessibilityLabel(model.isPlaying ? localized(en: "Pause", zh: "暂停") : localized(en: "Play", zh: "播放"))
        }
        .padding(.trailing, outerInset)
    }
}

private struct PulseIcon: View {
    let model: NowPlayingModel

    var body: some View {
        let isPlaying = model.isPlaying
        let isHovered = model.isPulseHovered
        let rhythm = model.rhythm
        ZStack {
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !isPlaying)) { timeline in
                PulseBars(
                    levels: rhythm.levels(at: timeline.date.timeIntervalSinceReferenceDate, count: PulseBars.barCount),
                    amplitude: isPlaying ? 1 : 0
                )
                .fill(barStyle)
            }
            .blur(radius: isHovered ? 4 : 0)
            .opacity(isHovered ? 0 : 1)

            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(symbolStyle)
                .contentTransition(.symbolEffect(.replace))
                .scaleEffect(isHovered ? 1 : 0.6)
                .opacity(isHovered ? 1 : 0)
        }
        .frame(width: PulseBars.width, height: PulseBars.maximumHeight)
        // The whole bars region takes the click, not only the bars themselves.
        .contentShape(Rectangle())
        .animation(.spring(duration: 0.5, bounce: 0.3), value: isPlaying)
        .animation(.smooth(duration: 0.2), value: isHovered)
    }

    private var barStyle: AnyShapeStyle {
        guard NotchAppearance.shared.isLightAndColorEnabled, let palette = model.palette else {
            return AnyShapeStyle(NotchTheme.primaryText)
        }
        return AnyShapeStyle(LinearGradient(
            colors: [palette.primary.color, palette.secondary.color],
            startPoint: .top,
            endPoint: .bottom
        ))
    }

    private var symbolStyle: AnyShapeStyle {
        guard NotchAppearance.shared.isLightAndColorEnabled, let palette = model.palette else {
            return AnyShapeStyle(NotchTheme.primaryText)
        }
        return AnyShapeStyle(palette.primary.color)
    }
}

/// All bars in one shape, so `amplitude` animates them together: 1 lets them
/// follow `levels`, 0 settles them into dots as tall as they are wide.
private struct PulseBars: Shape {
    var levels: [Double]
    var amplitude: Double

    static let barCount = 5
    static let barWidth: CGFloat = 3
    static let gap: CGFloat = 2.5
    static let minimumHeight: CGFloat = 4
    static let maximumHeight: CGFloat = 16
    static var width: CGFloat {
        CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * gap
    }

    var animatableData: Double {
        get { amplitude }
        set { amplitude = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for (index, level) in levels.enumerated() {
            let playing = Self.minimumHeight + CGFloat(level) * (Self.maximumHeight - Self.minimumHeight)
            let height = Self.barWidth + (playing - Self.barWidth) * CGFloat(amplitude)
            let x = rect.minX + CGFloat(index) * (Self.barWidth + Self.gap)
            path.addRoundedRect(
                in: CGRect(x: x, y: rect.midY - height / 2, width: Self.barWidth, height: height),
                cornerSize: CGSize(width: Self.barWidth / 2, height: Self.barWidth / 2)
            )
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

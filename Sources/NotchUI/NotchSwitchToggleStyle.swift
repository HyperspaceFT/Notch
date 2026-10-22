import SwiftUI

/// A small switch that stays readable inside the island and behaves like the
/// macOS 26 one. The system switch draws its "on" state in gray while the window
/// is not key, which the island panel never is, so on and off look nearly alike
/// there.
///
/// Like the system switch, the knob is a white pill at rest and turns into a
/// clear lens over the track while held; it can be dragged, and the switch then
/// takes the side the lens is released on. The lens is drawn by hand because
/// `glassEffect` renders opaque in the island panel, hiding the track it should
/// magnify.
public struct NotchSwitchToggleStyle: ToggleStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        NotchSwitch(isOn: configuration.$isOn, label: configuration.label)
    }
}

extension ToggleStyle where Self == NotchSwitchToggleStyle {
    public static var notchSwitch: NotchSwitchToggleStyle { NotchSwitchToggleStyle() }
}

private struct NotchSwitch: View {
    static let trackSize = CGSize(width: 34, height: 18)
    static let knobSize = CGSize(width: 19, height: 14)
    /// Taller than the track, so the lens bulges past it like the system one.
    static let lensSize = CGSize(width: 23, height: 22)
    /// How much the lens enlarges the track behind it. Kept low so the enlarged
    /// track stays shorter than the lens and the island shows through above and below it.
    static let magnification: CGFloat = 1.1
    /// Travel below which a press counts as a click, which toggles.
    static let clickTolerance: CGFloat = 3

    @Binding var isOn: Bool
    let label: ToggleStyleConfiguration.Label
    /// Horizontal drag translation while the knob is held; `nil` otherwise.
    @GestureState private var drag: CGFloat?

    var body: some View {
        let isHeld = drag != nil
        HStack(spacing: 6) {
            label
                .foregroundStyle(isOn ? NotchTheme.primaryText : NotchTheme.secondaryText)
                .contentShape(.rect)
                .onTapGesture { isOn.toggle() }
            track(isHeld: isHeld)
        }
        .animation(.snappy(duration: 0.25), value: isOn)
        .animation(.snappy(duration: 0.2), value: isHeld)
        .accessibilityRepresentation {
            Toggle(isOn: $isOn) { label }
        }
    }

    private var trackColor: Color {
        isOn ? .accentColor : Color(white: 0.32)
    }

    private func track(isHeld: Bool) -> some View {
        let offset = knobOffset(isHeld: isHeld, translation: drag ?? 0)
        return Capsule()
            .fill(trackColor)
            .frame(width: Self.trackSize.width, height: Self.trackSize.height)
            .overlay {
                knob(isHeld: isHeld, offset: offset)
            }
            .contentShape(.capsule)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($drag) { value, drag, _ in
                        drag = value.translation.width
                    }
                    .onEnded { value in
                        let translation = value.translation.width
                        if abs(translation) < Self.clickTolerance {
                            isOn.toggle()
                        } else {
                            // The side the lens is let go on wins, so a drag that
                            // comes back leaves the switch as it was.
                            isOn = knobOffset(isHeld: true, translation: translation) > 0
                        }
                    }
            )
    }

    /// Knob center relative to the track center, clamped to the track.
    private func knobOffset(isHeld: Bool, translation: CGFloat) -> CGFloat {
        let width = isHeld ? Self.lensSize.width : Self.knobSize.width
        // At rest the knob keeps a 2 pt inset from the track's ends; the lens may touch them.
        let travel = (Self.trackSize.width - width) / 2 - (isHeld ? 0 : 2)
        return min(max((isOn ? travel : -travel) + translation, -travel), travel)
    }

    /// One view throughout, so the press morphs the pill into the lens.
    private func knob(isHeld: Bool, offset: CGFloat) -> some View {
        let size = isHeld ? Self.lensSize : Self.knobSize
        let lens = isHeld ? 1.0 : 0.0
        return ZStack {
            // The track as seen through the lens: enlarged about the lens center.
            Capsule()
                .fill(trackColor)
                .frame(
                    width: Self.trackSize.width * Self.magnification,
                    height: Self.trackSize.height * Self.magnification
                )
                .offset(x: -offset * Self.magnification)
                .opacity(lens)
            // Sheen across the top of the glass.
            Capsule()
                .fill(LinearGradient(
                    colors: [.white.opacity(0.32), .white.opacity(0.04)],
                    startPoint: .top,
                    endPoint: .bottom
                ))
                .opacity(lens)
            // Bright rim, strongest where the light comes from (top left).
            Capsule()
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.95), .white.opacity(0.2), .white.opacity(0.55)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
                .opacity(lens)
            Capsule()
                .fill(.white)
                .opacity(1 - lens)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(.capsule)
        .shadow(color: .black.opacity(isHeld ? 0.35 : 0.2), radius: isHeld ? 3 : 1, y: 1)
        .offset(x: offset)
    }
}

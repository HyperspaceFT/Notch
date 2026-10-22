import SwiftUI

/// A small switch that stays readable inside the island and behaves like the
/// macOS 26 one. The system switch draws its "on" state in gray while the window
/// is not key, which the island panel never is, so on and off look nearly alike
/// there. Like the system switch, the knob is a white pill at rest and turns into
/// a clear Liquid Glass lens over the track while pressed.
public struct NotchSwitchToggleStyle: ToggleStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            configuration.label
        }
        .buttonStyle(SwitchButtonStyle(isOn: configuration.isOn))
    }
}

extension ToggleStyle where Self == NotchSwitchToggleStyle {
    public static var notchSwitch: NotchSwitchToggleStyle { NotchSwitchToggleStyle() }
}

/// Draws the label and the switch. A button style, because the knob reacts to the press.
private struct SwitchButtonStyle: ButtonStyle {
    static let trackSize = CGSize(width: 28, height: 16)
    static let knobSize = CGSize(width: 16, height: 12)
    /// Larger than the track's height, so the lens bulges past it like the system one.
    static let pressedKnobSize = CGSize(width: 22, height: 18)

    let isOn: Bool

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let knob = pressed ? Self.pressedKnobSize : Self.knobSize
        // At rest the knob keeps a 2 pt inset from the track's ends; the lens may touch them.
        let travel = (Self.trackSize.width - knob.width) / 2 - (pressed ? 0 : 2)

        HStack(spacing: 6) {
            configuration.label
                .foregroundStyle(isOn ? NotchTheme.primaryText : NotchTheme.secondaryText)
            Capsule()
                .fill(isOn ? Color.accentColor : Color.white.opacity(0.2))
                .frame(width: Self.trackSize.width, height: Self.trackSize.height)
                .overlay {
                    // One view throughout, so the press morphs it: the white fill
                    // fades to reveal the glass underneath while the pill grows.
                    Capsule()
                        .fill(.white.opacity(pressed ? 0 : 1))
                        .frame(width: knob.width, height: knob.height)
                        .glassEffect(.clear, in: .capsule)
                        .offset(x: isOn ? travel : -travel)
                }
        }
        .contentShape(.rect)
        .animation(.snappy(duration: 0.25), value: isOn)
        .animation(.snappy(duration: 0.2), value: pressed)
    }
}

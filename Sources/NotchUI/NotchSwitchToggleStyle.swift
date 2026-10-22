import SwiftUI

/// A small Liquid Glass switch that stays readable inside the island. The system
/// switch draws its "on" state in gray while the window is not key, which the
/// island panel never is, so on and off look nearly alike there. Here the glass
/// track takes the accent color when on.
public struct NotchSwitchToggleStyle: ToggleStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 6) {
                configuration.label
                    .foregroundStyle(configuration.isOn ? NotchTheme.primaryText : NotchTheme.secondaryText)
                Circle()
                    .fill(.white)
                    .frame(width: 11, height: 11)
                    .offset(x: configuration.isOn ? 5.5 : -5.5)
                    .frame(width: 26, height: 15)
                    .glassEffect(
                        configuration.isOn ? .regular.tint(.accentColor).interactive() : .regular.interactive(),
                        in: .capsule
                    )
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.2), value: configuration.isOn)
    }
}

extension ToggleStyle where Self == NotchSwitchToggleStyle {
    public static var notchSwitch: NotchSwitchToggleStyle { NotchSwitchToggleStyle() }
}

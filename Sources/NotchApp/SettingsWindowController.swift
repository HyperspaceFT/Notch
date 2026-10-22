import AppKit
import NotchKit
import Observation
import SwiftUI

/// The settings window: a standalone window with one toolbar tab per pane
/// (just General for now). Built on first use and kept for later openings.
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private var generalItem: NSTabViewItem?
    private let launchAtLogin = LaunchAtLogin()

    func show() {
        launchAtLogin.refresh()
        let window = window ?? makeWindow()
        // An accessory app is never active on its own; without this the window
        // would open behind the frontmost app.
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let general = NSHostingController(rootView: GeneralSettingsView(
            localization: .shared,
            launchAtLogin: launchAtLogin
        ))
        // The window takes the pane's ideal size.
        general.sizingOptions = [.preferredContentSize]
        let generalItem = NSTabViewItem(viewController: general)
        generalItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        self.generalItem = generalItem

        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        tabs.addTabViewItem(generalItem)

        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window

        updateTitles()
        return window
    }

    /// Sets the AppKit labels for the interface language, again on every switch.
    private func updateTitles() {
        withObservationTracking {
            let title = localized(en: "General", zh: "通用")
            generalItem?.label = title
            // The toolbar tab style shows the selected pane's title as the window title.
            generalItem?.viewController?.title = title
            window?.title = title
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.updateTitles()
            }
        }
    }
}

private struct GeneralSettingsView: View {
    @Bindable var localization: Localization
    @Bindable var launchAtLogin: LaunchAtLogin

    var body: some View {
        Form {
            Toggle(isOn: $launchAtLogin.isEnabled) {
                Text(localized(en: "Open at Login", zh: "登录时打开"))
                if let note = launchAtLoginNote {
                    Text(note)
                }
            }
            .toggleStyle(.switch)
            Picker(localized(en: "Language", zh: "语言"), selection: $localization.override) {
                Text(localized(en: "System", zh: "跟随系统"))
                    .tag(AppLanguage?.none)
                Divider()
                ForEach(AppLanguage.allCases, id: \.self) { language in
                    Text(language.nativeName)
                        .tag(AppLanguage?.some(language))
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        // Coming back from System Settings, where the login item may have changed.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            launchAtLogin.refresh()
        }
    }

    /// Shown under the switch: why turning it on or off failed, or what is left to do.
    private var launchAtLoginNote: String? {
        if let error = launchAtLogin.errorMessage { return error }
        if launchAtLogin.status == .requiresApproval {
            return localized(
                en: "Allow Notch in System Settings → General → Login Items.",
                zh: "请在「系统设置 → 通用 → 登录项」中允许 Notch。"
            )
        }
        return nil
    }
}

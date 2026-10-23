import AppKit
import HomeFeature
import NotchKit
import Observation
import SwiftUI
import SystemHUDFeature

/// The settings window: a standalone window with one toolbar tab per pane
/// (General, Island, and Home). Built on first use and kept for later openings.
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private var tabs: NSTabViewController?
    /// Each pane's tab and its title in the interface language.
    private var panes: [(item: NSTabViewItem, title: @MainActor () -> String)] = []
    private let launchAtLogin = LaunchAtLogin()

    func show() {
        launchAtLogin.refresh()
        SystemHUDSettings.shared.refreshAccessibilityAccess()
        let window = window ?? makeWindow()
        // An accessory app is never active on its own; without this the window
        // would open behind the frontmost app.
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        addPane(
            GeneralSettingsView(localization: .shared, launchAtLogin: launchAtLogin),
            symbol: "gearshape"
        ) { localized(en: "General", zh: "通用") }
        addPane(IslandSettingsView(systemHUD: .shared), symbol: "capsule") {
            localized(en: "Island", zh: "灵动岛")
        }
        addPane(HomeSettingsView(settings: .shared), symbol: "house") {
            localized(en: "Home", zh: "主页")
        }

        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        for pane in panes {
            tabs.addTabViewItem(pane.item)
        }
        self.tabs = tabs

        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window

        updateTitles()
        return window
    }

    private func addPane<Content: View>(
        _ view: Content,
        symbol: String,
        title: @escaping @MainActor () -> String
    ) {
        let controller = NSHostingController(rootView: view)
        // The window takes the selected pane's ideal size.
        controller.sizingOptions = [.preferredContentSize]
        let item = NSTabViewItem(viewController: controller)
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        panes.append((item, title))
    }

    /// Sets the AppKit labels for the interface language, again on every switch.
    private func updateTitles() {
        withObservationTracking {
            for pane in panes {
                let title = pane.title()
                pane.item.label = title
                // The toolbar tab style shows the selected pane's title as the window title.
                pane.item.viewController?.title = title
            }
            if let tabs, tabs.tabViewItems.indices.contains(tabs.selectedTabViewItemIndex) {
                window?.title = tabs.tabViewItems[tabs.selectedTabViewItemIndex].label
            }
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

/// What the island shows: for now, whether it replaces the system volume and brightness HUD.
private struct IslandSettingsView: View {
    @Bindable var systemHUD: SystemHUDSettings

    var body: some View {
        Form {
            Toggle(isOn: $systemHUD.isEnabled) {
                Text(localized(en: "Replace Volume and Brightness HUD", zh: "替换系统音量和亮度提示"))
                if needsAccessibilityAccess {
                    Text(localized(
                        en: "Allow Notch in System Settings → Privacy & Security → Accessibility.",
                        zh: "请在「系统设置 → 隐私与安全性 → 辅助功能」中允许 Notch。"
                    ))
                }
            }
            .toggleStyle(.switch)
            if needsAccessibilityAccess {
                Button(localized(en: "Open Accessibility Settings…", zh: "打开辅助功能设置…")) {
                    systemHUD.requestAccessibilityAccess()
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        // Coming back from System Settings, where Accessibility access may have changed.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            systemHUD.refreshAccessibilityAccess()
        }
    }

    /// The HUD is on but cannot intercept the keys until the user grants access.
    private var needsAccessibilityAccess: Bool {
        systemHUD.isEnabled && !systemHUD.hasAccessibilityAccess
    }
}

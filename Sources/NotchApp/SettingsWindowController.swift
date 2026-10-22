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

    func show() {
        let window = window ?? makeWindow()
        // An accessory app is never active on its own; without this the window
        // would open behind the frontmost app.
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let general = NSHostingController(rootView: GeneralSettingsView(localization: .shared))
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

    var body: some View {
        Form {
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
    }
}

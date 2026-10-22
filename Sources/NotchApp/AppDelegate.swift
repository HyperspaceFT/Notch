import AppKit
import NotchShell

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let shell = NotchShellController()
    private let settings = SettingsWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        shell.onOpenSettings = { [settings] in settings.show() }
        shell.start(features: FeatureCatalog.makeFeatures())
    }

    func applicationWillTerminate(_ notification: Notification) {
        shell.stop()
    }
}

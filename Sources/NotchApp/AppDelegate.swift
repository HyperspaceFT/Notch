import AppKit
import NotchShell

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let shell = NotchShellController()
    private let settings = SettingsWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        shell.onOpenSettings = { [settings] in settings.show() }
        let features = FeatureCatalog.makeFeatures()
        settings.debugSources = DebugSources(islandItems: { [shell] in shell.debugItems }, features: features)
        settings.onEndDebugPins = { [shell] in shell.endDebugPins() }
        shell.start(features: features)
    }

    func applicationWillTerminate(_ notification: Notification) {
        shell.stop()
    }
}

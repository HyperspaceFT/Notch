import AppKit
import NotchShell

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let shell = NotchShellController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        shell.start(features: FeatureCatalog.makeFeatures())
    }

    func applicationWillTerminate(_ notification: Notification) {
        shell.stop()
    }
}

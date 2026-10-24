import AppKit

// Accessory app: no Dock icon, no menu bar of its own (LSUIElement is also set in Info.plist).
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)

// `kill` and `pkill` (as `scripts/run.sh` uses) send SIGTERM, which by default ends
// the app on the spot: `applicationWillTerminate` never runs, so features are not
// stopped and Now Playing's adapter, a child perl process, outlives the app. Quit
// the normal way instead.
signal(SIGTERM, SIG_IGN)
let terminationSignal = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
terminationSignal.setEventHandler {
    MainActor.assumeIsolated {
        NSApp.terminate(nil)
    }
}
terminationSignal.resume()

app.run()

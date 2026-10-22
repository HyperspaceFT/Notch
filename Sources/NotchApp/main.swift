import AppKit

// Accessory app: no Dock icon, no menu bar of its own (LSUIElement is also set in Info.plist).
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()

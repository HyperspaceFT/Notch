import AppKit
import NotchKit
import SwiftUI
import UsageFeature

/// The sign-in windows of the Usage pane: one per provider, reused while open.
/// Closing one drops its web view (and with it the web content process) and
/// reads the provider's usage again with the new sign-in.
@MainActor
final class UsageSignInWindows {
    private var windows: [UsageProvider: NSWindow] = [:]
    private var delegates: [UsageProvider: UsageSignInWindowDelegate] = [:]

    func show(_ provider: UsageProvider) {
        let window = windows[provider] ?? makeWindow(for: provider)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    private func makeWindow(for provider: UsageProvider) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 720),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = localized(en: "Sign In to \(provider.displayName)", zh: "登录 \(provider.displayName)")
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: UsageSignInView(provider: provider) { [weak window] in
            window?.close()
        })
        window.setContentSize(NSSize(width: 520, height: 720))
        let delegate = UsageSignInWindowDelegate { [weak self] in
            self?.closed(provider)
        }
        window.delegate = delegate
        window.center()
        windows[provider] = window
        delegates[provider] = delegate
        return window
    }

    private func closed(_ provider: UsageProvider) {
        windows[provider]?.contentViewController = nil
        windows[provider] = nil
        delegates[provider] = nil
        UsageModel.shared.signInWindowClosed(provider)
    }
}

/// Tells the sign-in windows that one is closing.
@MainActor
private final class UsageSignInWindowDelegate: NSObject, NSWindowDelegate {
    private let onClose: () -> Void

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}

import AppKit
import SwiftUI

/// Borderless, transparent, non-activating window that hosts the island.
///
/// The panel has a fixed size and sits top-centered on the notch, overlapping
/// the menu bar. While the island is neither hovered nor expanded it ignores
/// mouse events so the menu bar underneath stays clickable.
final class NotchPanel: NSPanel {
    /// Three levels above the main menu so the island draws over the menu bar
    /// (and over the status-bar level used by menu bar extras) on every Space.
    static let islandLevel = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = Self.islandLevel
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        // Only take key status when a control (e.g. a future text field) needs it.
        becomesKeyOnlyIfNeeded = true
        acceptsMouseMovedEvents = true
        ignoresMouseEvents = true
    }

    // Lets future text fields receive keyboard input without activating the app.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // AppKit would otherwise push the frame below the menu bar.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

/// Hosting view for the panel. The app is never active, so without first-mouse
/// support the first click on a control would only make the panel key.
final class NotchHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

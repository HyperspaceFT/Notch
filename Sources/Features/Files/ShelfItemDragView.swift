import AppKit
import NotchKit
import SwiftUI

/// An AppKit overlay on a shelf item that drags the file out and shows its context
/// menu. It sits on top of the SwiftUI cell, so it receives both mouse buttons.
struct ShelfItemDragView: NSViewRepresentable {
    let item: ShelfItem
    let shelf: FileShelf

    func makeNSView(context: Context) -> ShelfItemDragNSView {
        let view = ShelfItemDragNSView()
        view.configure(item: item, shelf: shelf)
        return view
    }

    func updateNSView(_ view: ShelfItemDragNSView, context: Context) {
        view.configure(item: item, shelf: shelf)
    }
}

final class ShelfItemDragNSView: NSView {
    /// Side of the icon drawn at the top of the cell; the drag image uses the same rect.
    static let iconSize: CGFloat = 40
    /// How far the pointer must travel with the button down before a drag starts.
    private static let dragThreshold: CGFloat = 3

    private var item: ShelfItem?
    private weak var shelf: FileShelf?
    private var mouseDownEvent: NSEvent?

    override var isFlipped: Bool { true }

    func configure(item: ShelfItem, shelf: FileShelf) {
        self.item = item
        self.shelf = shelf
        toolTip = item.url.path(percentEncoded: false)
    }

    // The island panel is never key, so the first click must already count.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
    }

    override func mouseUp(with event: NSEvent) {
        mouseDownEvent = nil
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownEvent, let item, let shelf else { return }
        let dx = event.locationInWindow.x - start.locationInWindow.x
        let dy = event.locationInWindow.y - start.locationInWindow.y
        guard dx * dx + dy * dy > Self.dragThreshold * Self.dragThreshold else { return }
        mouseDownEvent = nil

        let path = item.url.path(percentEncoded: false)
        let draggingItem = NSDraggingItem(pasteboardWriter: item.url as NSURL)
        draggingItem.setDraggingFrame(
            NSRect(x: (bounds.width - Self.iconSize) / 2, y: 0, width: Self.iconSize, height: Self.iconSize),
            contents: NSWorkspace.shared.icon(forFile: path)
        )
        shelf.beginDrag(item.id)
        beginDraggingSession(with: [draggingItem], event: start, source: shelf.dragSource)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard item != nil else { return nil }
        let menu = NSMenu()
        for (title, action) in [
            (localized(en: "Copy", zh: "拷贝"), #selector(copyItem)),
            (localized(en: "Show in Finder", zh: "在访达中显示"), #selector(revealItem)),
            (localized(en: "Remove", zh: "移除"), #selector(removeItem)),
        ] {
            let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: "")
            menuItem.target = self
            menu.addItem(menuItem)
        }
        return menu
    }

    @objc private func copyItem() {
        guard let item else { return }
        shelf?.copy(item)
    }

    @objc private func revealItem() {
        guard let item else { return }
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    @objc private func removeItem() {
        guard let item else { return }
        shelf?.remove(item.id)
    }
}

import AppKit
import NotchKit
import SwiftUI

/// Frames of the shelf's cells in `ShelfRowView.coordinateSpace`, keyed by item.
struct ShelfCellFramesKey: PreferenceKey {
    static let defaultValue: [ShelfItem.ID: CGRect] = [:]

    static func reduce(value: inout [ShelfItem.ID: CGRect], nextValue: () -> [ShelfItem.ID: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

/// An AppKit overlay on the shelf's row that selects items, drags them out, and
/// shows their context menu. It covers the whole row, the empty space beside the
/// items included, so it receives both mouse buttons there and draws the
/// selection rectangle over the cells.
///
/// - A click selects an item alone; on empty space it clears the selection.
/// - A Command-click adds an item to the selection or takes it out.
/// - A Shift-click selects the items from the one last clicked to this one.
/// - Dragging with Shift or Command held draws a selection rectangle that adds
///   to the selection; dragging from empty space draws one that replaces it.
/// - Dragging an item drags it out, with the rest of the selection when it is selected.
/// - ⌘A selects every item once a click in the row has given it the keyboard.
struct ShelfRowView: NSViewRepresentable {
    static let coordinateSpace = "ShelfRow"

    let shelf: FileShelf
    let cellFrames: [ShelfItem.ID: CGRect]

    func makeNSView(context: Context) -> ShelfRowNSView {
        let view = ShelfRowNSView()
        view.configure(shelf: shelf, cellFrames: cellFrames)
        return view
    }

    func updateNSView(_ view: ShelfRowNSView, context: Context) {
        view.configure(shelf: shelf, cellFrames: cellFrames)
    }
}

final class ShelfRowNSView: NSView {
    /// Side of the icon drawn at the top of a cell; the drag image uses the same rect.
    static let iconSize: CGFloat = 40
    /// Room between a cell's edge and its content, where its selection highlight shows.
    static let cellPadding: CGFloat = 4
    /// How far the pointer must travel with the button down before a drag starts.
    private static let dragThreshold: CGFloat = 3

    /// What the left button pressed in `mouseDown` turns into.
    private enum Press {
        /// On an item without Shift or Command: dragging drags it out. When it was
        /// already selected the selection stays for the drag, and only a click
        /// without moving narrows it to this item (`selectsOnRelease`).
        case item(ShelfItem.ID, selectsOnRelease: Bool)
        /// With Shift or Command, or on empty space: dragging draws a selection
        /// rectangle whose items join `base`; a click without moving on `item`
        /// toggles it (Command) or selects the range up to it (Shift).
        case selection(base: Set<ShelfItem.ID>, item: ShelfItem.ID?, modifiers: NSEvent.ModifierFlags)
    }

    private weak var shelf: FileShelf?
    private var cellFrames: [ShelfItem.ID: CGRect] = [:]
    private var press: Press?
    private var mouseDownEvent: NSEvent?
    /// Where the press started, in this view's coordinates.
    private var pressOrigin: CGPoint = .zero
    /// The selection rectangle being drawn, in this view's coordinates.
    private var marquee: CGRect? {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { true }

    func configure(shelf: FileShelf, cellFrames: [ShelfItem.ID: CGRect]) {
        self.shelf = shelf
        guard cellFrames != self.cellFrames else { return }
        self.cellFrames = cellFrames
        removeAllToolTips()
        for frame in cellFrames.values {
            addToolTip(frame, owner: self, userData: nil)
        }
    }

    // The island panel is never key, so the first click must already count.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // ⌘A needs the keyboard: a click in the row makes the panel key and this
    // view its first responder. The panel gives the keyboard back when it collapses.
    override var acceptsFirstResponder: Bool { true }
    override var needsPanelToBecomeKey: Bool { true }

    // The app has no menu bar, whose Edit menu would turn ⌘A into Select All, so
    // the row maps it itself. Every view in the window is offered key
    // equivalents, so it takes them only while it has the keyboard.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if window?.firstResponder === self, performShortcut(event) { return true }
        return super.performKeyEquivalent(with: event)
    }

    // Reached instead when the hosting view does not pass key equivalents on.
    override func keyDown(with event: NSEvent) {
        if performShortcut(event) { return }
        super.keyDown(with: event)
    }

    private func performShortcut(_ event: NSEvent) -> Bool {
        guard
            let shelf,
            event.modifierFlags.intersection([.command, .shift, .option, .control]) == .command,
            event.charactersIgnoringModifiers?.lowercased() == "a"
        else { return false }
        shelf.selectAll()
        return true
    }

    override func mouseDown(with event: NSEvent) {
        // A press whose mouseUp went missing must not leak into this one.
        press = nil
        marquee = nil
        // A Control-click opens the context menu, as a right-click does.
        if event.modifierFlags.contains(.control) {
            rightMouseDown(with: event)
            return
        }
        guard let shelf else { return }
        mouseDownEvent = event
        pressOrigin = convert(event.locationInWindow, from: nil)
        let id = itemID(at: pressOrigin)
        let modifiers = event.modifierFlags.intersection([.shift, .command])
        if let id, modifiers.isEmpty {
            let wasSelected = shelf.selection.contains(id)
            if !wasSelected {
                shelf.select(id)
            }
            press = .item(id, selectsOnRelease: wasSelected)
        } else {
            if id == nil, modifiers.isEmpty {
                shelf.clearSelection()
            }
            press = .selection(base: shelf.selection, item: id, modifiers: modifiers)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownEvent, let press, let shelf else { return }
        if marquee == nil {
            let dx = event.locationInWindow.x - start.locationInWindow.x
            let dy = event.locationInWindow.y - start.locationInWindow.y
            guard dx * dx + dy * dy > Self.dragThreshold * Self.dragThreshold else { return }
        }

        switch press {
        case .item(let id, _):
            self.press = nil
            mouseDownEvent = nil
            dragOut(shelf.items(actingOn: id), startedBy: start, shelf: shelf)
        case .selection(let base, _, _):
            let point = convert(event.locationInWindow, from: nil)
            let rect = CGRect(
                x: min(pressOrigin.x, point.x),
                y: min(pressOrigin.y, point.y),
                width: abs(point.x - pressOrigin.x),
                height: abs(point.y - pressOrigin.y)
            )
            marquee = rect
            let covered = cellFrames.filter { $0.value.intersects(rect) }.keys
            shelf.setSelection(base.union(covered))
        }
    }

    override func mouseUp(with event: NSEvent) {
        let press = self.press
        let wasDrawingMarquee = marquee != nil
        self.press = nil
        mouseDownEvent = nil
        marquee = nil
        guard let press, let shelf, !wasDrawingMarquee else { return }

        switch press {
        case .item(let id, let selectsOnRelease):
            if selectsOnRelease {
                shelf.select(id)
            }
        case .selection(_, let id?, let modifiers):
            if modifiers.contains(.command) {
                shelf.toggleSelection(id)
            } else {
                shelf.extendSelection(to: id)
            }
        case .selection(_, nil, _):
            break
        }
    }

    private func dragOut(_ items: [ShelfItem], startedBy event: NSEvent, shelf: FileShelf) {
        var draggedIDs: Set<ShelfItem.ID> = []
        let draggingItems = items.compactMap { item -> NSDraggingItem? in
            guard let cell = cellFrames[item.id] else { return nil }
            draggedIDs.insert(item.id)
            let draggingItem = NSDraggingItem(pasteboardWriter: item.url as NSURL)
            draggingItem.setDraggingFrame(
                NSRect(
                    x: cell.midX - Self.iconSize / 2,
                    y: cell.minY + Self.cellPadding,
                    width: Self.iconSize,
                    height: Self.iconSize
                ),
                contents: NSWorkspace.shared.icon(forFile: item.url.path(percentEncoded: false))
            )
            return draggingItem
        }
        guard !draggingItems.isEmpty else { return }
        shelf.beginDrag(draggedIDs)
        beginDraggingSession(with: draggingItems, event: event, source: shelf.dragSource)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let marquee else { return }
        let path = NSBezierPath(roundedRect: marquee.insetBy(dx: 0.5, dy: 0.5), xRadius: 3, yRadius: 3)
        NSColor.white.withAlphaComponent(0.12).setFill()
        path.fill()
        NSColor.white.withAlphaComponent(0.5).setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let shelf, let id = itemID(at: convert(event.locationInWindow, from: nil)) else { return nil }
        // As in Finder, a right-click outside the selection selects that item alone.
        if !shelf.selection.contains(id) {
            shelf.select(id)
        }
        let items = shelf.items(actingOn: id)
        let menu = NSMenu()
        for (title, action) in [
            (localized(en: "Copy", zh: "拷贝"), #selector(copyItems(_:))),
            (localized(en: "Show in Finder", zh: "在访达中显示"), #selector(revealItems(_:))),
            (localized(en: "Remove", zh: "移除"), #selector(removeItems(_:))),
        ] {
            let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: "")
            menuItem.target = self
            menuItem.representedObject = items
            menu.addItem(menuItem)
        }
        return menu
    }

    @objc private func copyItems(_ sender: NSMenuItem) {
        guard let items = sender.representedObject as? [ShelfItem] else { return }
        shelf?.copy(items)
    }

    @objc private func revealItems(_ sender: NSMenuItem) {
        guard let items = sender.representedObject as? [ShelfItem] else { return }
        NSWorkspace.shared.activateFileViewerSelecting(items.map(\.url))
    }

    @objc private func removeItems(_ sender: NSMenuItem) {
        guard let items = sender.representedObject as? [ShelfItem] else { return }
        for item in items {
            shelf?.remove(item.id)
        }
    }

    private func itemID(at point: CGPoint) -> ShelfItem.ID? {
        cellFrames.first { $0.value.contains(point) }?.key
    }
}

extension ShelfRowNSView: NSViewToolTipOwner {
    func view(
        _ view: NSView,
        stringForToolTip tag: NSView.ToolTipTag,
        point: NSPoint,
        userData data: UnsafeMutableRawPointer?
    ) -> String {
        guard let id = itemID(at: point), let item = shelf?.items.first(where: { $0.id == id }) else { return "" }
        return item.url.path(percentEncoded: false)
    }
}

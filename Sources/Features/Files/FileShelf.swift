import AppKit
import Observation

/// A file waiting on the shelf. It references the original file; nothing is copied.
struct ShelfItem: Identifiable, Equatable {
    let id = UUID()
    let url: URL
}

/// The files staged in the Files tab, kept in memory only.
///
/// Also owns the long-lived drag source and pasteboard data providers: the views
/// that start a drag or a copy can disappear (the island collapses) before AppKit
/// calls back, so the callbacks must not depend on them.
@MainActor
@Observable
final class FileShelf {
    private static let removesAfterPasteKey = "FilesRemovesAfterPaste"

    private(set) var items: [ShelfItem] = []
    /// The items picked in the shelf; a drag or a menu command on one of them acts on all of them.
    private(set) var selection: Set<ShelfItem.ID> = []
    /// The items currently being dragged out of the shelf; empty when none is.
    private(set) var draggingItemIDs: Set<ShelfItem.ID> = []
    /// Where a Shift-click range starts: the item last clicked without Shift.
    @ObservationIgnored private var selectionAnchor: ShelfItem.ID?
    /// What else was selected when the anchor was set. A Shift-click selects its
    /// range on top of this, so a shorter range can replace a longer one.
    @ObservationIgnored private var selectionOutsideRange: Set<ShelfItem.ID> = []

    /// Whether an item leaves the shelf once it has been dropped or pasted elsewhere.
    var removesAfterPaste: Bool {
        didSet { UserDefaults.standard.set(removesAfterPaste, forKey: Self.removesAfterPasteKey) }
    }

    @ObservationIgnored private(set) lazy var dragSource = ShelfDragSource(shelf: self)
    /// Providers behind the general pasteboard's lazy file URL, keyed by their token.
    /// Held until the pasteboard lets go of them, even after the data was requested:
    /// NSPasteboardItem is not documented to retain its data provider.
    @ObservationIgnored private var pasteProviders: [UUID: ShelfPasteProvider] = [:]

    init() {
        removesAfterPaste = UserDefaults.standard.bool(forKey: Self.removesAfterPasteKey)
    }

    /// Appends dropped files in order, skipping non-file URLs and files already on the shelf.
    func add(_ urls: [URL]) {
        for url in urls {
            guard url.isFileURL, let path = (url as NSURL).filePathURL else { continue }
            let standardized = path.standardizedFileURL
            guard !items.contains(where: { $0.url.standardizedFileURL == standardized }) else { continue }
            items.append(ShelfItem(url: path))
        }
    }

    func remove(_ id: ShelfItem.ID) {
        items.removeAll { $0.id == id }
        selection.remove(id)
        selectionOutsideRange.remove(id)
        if selectionAnchor == id {
            selectionAnchor = nil
        }
    }

    // MARK: Selection

    /// A click: selects `id` alone.
    func select(_ id: ShelfItem.ID) {
        selection = [id]
        anchorSelection(at: id)
    }

    /// A Command-click: adds `id` to the selection, or takes it out.
    func toggleSelection(_ id: ShelfItem.ID) {
        if selection.remove(id) == nil {
            selection.insert(id)
        }
        anchorSelection(at: id)
    }

    /// A Shift-click: selects the items from the anchor to `id`, on top of what
    /// else was selected when the anchor was set. Without an anchor it adds `id`
    /// to the selection and anchors there.
    func extendSelection(to id: ShelfItem.ID) {
        guard
            let anchor = selectionAnchor,
            let from = items.firstIndex(where: { $0.id == anchor }),
            let to = items.firstIndex(where: { $0.id == id })
        else {
            selection.insert(id)
            anchorSelection(at: id)
            return
        }
        selection = selectionOutsideRange.union(items[min(from, to)...max(from, to)].map(\.id))
    }

    /// Replaces the selection, for instance with what a selection rectangle
    /// covers. A later Shift-click keeps all of it and extends from the anchor.
    func setSelection(_ ids: Set<ShelfItem.ID>) {
        // The cells' frames can lag a removal by a layout pass.
        selection = ids.filter { id in items.contains { $0.id == id } }
        selectionOutsideRange = selection.subtracting(selectionAnchor.map { [$0] } ?? [])
    }

    /// ⌘A: selects every item.
    func selectAll() {
        setSelection(Set(items.map(\.id)))
    }

    func clearSelection() {
        selection = []
        selectionAnchor = nil
        selectionOutsideRange = []
    }

    /// The items a drag or a menu command on `id` acts on, in shelf order: the
    /// whole selection when `id` is in it, else `id` alone.
    func items(actingOn id: ShelfItem.ID) -> [ShelfItem] {
        let ids = selection.contains(id) ? selection : [id]
        return items.filter { ids.contains($0.id) }
    }

    private func anchorSelection(at id: ShelfItem.ID) {
        selectionAnchor = id
        selectionOutsideRange = selection.subtracting([id])
    }

    // MARK: Dragging and copying

    func beginDrag(_ ids: Set<ShelfItem.ID>) {
        draggingItemIDs = ids
    }

    func endDrag(operation: NSDragOperation) {
        guard !draggingItemIDs.isEmpty else { return }
        let ids = draggingItemIDs
        draggingItemIDs = []
        if !operation.isEmpty && removesAfterPaste {
            for id in ids {
                remove(id)
            }
        }
    }

    /// Puts the items' file URLs on the general pasteboard. Each URL is provided
    /// lazily, so the first request for it tells us that file was pasted somewhere.
    func copy(_ items: [ShelfItem]) {
        let pasteboardItems = items.map { item in
            let id = item.id
            let provider = ShelfPasteProvider(url: item.url) { [weak self] token in
                // The item is registered for one type, so AppKit asks for its data once.
                guard let self, self.pasteProviders[token] != nil else { return }
                if self.removesAfterPaste {
                    self.remove(id)
                }
            } onFinished: { [weak self] token in
                self?.pasteProviders.removeValue(forKey: token)
            }
            pasteProviders[provider.token] = provider

            let pasteboardItem = NSPasteboardItem()
            pasteboardItem.setDataProvider(provider, forTypes: [.fileURL])
            return pasteboardItem
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(pasteboardItems)
    }
}

/// Drag source for items dragged out of the shelf. Owned by the shelf, not the
/// row view, so the end callback still arrives after the view is gone.
@MainActor
final class ShelfDragSource: NSObject, NSDraggingSource {
    private unowned let shelf: FileShelf

    init(shelf: FileShelf) {
        self.shelf = shelf
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        // Copy only: with .move or .generic, Finder moves the original file when
        // the destination is on the same volume.
        .copy
    }

    func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        shelf.endDrag(operation: operation)
    }
}

/// Supplies a shelf item's file URL to the general pasteboard on demand.
///
/// AppKit calls the provider off the main actor, so it holds only immutable
/// Sendable state, answers synchronously, and hops to the main actor to report.
final class ShelfPasteProvider: NSObject, NSPasteboardItemDataProvider, Sendable {
    let token = UUID()
    private let url: URL
    private let onRequest: @MainActor @Sendable (UUID) -> Void
    private let onFinished: @MainActor @Sendable (UUID) -> Void

    init(
        url: URL,
        onRequest: @escaping @MainActor @Sendable (UUID) -> Void,
        onFinished: @escaping @MainActor @Sendable (UUID) -> Void
    ) {
        self.url = url
        self.onRequest = onRequest
        self.onFinished = onFinished
    }

    func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
        item.setString(url.absoluteString, forType: type)
        Task { @MainActor [token, onRequest] in onRequest(token) }
    }

    func pasteboardFinishedWithDataProvider(_ pasteboard: NSPasteboard) {
        // Enqueued after any request reported above, so a paste is counted before
        // the provider is released.
        Task { @MainActor [token, onFinished] in onFinished(token) }
    }
}

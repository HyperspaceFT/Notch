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
    /// The item currently being dragged out of the shelf, if any.
    private(set) var draggingItemID: ShelfItem.ID?

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
    }

    func beginDrag(_ id: ShelfItem.ID) {
        draggingItemID = id
    }

    func endDrag(operation: NSDragOperation) {
        guard let id = draggingItemID else { return }
        draggingItemID = nil
        if !operation.isEmpty && removesAfterPaste {
            remove(id)
        }
    }

    /// Puts the item's file URL on the general pasteboard. The URL is provided lazily,
    /// so the first request for it tells us the file was pasted somewhere.
    func copy(_ item: ShelfItem) {
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
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([pasteboardItem])
    }
}

/// Drag source for items dragged out of the shelf. Owned by the shelf, not the
/// item view, so the end callback still arrives after the view is gone.
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

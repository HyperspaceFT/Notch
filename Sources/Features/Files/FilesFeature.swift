import AppKit
import NotchKit
import NotchUI
import SwiftUI
import UniformTypeIdentifiers

/// A tab with an AirDrop drop zone and a shelf that holds files for dragging or
/// pasting elsewhere. Files dragged onto the notch open the island on this tab.
@MainActor
public final class FilesFeature: NotchFeature {
    public let id = "files"
    public let title = "文件"
    public let symbol = "folder"
    public let opensOnDrag = true

    private let shelf = FileShelf()
    private let airDropTarget = DropTarget()
    private let shelfTarget = DropTarget()

    public init() {}

    public func makeExpandedView() -> AnyView? {
        AnyView(FilesExpandedView(shelf: shelf, airDropTarget: airDropTarget, shelfTarget: shelfTarget))
    }
}

private struct FilesExpandedView: View {
    let shelf: FileShelf
    let airDropTarget: DropTarget
    let shelfTarget: DropTarget

    var body: some View {
        HStack(spacing: 10) {
            AirDropZone(target: airDropTarget)
                .frame(width: 130)
            ShelfCard(shelf: shelf, target: shelfTarget)
        }
    }
}

private struct ShelfCard: View {
    @Bindable var shelf: FileShelf
    @Bindable var target: DropTarget

    var body: some View {
        NotchCard {
            HStack {
                Text("文件暂存")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(NotchTheme.secondaryText)
                Spacer()
                Toggle("粘贴后自动删除文件", isOn: $shelf.removesAfterPaste)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .font(.system(size: 11))
                    .foregroundStyle(NotchTheme.secondaryText)
                    .help("文件被拖出或粘贴到别处后，自动从暂存区移除（不会删除原文件）")
            }
            if shelf.items.isEmpty {
                Text("把文件拖到这里暂存")
                    .font(.system(size: 12))
                    .foregroundStyle(NotchTheme.secondaryText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(shelf.items) { item in
                            ShelfItemCell(item: item, shelf: shelf)
                        }
                    }
                }
            }
        }
        // While one of the shelf's own items is dragged, dropping it back is not
        // an addition (no duplicate) and must not count as a paste.
        .dropZone(isTargeted: target.isTargeted && shelf.draggingItemID == nil)
        .onDrop(of: [.fileURL], isTargeted: $target.isTargeted) { providers in
            guard shelf.draggingItemID == nil else { return false }
            Task { @MainActor [shelf] in
                shelf.add(await loadFileURLs(from: providers))
            }
            return true
        }
    }
}

private struct ShelfItemCell: View {
    let item: ShelfItem
    let shelf: FileShelf

    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path(percentEncoded: false)))
                .resizable()
                .frame(width: ShelfItemDragNSView.iconSize, height: ShelfItemDragNSView.iconSize)
            Text(item.url.lastPathComponent)
                .font(.system(size: 10))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(width: 64)
        .opacity(shelf.draggingItemID == item.id ? 0.4 : 1)
        .overlay {
            ShelfItemDragView(item: item, shelf: shelf)
        }
    }
}

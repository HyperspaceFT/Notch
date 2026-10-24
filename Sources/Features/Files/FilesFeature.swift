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
    public var title: String { localized(en: "Files", zh: "文件") }
    public let symbol = "folder"
    public let opensOnDrag = true

    private let shelf = FileShelf()
    private let airDropTarget = DropTarget()
    private let shelfTarget = DropTarget()

    private var highlightTask: Task<Void, Never>?

    public init() {}

    public func deactivate() {
        highlightTask?.cancel()
        highlightTask = nil
    }

    /// Sample files on the shelf, and the AirDrop zone's drop highlight, for
    /// checking the tab. The files are written to the temporary directory and
    /// only these leave the shelf again; nothing is sent with AirDrop.
    public var debugItems: [NotchMenuItem] {
        [
            .button(localized(en: "Add Sample Files", zh: "添加示例文件"), symbol: "doc.badge.plus") { [shelf] in
                shelf.add(FileSamples.create())
            },
            .button(localized(en: "Remove Sample Files", zh: "移除示例文件"), symbol: "doc.badge.minus") { [shelf] in
                shelf.removeItems(inside: FileSamples.directory)
                FileSamples.delete()
            },
            .divider,
            .button(localized(en: "Highlight the AirDrop Zone", zh: "高亮 AirDrop 区域"), symbol: "dot.radiowaves.left.and.right") { [weak self] in
                self?.highlightAirDropZone()
            },
        ]
    }

    private func highlightAirDropZone() {
        highlightTask?.cancel()
        airDropTarget.isTargeted = true
        highlightTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, let self else { return }
            airDropTarget.isTargeted = false
            highlightTask = nil
        }
    }

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
                Text(localized(en: "Shelf", zh: "文件暂存"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(NotchTheme.secondaryText)
                Spacer()
                Toggle(localized(en: "Remove after pasting", zh: "粘贴后自动删除文件"), isOn: $shelf.removesAfterPaste)
                    .toggleStyle(.notchSwitch)
                    .font(.system(size: 11))
                    .foregroundStyle(NotchTheme.secondaryText)
                    .help(localized(
                        en: "Removes files from the shelf once they are dragged out or pasted elsewhere (the originals are kept)",
                        zh: "文件被拖出或粘贴到别处后，自动从暂存区移除（不会删除原文件）"
                    ))
            }
            if shelf.items.isEmpty {
                Text(localized(en: "Drop files here to keep them handy", zh: "把文件拖到这里暂存"))
                    .font(.system(size: 12))
                    .foregroundStyle(NotchTheme.secondaryText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GeometryReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(shelf.items) { item in
                                ShelfItemCell(item: item, shelf: shelf)
                            }
                        }
                        // As big as the visible card below the header, so a click
                        // or a selection rectangle can start beside the items too.
                        .frame(minWidth: proxy.size.width, minHeight: proxy.size.height, alignment: .topLeading)
                        .coordinateSpace(.named(ShelfRowView.coordinateSpace))
                        .overlayPreferenceValue(ShelfCellFramesKey.self) { frames in
                            ShelfRowView(shelf: shelf, cellFrames: frames)
                        }
                    }
                }
            }
        }
        // While the shelf's own items are dragged, dropping them back is not an
        // addition (no duplicates) and must not count as a paste.
        .dropZone(isTargeted: target.isTargeted && shelf.draggingItemIDs.isEmpty)
        .onDrop(of: [.fileURL], isTargeted: $target.isTargeted) { providers in
            guard shelf.draggingItemIDs.isEmpty else { return false }
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
                .frame(width: ShelfRowNSView.iconSize, height: ShelfRowNSView.iconSize)
            Text(item.url.lastPathComponent)
                .font(.system(size: 10))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(width: 64)
        .padding(ShelfRowNSView.cellPadding)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.white.opacity(shelf.selection.contains(item.id) ? 0.16 : 0))
        }
        .opacity(shelf.draggingItemIDs.contains(item.id) ? 0.4 : 1)
        // The row's AppKit overlay hit-tests the cells by these frames.
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: ShelfCellFramesKey.self,
                    value: [item.id: proxy.frame(in: .named(ShelfRowView.coordinateSpace))]
                )
            }
        }
    }
}

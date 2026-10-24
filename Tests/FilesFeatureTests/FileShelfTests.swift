import AppKit
import Foundation
import Testing
@testable import FilesFeature

@MainActor
struct FileShelfTests {
    private let shelf: FileShelf
    /// The ids of five shelved files, a to e, in shelf order.
    private let ids: [ShelfItem.ID]

    init() {
        shelf = FileShelf()
        shelf.add(["a", "b", "c", "d", "e"].map { URL(fileURLWithPath: "/tmp/shelf-test/\($0)") })
        ids = shelf.items.map(\.id)
    }

    @Test func clickSelectsOneItemAlone() {
        shelf.select(ids[1])
        shelf.select(ids[3])
        #expect(shelf.selection == [ids[3]])
    }

    @Test func commandClickTogglesItems() {
        shelf.select(ids[0])
        shelf.toggleSelection(ids[2])
        #expect(shelf.selection == [ids[0], ids[2]])
        shelf.toggleSelection(ids[0])
        #expect(shelf.selection == [ids[2]])
    }

    @Test func shiftClickSelectsTheRangeFromTheAnchorEitherWay() {
        shelf.select(ids[1])
        shelf.extendSelection(to: ids[3])
        #expect(shelf.selection == Set(ids[1...3]))
        // A shorter range on the other side replaces the longer one.
        shelf.extendSelection(to: ids[0])
        #expect(shelf.selection == Set(ids[0...1]))
    }

    @Test func shiftClickKeepsWhatWasCommandClickedBeforeTheAnchor() {
        shelf.select(ids[0])
        shelf.toggleSelection(ids[2])
        shelf.extendSelection(to: ids[4])
        #expect(shelf.selection == [ids[0], ids[2], ids[3], ids[4]])
    }

    @Test func shiftClickWithoutAnchorAddsTheItemAndAnchorsThere() {
        shelf.extendSelection(to: ids[2])
        #expect(shelf.selection == [ids[2]])
        shelf.extendSelection(to: ids[4])
        #expect(shelf.selection == Set(ids[2...4]))
    }

    @Test func shiftClickAfterASelectionRectangleKeepsWhatItCovered() {
        // A click on a, then a Shift-drag rectangle over c and d (on top of a).
        shelf.select(ids[0])
        shelf.setSelection([ids[0], ids[2], ids[3]])
        shelf.extendSelection(to: ids[1])
        #expect(shelf.selection == Set(ids[0...3]))
    }

    @Test func shiftClickAfterARectangleFromEmptySpaceAddsTheItem() {
        shelf.select(ids[0])
        shelf.clearSelection()
        shelf.setSelection([ids[1], ids[2]])
        shelf.extendSelection(to: ids[4])
        #expect(shelf.selection == [ids[1], ids[2], ids[4]])
    }

    @Test func aSelectionRectangleIgnoresRemovedItems() {
        let removed = ids[3]
        shelf.remove(removed)
        shelf.setSelection([ids[0], removed])
        #expect(shelf.selection == [ids[0]])
    }

    @Test func actionsOnASelectedItemTakeTheWholeSelectionInShelfOrder() {
        shelf.select(ids[3])
        shelf.toggleSelection(ids[1])
        #expect(shelf.items(actingOn: ids[3]).map(\.id) == [ids[1], ids[3]])
        // An item outside the selection acts alone.
        #expect(shelf.items(actingOn: ids[0]).map(\.id) == [ids[0]])
    }

    @Test func removingAnItemDropsItFromTheSelectionAndTheAnchor() {
        shelf.select(ids[1])
        shelf.toggleSelection(ids[2])
        shelf.remove(ids[2])
        #expect(shelf.selection == [ids[1]])
        // The removed anchor no longer starts a range.
        shelf.extendSelection(to: ids[4])
        #expect(shelf.selection == [ids[1], ids[4]])
    }

    @Test func aDragThatDropsNothingKeepsItsItems() {
        shelf.beginDrag([ids[0], ids[1]])
        #expect(shelf.draggingItemIDs == [ids[0], ids[1]])
        shelf.endDrag(operation: [])
        #expect(shelf.draggingItemIDs.isEmpty)
        #expect(shelf.items.count == 5)
    }
}

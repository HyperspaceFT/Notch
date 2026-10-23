import Foundation
import Testing
@testable import NotesFeature

/// A temporary folder for one test's notes file, removed after `body`.
@MainActor
private func withFolder(_ body: (URL) async throws -> Void) async rethrows {
    let folder = FileManager.default.temporaryDirectory
        .appending(path: "NotesStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: folder) }
    try await body(folder)
}

@MainActor
private func makeStore(in folder: URL, saveDelay: Duration = .seconds(60)) -> NotesStore {
    NotesStore(fileURL: folder.appending(path: "Notes.json"), saveDelay: saveDelay)
}

@MainActor
struct NotesStoreTests {
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    @Test func typingIntoAnEmptyStoreCreatesAndSelectsANote() async {
        await withFolder { folder in
            let store = makeStore(in: folder)
            #expect(store.notes.isEmpty)
            #expect(store.selectedNote == nil)

            store.setText("\n   \n  Groceries  \nmilk", now: start)
            #expect(store.notes.count == 1)
            #expect(store.selectedID == store.notes.first?.id)
            #expect(store.selectedNote?.text == "\n   \n  Groceries  \nmilk")
            #expect(store.selectedNote?.title == "Groceries")
        }
    }

    @Test func aBlankNoteHasNoTitle() {
        let note = Note(id: UUID(), text: " \n\t\n ", created: start, modified: start)
        #expect(note.title == nil)
        #expect(Note(id: UUID(), text: "", created: start, modified: start).title == nil)
    }

    @Test func settingTheSameTextKeepsTheModifiedDate() async {
        await withFolder { folder in
            let store = makeStore(in: folder)
            store.setText("a", now: start)
            store.setText("a", now: start.addingTimeInterval(60))
            #expect(store.selectedNote?.modified == start)
            store.setText("ab", now: start.addingTimeInterval(120))
            #expect(store.selectedNote?.modified == start.addingTimeInterval(120))
            #expect(store.selectedNote?.created == start)
        }
    }

    @Test func newNoteGoesFirstAndIsSelected() async {
        await withFolder { folder in
            let store = makeStore(in: folder)
            store.setText("first", now: start)
            let first = store.selectedID
            store.newNote(now: start.addingTimeInterval(10))
            #expect(store.notes.count == 2)
            #expect(store.notes.first?.id == store.selectedID)
            #expect(store.selectedID != first)
            #expect(store.selectedNote?.text == "")
            #expect(store.notes.last?.id == first)
        }
    }

    @Test func aBlankSelectedNoteIsReused() async {
        await withFolder { folder in
            let store = makeStore(in: folder)
            store.setText("first", now: start)
            store.newNote(now: start.addingTimeInterval(10))
            let blank = store.selectedID
            store.setText("   ", now: start.addingTimeInterval(20))
            store.newNote(now: start.addingTimeInterval(30))
            #expect(store.notes.count == 2)
            #expect(store.selectedID == blank)
        }
    }

    @Test func selectingAwayFromABlankNoteRemovesIt() async {
        await withFolder { folder in
            let store = makeStore(in: folder)
            store.setText("kept", now: start)
            let kept = store.selectedID!
            store.newNote(now: start.addingTimeInterval(10))
            let blank = store.selectedID!
            store.select(kept)
            #expect(store.selectedID == kept)
            #expect(store.notes.map(\.id) == [kept])
            #expect(!store.notes.contains { $0.id == blank })
        }
    }

    @Test func selectingAwayFromANoteWithTextKeepsIt() async {
        await withFolder { folder in
            let store = makeStore(in: folder)
            store.setText("older", now: start)
            let older = store.selectedID!
            store.newNote(now: start.addingTimeInterval(10))
            store.setText("newer", now: start.addingTimeInterval(11))
            let newer = store.selectedID!
            store.select(older)
            #expect(store.notes.map(\.id) == [newer, older])
            #expect(store.selectedID == older)
        }
    }

    @Test func nextAndPreviousFollowTheListAndStopAtTheEnds() async {
        await withFolder { folder in
            let store = makeStore(in: folder)
            store.setText("c", now: start)
            store.newNote(now: start.addingTimeInterval(1))
            store.setText("b", now: start.addingTimeInterval(1))
            store.newNote(now: start.addingTimeInterval(2))
            store.setText("a", now: start.addingTimeInterval(2))
            #expect(store.notes.map(\.text) == ["a", "b", "c"])
            #expect(store.selectedNote?.text == "a")

            store.selectPrevious()
            #expect(store.selectedNote?.text == "a")
            store.selectNext()
            #expect(store.selectedNote?.text == "b")
            store.selectNext()
            #expect(store.selectedNote?.text == "c")
            store.selectNext()
            #expect(store.selectedNote?.text == "c")
            store.selectPrevious()
            #expect(store.selectedNote?.text == "b")
            #expect(store.notes.map(\.text) == ["a", "b", "c"])
        }
    }

    @Test func deleteSelectsTheNextNoteElseThePrevious() async {
        await withFolder { folder in
            let store = makeStore(in: folder)
            store.setText("c", now: start)
            store.newNote(now: start.addingTimeInterval(1))
            store.setText("b", now: start.addingTimeInterval(1))
            store.newNote(now: start.addingTimeInterval(2))
            store.setText("a", now: start.addingTimeInterval(2))

            store.selectNext()
            store.delete(store.selectedID!)
            #expect(store.notes.map(\.text) == ["a", "c"])
            #expect(store.selectedNote?.text == "c")

            store.delete(store.selectedID!)
            #expect(store.notes.map(\.text) == ["a"])
            #expect(store.selectedNote?.text == "a")

            store.delete(store.selectedID!)
            #expect(store.notes.isEmpty)
            #expect(store.selectedID == nil)
        }
    }

    @Test func deletingAnotherNoteKeepsTheSelection() async {
        await withFolder { folder in
            let store = makeStore(in: folder)
            store.setText("b", now: start)
            let b = store.selectedID!
            store.newNote(now: start.addingTimeInterval(1))
            store.setText("a", now: start.addingTimeInterval(1))
            store.delete(b)
            #expect(store.notes.map(\.text) == ["a"])
            #expect(store.selectedNote?.text == "a")
        }
    }

    @Test func flushedNotesSurviveARelaunchWithoutTheBlankOne() async {
        await withFolder { folder in
            let store = makeStore(in: folder)
            store.setText("older", now: start)
            store.newNote(now: start.addingTimeInterval(1))
            store.setText("newer\nsecond line", now: start.addingTimeInterval(2))
            let saved = store.notes
            store.newNote(now: start.addingTimeInterval(3))
            #expect(store.notes.count == 3)
            store.flush()

            let reloaded = makeStore(in: folder)
            #expect(reloaded.notes == saved)
            #expect(reloaded.notes.map(\.text) == ["newer\nsecond line", "older"])
            // The blank note was selected; the selection falls back to the first note.
            #expect(reloaded.selectedID == saved.first?.id)
        }
    }

    @Test func theSelectionSurvivesARelaunch() async {
        await withFolder { folder in
            let store = makeStore(in: folder)
            store.setText("older", now: start)
            let older = store.selectedID
            store.newNote(now: start.addingTimeInterval(1))
            store.setText("newer", now: start.addingTimeInterval(2))
            store.selectNext()
            store.flush()

            let reloaded = makeStore(in: folder)
            #expect(reloaded.notes.map(\.text) == ["newer", "older"])
            #expect(reloaded.selectedID == older)
        }
    }

    @Test func anUnreadableFileIsMovedAsideAndKept() async throws {
        try await withFolder { folder in
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appending(path: "Notes.json")
            let bytes = Data("not json {".utf8)
            try bytes.write(to: url)

            let store = makeStore(in: folder)
            #expect(store.notes.isEmpty)
            #expect(!FileManager.default.fileExists(atPath: url.path))
            let aside = try FileManager.default.contentsOfDirectory(atPath: folder.path)
                .filter { $0.hasPrefix("Notes-unreadable-") && $0.hasSuffix(".json") }
            #expect(aside.count == 1)
            let movedURL = folder.appending(path: try #require(aside.first))
            #expect(try Data(contentsOf: movedURL) == bytes)

            store.setText("fresh", now: start)
            store.flush()
            #expect(try Data(contentsOf: movedURL) == bytes)
            #expect(makeStore(in: folder).notes.map(\.text) == ["fresh"])
        }
    }

    @Test func aFileThatCannotBeReadIsNeverOverwritten() async throws {
        try await withFolder { folder in
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appending(path: "Notes.json")
            let bytes = Data(#"{"notes":[]}"#.utf8)
            try bytes.write(to: url)
            try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: url.path)
            defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path) }

            let store = makeStore(in: folder)
            #expect(store.notes.isEmpty)
            store.setText("typed while the file was locked", now: start)
            store.flush()

            try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
            #expect(try Data(contentsOf: url) == bytes)
        }
    }

    @Test func typingWithoutAPauseIsStillSaved() async {
        await withFolder { folder in
            let store = makeStore(in: folder, saveDelay: .milliseconds(100))
            let url = folder.appending(path: "Notes.json")
            // Changes come faster than the delay for five times its length.
            let end = ContinuousClock.now + .milliseconds(500)
            var text = ""
            while ContinuousClock.now < end {
                text += "a"
                store.setText(text, now: start)
                try? await Task.sleep(for: .milliseconds(20))
            }
            #expect(FileManager.default.fileExists(atPath: url.path))
        }
    }

    @Test func aChangeIsSavedAfterTheDelayWithoutFlush() async {
        await withFolder { folder in
            let store = makeStore(in: folder, saveDelay: .milliseconds(50))
            store.setText("saved by itself", now: start)
            let url = folder.appending(path: "Notes.json")
            let deadline = ContinuousClock.now + .seconds(2)
            while !FileManager.default.fileExists(atPath: url.path), ContinuousClock.now < deadline {
                try? await Task.sleep(for: .milliseconds(20))
            }
            #expect(makeStore(in: folder).notes.map(\.text) == ["saved by itself"])
        }
    }
}

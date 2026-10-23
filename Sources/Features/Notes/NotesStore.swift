import Foundation
import Observation

/// One note: plain text with when it was created and last changed.
struct Note: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var text: String
    let created: Date
    var modified: Date

    /// The first line with something on it, trimmed; `nil` for a blank note.
    var title: String? {
        text.split(whereSeparator: \.isNewline)
            .lazy
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
    }

    var isBlank: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// The notes written in the island, shared by the Notes tab and the Notes Home
/// module, and the one selected in both.
///
/// Notes are listed newest created first, so the order holds still while the
/// user types. A blank note is dropped as soon as another one is selected, as
/// in Apple Notes. Every change is saved to a JSON file within `saveDelay`;
/// `flush()` saves at once (on quit).
@MainActor
@Observable
final class NotesStore {
    static let shared = NotesStore(fileURL: defaultFileURL, saveDelay: .milliseconds(500))

    /// Application Support/<bundle id>/Notes.json. Notes can be long, so they
    /// live in a file of their own rather than in the defaults.
    static var defaultFileURL: URL {
        URL.applicationSupportDirectory
            .appending(path: Bundle.main.bundleIdentifier ?? "Notch", directoryHint: .isDirectory)
            .appending(path: "Notes.json", directoryHint: .notDirectory)
    }

    /// What the file holds; a wrapper rather than a bare array, so fields can be added later.
    private struct Saved: Codable {
        var notes: [Note]
        var selectedID: UUID?
    }

    private(set) var notes: [Note] = []
    private(set) var selectedID: UUID?

    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private let saveDelay: Duration
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    /// Changes not yet written. Stays set after a failed write, so the next
    /// change or `flush()` tries again.
    @ObservationIgnored private var hasUnsavedChanges = false
    /// Set when the file is there but could neither be read nor moved aside:
    /// saving would replace notes this store never saw, so nothing is written.
    @ObservationIgnored private var isSavingBlocked = false

    init(fileURL: URL, saveDelay: Duration) {
        self.fileURL = fileURL
        self.saveDelay = saveDelay
        load()
    }

    var selectedNote: Note? {
        guard let selectedID else { return nil }
        return notes.first { $0.id == selectedID }
    }

    /// The selected note's position in the list, from 0.
    var selectedIndex: Int? {
        guard let selectedID else { return nil }
        return notes.firstIndex { $0.id == selectedID }
    }

    // MARK: Changes

    /// Sets the selected note's text. With no note selected, a non-empty text
    /// starts a new note, so the first one needs no "+".
    func setText(_ text: String, now: Date = Date()) {
        guard let index = selectedIndex else {
            guard !text.isEmpty else { return }
            let note = Note(id: UUID(), text: text, created: now, modified: now)
            notes.insert(note, at: 0)
            selectedID = note.id
            didChange()
            return
        }
        guard notes[index].text != text else { return }
        notes[index].text = text
        notes[index].modified = now
        didChange()
    }

    /// Selects a new blank note at the top of the list, or the selected note
    /// when it is already blank.
    func newNote(now: Date = Date()) {
        if let selectedNote, selectedNote.isBlank {
            return
        }
        let note = Note(id: UUID(), text: "", created: now, modified: now)
        notes.insert(note, at: 0)
        selectedID = note.id
        didChange()
    }

    /// Selects the note `id`, dropping the previously selected one if it is blank.
    func select(_ id: UUID) {
        guard id != selectedID, notes.contains(where: { $0.id == id }) else { return }
        let previous = selectedNote
        selectedID = id
        if let previous, previous.isBlank {
            notes.removeAll { $0.id == previous.id }
        }
        didChange()
    }

    /// Selects the note after the selected one in the list, if any.
    func selectNext() {
        guard let index = selectedIndex, index + 1 < notes.count else { return }
        select(notes[index + 1].id)
    }

    /// Selects the note before the selected one in the list, if any.
    func selectPrevious() {
        guard let index = selectedIndex, index > 0 else { return }
        select(notes[index - 1].id)
    }

    /// Removes the note `id`. When it was selected, the note that takes its
    /// place in the list is selected, else the one before it.
    func delete(_ id: UUID) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes.remove(at: index)
        if id == selectedID {
            if notes.indices.contains(index) {
                selectedID = notes[index].id
            } else {
                selectedID = notes.last?.id
            }
        }
        didChange()
    }

    // MARK: Saving

    /// Writes unsaved changes now instead of after the delay.
    func flush() {
        saveTask?.cancel()
        saveTask = nil
        guard hasUnsavedChanges else { return }
        save()
    }

    private func didChange() {
        hasUnsavedChanges = true
        // A save already waiting writes this change too. It is not pushed back,
        // so a long stretch of typing is still saved every `saveDelay`.
        guard saveTask == nil else { return }
        let delay = saveDelay
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            self.saveTask = nil
            self.save()
        }
    }

    private func save() {
        guard !isSavingBlocked else { return }
        // A blank note being written is selected; it is dropped on the next load.
        let saved = Saved(notes: notes, selectedID: selectedID)
        do {
            let data = try JSONEncoder().encode(saved)
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: .atomic)
            hasUnsavedChanges = false
        } catch {
            // Left marked unsaved; the next change or flush retries.
        }
    }

    private func load() {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return
        } catch {
            // There but unreadable, e.g. its permissions changed.
            isSavingBlocked = true
            return
        }
        guard let saved = try? JSONDecoder().decode(Saved.self, from: data) else {
            if !moveUnreadableFileAside() {
                isSavingBlocked = true
            }
            return
        }
        notes = saved.notes
            .filter { !$0.isBlank }
            .sorted { $0.created > $1.created }
        if let id = saved.selectedID, notes.contains(where: { $0.id == id }) {
            selectedID = id
        } else {
            selectedID = notes.first?.id
        }
    }

    /// Keeps a file that does not decode (written by a newer version, or damaged)
    /// next to the new one instead of overwriting it with the next save. False
    /// when it could not be moved.
    private func moveUnreadableFileAside() -> Bool {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stem = "\(fileURL.deletingPathExtension().lastPathComponent)-unreadable-\(formatter.string(from: Date()))"
        let folder = fileURL.deletingLastPathComponent()
        // A second unreadable file within the same second gets a number, so
        // neither is lost.
        for attempt in 1...100 {
            let name = attempt == 1 ? stem : "\(stem)-\(attempt)"
            let destination = folder.appending(path: "\(name).\(fileURL.pathExtension)", directoryHint: .notDirectory)
            if (try? FileManager.default.moveItem(at: fileURL, to: destination)) != nil { return true }
        }
        return false
    }
}

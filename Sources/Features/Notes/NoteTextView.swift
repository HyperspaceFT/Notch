import AppKit
import SwiftUI

/// A plain-text editor for the island. AppKit rather than `TextEditor`, which
/// leaves no say over the first click, Esc, or the caret color in a panel that
/// is never active.
struct NoteTextView: NSViewRepresentable {
    @Binding var text: String
    /// The note being edited. When it changes the editor starts over at the top,
    /// with nothing to undo.
    let noteID: UUID?
    /// Changing it puts the caret in this editor.
    let focusToken: Int

    static let font = NSFont.systemFont(ofSize: 12)

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = IslandScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay

        let textView = IslandTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.font = Self.font
        // Set outright: the app does not force a dark appearance, so the defaults
        // could be black on the black island.
        textView.textColor = .white
        textView.insertionPointColor = .white
        textView.typingAttributes = [.font: Self.font, .foregroundColor: NSColor.white]
        // Flush with the card's other content and with the placeholder.
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.string = text

        scrollView.documentView = textView
        context.coordinator.noteID = noteID
        context.coordinator.focusToken = focusToken
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        let coordinator = context.coordinator
        coordinator.text = $text
        // The binding writes to the selected note, which during a switch is
        // already the next one; nothing changed here may reach it.
        coordinator.isApplyingUpdate = true
        defer { coordinator.isApplyingUpdate = false }

        // Typing into an empty store creates the note this text already shows;
        // that is not a switch, and the caret stays where it is.
        let isNoteCreatedByTyping = coordinator.noteID == nil && textView.string == text
        if coordinator.noteID != noteID, !isNoteCreatedByTyping {
            coordinator.noteID = noteID
            // Dropped, not committed: committing would write it into the next note.
            textView.inputContext?.discardMarkedText()
            textView.string = text
            textView.setSelectedRange(NSRange(location: 0, length: 0))
            textView.scroll(.zero)
            // Undo must not carry one note's text into another.
            coordinator.undoManager.removeAllActions()
        } else if coordinator.noteID != noteID {
            coordinator.noteID = noteID
        } else if textView.string != text, !textView.hasMarkedText() {
            // Never while an input method composes, which would break the composition.
            textView.string = text
            // Typed in the other card; the steps to undo here were for the old text.
            coordinator.undoManager.removeAllActions()
        }

        if coordinator.focusToken != focusToken {
            coordinator.focusToken = focusToken
            // After SwiftUI has finished this update, so the view is in its window.
            Task { @MainActor [weak textView] in
                guard let textView, let window = textView.window else { return }
                // The one window call a feature makes: the panel takes the
                // keyboard only for a text view, and this is its own.
                window.makeKey()
                window.makeFirstResponder(textView)
            }
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var noteID: UUID?
        var focusToken = 0
        /// Set while `updateNSView` changes the text view, so those changes are not
        /// taken for typing.
        var isApplyingUpdate = false
        /// This editor's own. The text views would otherwise share the panel's, so
        /// clearing one editor's steps would clear the other card's too.
        let undoManager = UndoManager()

        init(text: Binding<String>) {
            self.text = text
        }

        func undoManager(for view: NSTextView) -> UndoManager? {
            undoManager
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingUpdate, let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }
    }
}

/// The editor's scroll view. Keeps the text view at least as tall as the visible
/// area, so a click anywhere in the editor, not only on the lines it has, puts
/// the caret in it.
private final class IslandScrollView: NSScrollView {
    override func tile() {
        super.tile()
        guard let textView = documentView as? NSTextView else { return }
        let height = contentSize.height
        guard textView.minSize.height != height else { return }
        textView.minSize = NSSize(width: 0, height: height)
        if textView.frame.height < height {
            textView.setFrameSize(NSSize(width: textView.frame.width, height: height))
        }
    }
}

/// The editor's text view, adjusted for a panel that is never active.
private final class IslandTextView: NSTextView {
    // The first click must place the caret, not only make the panel key.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // Esc ends editing rather than opening the completion list.
    override func cancelOperation(_ sender: Any?) {
        window?.makeFirstResponder(nil)
    }

    // The app has no menu bar, whose Edit menu would turn ⌘X, ⌘C, ⌘V, ⌘A, ⌘Z,
    // and ⇧⌘Z into actions, so the editor maps them itself. Every view in the
    // window is offered key equivalents, the other card's editor too, so only
    // the one with the keyboard takes them.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if window?.firstResponder === self, performEditingShortcut(event) { return true }
        return super.performKeyEquivalent(with: event)
    }

    // Reached instead when the hosting view does not pass key equivalents on.
    override func keyDown(with event: NSEvent) {
        if performEditingShortcut(event) { return }
        super.keyDown(with: event)
    }

    private func performEditingShortcut(_ event: NSEvent) -> Bool {
        // While an input method composes, its keys are its own.
        guard !hasMarkedText(), let key = event.charactersIgnoringModifiers?.lowercased() else { return false }
        switch (event.modifierFlags.intersection([.command, .shift, .option, .control]), key) {
        case ([.command], "x"): cut(nil)
        case ([.command], "c"): copy(nil)
        case ([.command], "v"): paste(nil)
        case ([.command], "a"): selectAll(nil)
        case ([.command], "z"):
            if undoManager?.canUndo == true { undoManager?.undo() }
        case ([.command, .shift], "z"):
            if undoManager?.canRedo == true { undoManager?.redo() }
        default:
            return false
        }
        return true
    }
}

import AppKit
import SwiftUI

/// A single-line field for the island. AppKit rather than `TextField`, which
/// leaves no say over the first click, Esc, or the caret color in a panel that
/// is never active.
struct ReminderInputField: NSViewRepresentable {
    let placeholder: String
    /// Called on Return with the field's text; the field clears when it returns true.
    let onSubmit: (String) -> Bool

    static let font = NSFont.systemFont(ofSize: 12)

    func makeCoordinator() -> Coordinator {
        Coordinator(onSubmit: onSubmit)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = IslandTextField()
        field.delegate = context.coordinator
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = Self.font
        // Set outright: the app does not force a dark appearance, so the defaults
        // could be black on the black island.
        field.textColor = .white
        field.usesSingleLineMode = true
        field.lineBreakMode = .byClipping
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        applyPlaceholder(to: field)
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.onSubmit = onSubmit
        // Follows the interface language.
        if field.placeholderAttributedString?.string != placeholder {
            applyPlaceholder(to: field)
        }
    }

    private func applyPlaceholder(to field: NSTextField) {
        field.placeholderAttributedString = NSAttributedString(
            string: placeholder,
            attributes: [.font: Self.font, .foregroundColor: NSColor.white.withAlphaComponent(0.6)]
        )
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var onSubmit: (String) -> Bool

        init(onSubmit: @escaping (String) -> Bool) {
            self.onSubmit = onSubmit
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                // Return while an input method composes picks its candidate instead.
                guard !textView.hasMarkedText() else { return false }
                if onSubmit(textView.string) {
                    // Through the field editor, so the caret stays for the next one.
                    textView.string = ""
                    // The steps to undo were for the text just added; the next typing
                    // starts a step of its own rather than joining a discarded one.
                    textView.breakUndoCoalescing()
                    textView.undoManager?.removeAllActions()
                }
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                // Esc ends editing.
                control.window?.makeFirstResponder(nil)
                return true
            case Selector(("noop:")):
                // A ⌘ shortcut no view took as a key equivalent reaches the field
                // editor as a key press instead.
                guard let event = NSApp.currentEvent, event.type == .keyDown,
                      let field = control as? IslandTextField
                else { return false }
                return field.performEditingShortcut(event)
            default:
                return false
            }
        }
    }
}

/// The field, adjusted for a panel that is never active.
private final class IslandTextField: NSTextField {
    // The first click must place the caret, not only make the panel key.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        // The window's shared field editor, set up for this field while it edits:
        // a white caret on the black island, and undo for ⌘Z.
        if became, let editor = currentEditor() as? NSTextView {
            editor.insertionPointColor = .white
            editor.allowsUndo = true
        }
        return became
    }

    // The app has no menu bar, whose Edit menu would turn ⌘X, ⌘C, ⌘V, ⌘A, ⌘Z,
    // and ⇧⌘Z into actions, so the field maps them itself. Every view in the
    // window is offered key equivalents, the other card's field and the notes
    // editor too, so only the field whose editor has the keyboard takes them.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if performEditingShortcut(event) { return true }
        return super.performKeyEquivalent(with: event)
    }

    func performEditingShortcut(_ event: NSEvent) -> Bool {
        // While an input method composes, its keys are its own.
        guard let editor = currentEditor() as? NSTextView,
              window?.firstResponder === editor,
              !editor.hasMarkedText(),
              let key = event.charactersIgnoringModifiers?.lowercased()
        else { return false }
        switch (event.modifierFlags.intersection([.command, .shift, .option, .control]), key) {
        case ([.command], "x"): editor.cut(nil)
        case ([.command], "c"): editor.copy(nil)
        case ([.command], "v"): editor.paste(nil)
        case ([.command], "a"): editor.selectAll(nil)
        case ([.command], "z"):
            if editor.undoManager?.canUndo == true { editor.undoManager?.undo() }
        case ([.command, .shift], "z"):
            if editor.undoManager?.canRedo == true { editor.undoManager?.redo() }
        default:
            return false
        }
        return true
    }
}

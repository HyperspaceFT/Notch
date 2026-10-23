import NotchKit
import NotchUI
import Observation
import SwiftUI

/// The notes card at the size it is given, in the Notes tab or on Home. From
/// `wideThreshold` on, a list of the notes sits beside the editor; below it, a
/// pager in a one-line header steps through them.
struct NotesView: View {
    let store: NotesStore
    let focus: NotesEditorFocus
    let size: CGSize

    static let wideThreshold: CGFloat = 280
    static let listWidth: CGFloat = 140
    /// A warm note-paper yellow.
    static let tint = Color(red: 1, green: 0.8, blue: 0.3)

    var body: some View {
        NotchCard(tint: Self.tint) {
            if size.width >= Self.wideThreshold {
                HStack(alignment: .top, spacing: 10) {
                    NotesList(store: store, newNote: newNote)
                        .frame(width: Self.listWidth)
                    Rectangle()
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 1)
                    editor
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    NotesPagerHeader(store: store, newNote: newNote)
                    editor
                }
            }
        }
        .frame(width: size.width, height: size.height)
    }

    private var editor: some View {
        NoteTextView(
            text: Binding(
                get: { store.selectedNote?.text ?? "" },
                set: { store.setText($0) }
            ),
            noteID: store.selectedID,
            focusToken: focus.token
        )
        .overlay(alignment: .topLeading) {
            if store.selectedNote?.text.isEmpty ?? true {
                Text(localized(en: "Write something…", zh: "写点什么…"))
                    .font(.system(size: 12))
                    .foregroundStyle(NotchTheme.secondaryText)
                    .lineLimit(1)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func newNote() {
        store.newNote()
        focus.token &+= 1
    }
}

/// Bumped by one card's "+", so only that card's editor takes the caret when
/// the tab and the Home module are both mounted. One per card, owned by whoever
/// creates the card rather than the view (`@State` needs a macro plugin the
/// Command Line Tools do not ship).
@MainActor
@Observable
final class NotesEditorFocus {
    var token = 0
}

/// The list column of the wide card: a header with "+", then the notes.
private struct NotesList: View {
    let store: NotesStore
    let newNote: () -> Void

    /// Height of the fade at the bottom, where a list longer than the card is cut off.
    private static let fadeHeight: CGFloat = 14

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text(localized(en: "Notes", zh: "笔记"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(NotchTheme.secondaryText)
                    .lineLimit(1)
                Spacer(minLength: 0)
                NoteIconButton(symbol: "plus", label: localized(en: "New Note", zh: "新建笔记"), action: newNote)
            }
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(store.notes) { note in
                        NoteRow(note: note, isSelected: note.id == store.selectedID)
                            .onTapGesture {
                                store.select(note.id)
                            }
                            .contextMenu {
                                Button(localized(en: "Delete", zh: "删除"), role: .destructive) {
                                    store.delete(note.id)
                                }
                            }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // Room to scroll the last note clear of the fade.
                .padding(.bottom, Self.fadeHeight)
            }
            .scrollIndicators(.hidden)
            // Notes cut off at the bottom fade out instead of ending at a hard edge.
            .mask {
                VStack(spacing: 0) {
                    Color.black
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: Self.fadeHeight)
                }
            }
        }
    }
}

/// One note in the list: its title over when it last changed.
private struct NoteRow: View {
    let note: Note
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(note.title ?? localized(en: "New Note", zh: "新笔记"))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(note.title == nil ? NotchTheme.secondaryText : NotchTheme.primaryText)
                .lineLimit(1)
            Text(NotesFormat.date(note.modified, now: Date(), language: Localization.shared.language, calendar: .current))
                .font(.system(size: 10))
                .foregroundStyle(NotchTheme.secondaryText)
                .monospacedDigit()
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white.opacity(0.12))
            }
        }
        .contentShape(.rect(cornerRadius: 6))
    }
}

/// The narrow card's header: previous, "2/5", next, and "+" on the trailing side.
private struct NotesPagerHeader: View {
    let store: NotesStore
    let newNote: () -> Void

    var body: some View {
        let index = store.selectedIndex
        let count = store.notes.count
        HStack(spacing: 2) {
            NoteIconButton(symbol: "chevron.left", label: localized(en: "Previous Note", zh: "上一条笔记")) {
                store.selectPrevious()
            }
            .disabled((index ?? 0) <= 0)
            ViewThatFits(in: .horizontal) {
                Text(verbatim: "\(index.map { $0 + 1 } ?? 0)/\(count)")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(NotchTheme.secondaryText)
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
                Color.clear.frame(width: 0, height: 0)
            }
            .frame(maxWidth: .infinity)
            NoteIconButton(symbol: "chevron.right", label: localized(en: "Next Note", zh: "下一条笔记")) {
                store.selectNext()
            }
            .disabled(index.map { $0 + 1 >= count } ?? true)
            NoteIconButton(symbol: "plus", label: localized(en: "New Note", zh: "新建笔记"), action: newNote)
        }
        .contentShape(.rect)
        .contextMenu {
            if let selectedID = store.selectedID {
                Button(localized(en: "Delete", zh: "删除"), role: .destructive) {
                    store.delete(selectedID)
                }
            }
        }
    }
}

/// A small plain symbol button for the card's headers.
private struct NoteIconButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(NotchTheme.secondaryText)
                .opacity(isEnabled ? 1 : 0.4)
                .frame(width: 18, height: 18)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}

/// The list's dates in a given language on the 24-hour clock.
enum NotesFormat {
    /// "14:05" for today, else an abbreviated month and day such as "Oct 22" or "10月22日".
    static func date(_ date: Date, now: Date, language: AppLanguage, calendar: Calendar) -> String {
        if calendar.isDate(date, inSameDayAs: now) {
            let parts = calendar.dateComponents([.hour, .minute], from: date)
            return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
        }
        let style = Date.FormatStyle(
            locale: Locale(identifier: language.rawValue),
            calendar: calendar,
            timeZone: calendar.timeZone
        )
        .month(.abbreviated)
        .day()
        return date.formatted(style)
    }
}

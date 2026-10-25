import AppKit
import NotchKit

/// The app's main menu, with an Edit menu and nothing else. An accessory app
/// never shows a menu bar, but AppKit still finds ⌘X, ⌘C, ⌘V, ⌘A, ⌘Z and ⇧⌘Z
/// through the main menu; without one, the text fields of the settings and
/// sign-in windows could not cut, copy, paste, select all, or undo. Views that
/// handle these keys themselves (notes, reminders, the file shelf) get them
/// first, since the key window's views see a key equivalent before the menu.
@MainActor
enum EditMenu {
    static func install() {
        let edit = NSMenu(title: localized(en: "Edit", zh: "编辑"))
        // NSResponder declares no undo:/redo:; the field editor answers them.
        edit.addItem(withTitle: localized(en: "Undo", zh: "撤销"), action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: localized(en: "Redo", zh: "重做"), action: Selector(("redo:")), keyEquivalent: "z")
            .keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: localized(en: "Cut", zh: "剪切"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: localized(en: "Copy", zh: "拷贝"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: localized(en: "Paste", zh: "粘贴"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(
            withTitle: localized(en: "Select All", zh: "全选"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let main = NSMenu()
        // The first item is always the application menu; Edit follows it.
        main.addItem(NSMenuItem())
        let editItem = NSMenuItem()
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
    }
}

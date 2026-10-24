import Foundation

/// An entry a feature adds to the island's right-click menu (see
/// `NotchFeature.menuItems`): a button, a submenu of further entries, or a
/// divider between them.
public struct NotchMenuItem {
    public enum Kind {
        /// A button that runs the action when chosen.
        case action(@MainActor () -> Void)
        /// A submenu showing these entries.
        case submenu([NotchMenuItem])
        /// A line between entries; its title and symbol are not shown.
        case divider
    }

    /// The entry's label, e.g. `localized(en: "Timer", zh: "计时器")`.
    public var title: String
    /// SF Symbol shown before the title; `nil` shows the title alone.
    public var symbol: String?
    public var kind: Kind

    public init(title: String, symbol: String? = nil, kind: Kind) {
        self.title = title
        self.symbol = symbol
        self.kind = kind
    }

    public static func button(
        _ title: String,
        symbol: String? = nil,
        action: @escaping @MainActor () -> Void
    ) -> NotchMenuItem {
        NotchMenuItem(title: title, symbol: symbol, kind: .action(action))
    }

    public static func submenu(_ title: String, symbol: String? = nil, items: [NotchMenuItem]) -> NotchMenuItem {
        NotchMenuItem(title: title, symbol: symbol, kind: .submenu(items))
    }

    public static var divider: NotchMenuItem {
        NotchMenuItem(title: "", kind: .divider)
    }
}

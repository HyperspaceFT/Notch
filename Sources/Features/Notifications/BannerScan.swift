import Foundation

/// One element of NotificationCenter's accessibility tree, as the banner scan
/// reads it. The real tree is `AXNode`; tests build fake ones. Attributes are
/// read only when the scan needs them, so an implementation may fetch them lazily.
protocol BannerNode {
    /// Identity across reads of the same element (`CFHash` for AX elements):
    /// the walk visits each element once, and a banner without identifiers is
    /// told apart by it.
    var nodeKey: Int { get }
    var role: String? { get }
    var subrole: String? { get }
    var identifier: String? { get }
    /// "AXStackingIdentifier": the group of notifications an element stands for.
    var stackingIdentifier: String? { get }
    /// "AXValue", when it is a string.
    var value: String? { get }
    /// "AXAttributedDescription" as plain text: "<App>, <title>, <body>…".
    var attributedDescription: String? { get }
    /// "AXChildren" followed by "AXOrderedChildren"; the two may overlap.
    var children: [Self] { get }
}

/// What a scan read from one banner.
struct BannerCapture: Equatable, Sendable {
    /// The banner's identity across scans (`BannerScan.token(for:)`).
    var token: String
    /// `nodeKey` of the window the banner sits in, which parking moves.
    var windowKey: Int
    var subrole: String
    var appName: String?
    var title: String?
    var subtitle: String?
    var body: String?

    /// Whether there is anything to show for it.
    var hasContent: Bool {
        appName != nil || title != nil || subtitle != nil || body != nil
    }

    /// The token together with what the banner says. A token may stand for a
    /// whole group of notifications (a stacking identifier does), and a banner
    /// may change its text in place, so a token alone does not tell one
    /// notification from the next.
    var identity: String {
        // U+001F, the unit separator, which notification text practically never holds.
        [token, appName ?? "", title ?? "", subtitle ?? "", body ?? ""].joined(separator: "\u{1F}")
    }

    /// Alerts wait for a click (Calendar's Snooze, for one); moved off screen,
    /// one would be stranded there.
    var isParkable: Bool {
        !subrole.contains("Alert")
    }
}

/// The outcome of scanning one window of NotificationCenter.
enum WindowScan: Equatable {
    /// The Notification Center history panel (or its widget editor): what it
    /// lists are old notifications, not new banners.
    case panel
    /// A desktop widget.
    case desktopWidget
    /// More elements than `BannerScan.windowNodeLimit`; skipped rather than
    /// read in full on the main thread.
    case tooLarge
    case banners([BannerCapture])

    var isPanelOrWidget: Bool {
        switch self {
        case .panel, .desktopWidget: true
        case .tooLarge, .banners: false
        }
    }
}

/// Finds notification banners in NotificationCenter's windows. There is no API
/// for other apps' notifications; these subroles and identifiers are what the
/// banners and the history panel carry on macOS 26, and may change with macOS.
enum BannerScan {
    static let windowNodeLimit = 1_024
    static let bannerNodeLimit = 256

    static let bannerSubroles: Set<String> = [
        "AXNotificationCenterBanner",
        "AXNotificationCenterAlert",
        "AXNotificationCenterNotification",
        "AXNotificationCenterBannerWindow",
        "AXNotificationCenterAlertStack",
    ]
    static let panelSubrole = "AXNotificationCenterPanel"
    static let widgetEditorIdentifier = "widget-editor-button"
    static let desktopWidgetPrefix = "widget-local:"
    /// The history panel's list; its notification groups are buttons whose
    /// stacking identifier starts with `stackPrefix`.
    static let listItemsIdentifier = "AXNotificationListItems"
    static let stackPrefix = "stack-"
    /// Identifiers that containers share, so they tell no banner apart.
    static let sharedIdentifiers: Set<String> = [listItemsIdentifier, "widgets-overlay-view"]

    private enum TextField: String, CaseIterable {
        case title, subtitle, body, header
    }

    /// Whether `node` itself marks a panel or a desktop widget. Events from such
    /// an element need no scan.
    static func isPanelOrWidget<Node: BannerNode>(_ node: Node) -> Bool {
        if node.subrole == panelSubrole { return true }
        guard let identifier = node.identifier else { return false }
        return identifier == widgetEditorIdentifier || identifier.hasPrefix(desktopWidgetPrefix)
    }

    /// Walks `window` depth first, in order. Any panel or widget element ignores
    /// the whole window; a banner nested in another banner is part of it.
    static func scan<Node: BannerNode>(window: Node) -> WindowScan {
        var stack: [(node: Node, isInBanner: Bool, isInListItems: Bool)] = [(window, false, false)]
        var visited: Set<Int> = []
        var banners: [Node] = []
        while let entry = stack.popLast() {
            guard visited.insert(entry.node.nodeKey).inserted else { continue }
            guard visited.count <= windowNodeLimit else { return .tooLarge }
            let node = entry.node
            let subrole = node.subrole
            let identifier = node.identifier
            if subrole == panelSubrole || identifier == widgetEditorIdentifier {
                return .panel
            }
            if identifier?.hasPrefix(desktopWidgetPrefix) == true {
                return .desktopWidget
            }
            if entry.isInListItems, !entry.isInBanner, node.role == "AXButton",
               node.stackingIdentifier?.hasPrefix(stackPrefix) == true {
                return .panel
            }
            let isBanner = !entry.isInBanner && subrole.map(bannerSubroles.contains) == true
            if isBanner {
                banners.append(node)
            }
            let isInBanner = entry.isInBanner || isBanner
            let isInListItems = entry.isInListItems || identifier == listItemsIdentifier
            // Reversed onto the stack, so children are visited in their order.
            for child in node.children.reversed() {
                stack.append((child, isInBanner, isInListItems))
            }
        }
        return .banners(banners.map { capture($0, windowKey: window.nodeKey) })
    }

    /// The banner's identifier unless it is empty or shared, else its stacking
    /// identifier, else its element hash.
    static func token<Node: BannerNode>(for banner: Node) -> String {
        if let identifier = banner.identifier, !identifier.isEmpty, !sharedIdentifiers.contains(identifier) {
            return identifier
        }
        if let stacking = banner.stackingIdentifier, !stacking.isEmpty {
            return stacking
        }
        return "ax-\(banner.nodeKey)"
    }

    /// The app's name from a banner's description, "<App>, <title>, <body>…":
    /// the part before the first comma (a full-width one, too, for Chinese),
    /// without the bidi marks that wrap it.
    static func appName(fromDescription description: String?) -> String? {
        guard let description else { return nil }
        let name = description.prefix { $0 != "," && $0 != "，" }
        return trimmed(strippingBidiControls(String(name)))
    }

    /// `text` without the invisible bidi controls (U+200E, U+200F, U+202A–U+202E,
    /// U+2066–U+2069) that wrap names in right-to-left-capable labels.
    static func strippingBidiControls(_ text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.filter { scalar in
            switch scalar.value {
            case 0x200E, 0x200F, 0x202A...0x202E, 0x2066...0x2069: false
            default: true
            }
        }))
    }

    private static func capture<Node: BannerNode>(_ banner: Node, windowKey: Int) -> BannerCapture {
        var fields: [TextField: String] = [:]
        var stack = [banner]
        var visited: Set<Int> = []
        while let node = stack.popLast(), visited.count < bannerNodeLimit {
            guard visited.insert(node.nodeKey).inserted else { continue }
            if let field = node.identifier.flatMap(TextField.init(rawValue:)), fields[field] == nil,
               let text = trimmed(node.value) {
                fields[field] = text
            }
            if fields.count == TextField.allCases.count { break }
            stack.append(contentsOf: node.children.reversed())
        }
        return BannerCapture(
            token: token(for: banner),
            windowKey: windowKey,
            subrole: banner.subrole ?? "",
            appName: appName(fromDescription: banner.attributedDescription),
            // A header stands in for a missing title.
            title: fields[.title] ?? fields[.header],
            subtitle: fields[.subtitle],
            body: fields[.body]
        )
    }

    private static func trimmed(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }
}

/// The banners of the last scan, by `BannerCapture.identity`: a banner is new
/// once, in the first scan that has it, and forgotten by the first that does not.
struct SeenBanners {
    private(set) var identities: Set<String> = []

    /// Replaces the remembered identities with `current` and returns those that are new.
    mutating func update(_ current: [String]) -> Set<String> {
        let current = Set(current)
        let new = current.subtracting(identities)
        identities = current
        return new
    }
}

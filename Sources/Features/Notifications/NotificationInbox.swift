import Foundation
import Observation

/// One notification the island caught.
struct NotificationItem: Identifiable, Equatable {
    /// Unique per arrival.
    let id: String
    /// The banner's token (`BannerScan.token(for:)`), which several
    /// notifications may share.
    var token: String
    var appName: String?
    var bundleIdentifier: String?
    var appURL: URL?
    var title: String?
    var subtitle: String?
    var body: String?
    var received: Date

    init(
        id: String = UUID().uuidString,
        token: String,
        appName: String? = nil,
        bundleIdentifier: String? = nil,
        appURL: URL? = nil,
        title: String? = nil,
        subtitle: String? = nil,
        body: String? = nil,
        received: Date
    ) {
        self.id = id
        self.token = token
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.appURL = appURL
        self.title = title
        self.subtitle = subtitle
        self.body = body
        self.received = received
    }

    /// The wings' two lines: the title over the body (or the subtitle); without a
    /// title, the subtitle over the body.
    var summary: (headline: String?, detail: String?) {
        if let title {
            return (title, body ?? subtitle)
        }
        if let subtitle {
            return (subtitle, body)
        }
        return (body, nil)
    }

    /// Whether `other` says the same thing, whenever it arrived.
    func hasSameContent(as other: NotificationItem) -> Bool {
        appName == other.appName && title == other.title && subtitle == other.subtitle && body == other.body
    }
}

/// The notifications caught since launch (or since the feature was turned on),
/// newest first. Kept in memory only: never written to disk or logged.
@MainActor
@Observable
final class NotificationInbox {
    static let capacity = 30
    /// How long the same content again counts as the same notification: a banner
    /// whose elements NotificationCenter rebuilds comes back under a new token.
    static let dedupeWindow: TimeInterval = 10

    private(set) var items: [NotificationItem] = []

    func item(id: String) -> NotificationItem? {
        items.first { $0.id == id }
    }

    /// Puts `item` on top, dropping the oldest past `capacity`. Ignored (`false`)
    /// when an item with the same content arrived within `dedupeWindow` of it.
    @discardableResult
    func insert(_ item: NotificationItem) -> Bool {
        let isRepeat = items.contains { listed in
            listed.hasSameContent(as: item)
                && abs(listed.received.timeIntervalSince(item.received)) <= Self.dedupeWindow
        }
        guard !isRepeat else { return false }
        items.insert(item, at: 0)
        if items.count > Self.capacity {
            items.removeLast(items.count - Self.capacity)
        }
        return true
    }

    /// Fills in the app of items from `appName` that do not know it yet, once a
    /// slow lookup has found it.
    func setApp(bundleIdentifier: String?, url: URL, forAppNamed appName: String) {
        let key = NotificationAppResolver.key(for: appName)
        for index in items.indices where items[index].appURL == nil {
            guard let name = items[index].appName, NotificationAppResolver.key(for: name) == key else { continue }
            items[index].bundleIdentifier = bundleIdentifier
            items[index].appURL = url
        }
    }

    func remove(id: String) {
        items.removeAll { $0.id == id }
    }

    func removeAll() {
        items = []
    }
}

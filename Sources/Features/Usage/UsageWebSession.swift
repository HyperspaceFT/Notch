import Foundation
import WebKit

/// The website data the user's sign-ins live in: a persistent WebKit data store
/// of Notch's own, apart from any browser and from other WebKit use. The
/// sign-in window browses with it, and the usage requests send its cookies.
@MainActor
public final class UsageWebSession {
    public static let shared = UsageWebSession(defaults: .standard)

    static let userAgentKey = "NotchUsageUserAgent"
    /// Fixed for good: a new value would start a new, empty store and lose the sign-ins.
    static let storeIdentifier = UUID(uuidString: "6F0B7C1E-3D2A-4E8B-9A51-2C7D8E4F1B93")!

    private let defaults: UserDefaults
    /// Opened on first use, so nothing touches WebKit until a usage view or the
    /// sign-in window needs it.
    private lazy var dataStore = WKWebsiteDataStore(forIdentifier: Self.storeIdentifier)

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// The user agent the sign-in window's web view last reported. The usage
    /// requests send it, so a Cloudflare clearance cookie, which is tied to the
    /// browser that earned it, stays valid; `nil` until a page loaded there.
    var userAgent: String? {
        defaults.string(forKey: Self.userAgentKey)
    }

    func recordUserAgent(_ userAgent: String) {
        guard Self.isAcceptableUserAgent(userAgent) else { return }
        defaults.set(userAgent, forKey: Self.userAgentKey)
    }

    /// A header value: printable ASCII only (no control characters, no line
    /// breaks), and nothing absurdly long.
    static func isAcceptableUserAgent(_ userAgent: String) -> Bool {
        !userAgent.isEmpty && userAgent.unicodeScalars.count <= 512
            && userAgent.unicodeScalars.allSatisfy { (0x20...0x7E).contains($0.value) }
    }

    /// The `Cookie` header for a request to `url`: only the stored cookies a
    /// browser would send there.
    func cookieHeader(for url: URL) async -> String? {
        let cookies = await dataStore.httpCookieStore.allCookies()
        return UsageCookie.header(for: url, from: cookies.map(UsageCookie.init), now: Date())
    }

    /// Keeps the cookies a response sets, as a browser would, so sessions that
    /// roll their cookie forward stay signed in. Only cookies for the response's
    /// own host (or a domain it belongs to) are kept, whatever Foundation lets
    /// through. Stops once the calling task is cancelled, so a refresh that a
    /// sign-out cancelled does not write a cookie back after its removal.
    func store(responseHeaders headers: [String: String], for url: URL) async {
        let cookies = HTTPCookie.cookies(withResponseHeaderFields: headers, for: url)
        for cookie in cookies where Self.mayStore(domain: cookie.domain, from: url) {
            guard !Task.isCancelled else { return }
            await dataStore.httpCookieStore.setCookie(cookie)
        }
    }

    /// Whether a response from `url` may set a cookie for `domain`: by the
    /// domain rule `UsageCookie` sends cookies with, the response's host must
    /// match it.
    nonisolated static func mayStore(domain: String, from url: URL) -> Bool {
        guard let host = url.host(), !host.isEmpty, let root = URL(string: "https://\(host)/") else { return false }
        return UsageCookie(name: "", value: "", domain: domain, path: "/", isSecure: false).matches(root, now: .distantPast)
    }

    /// Removes every kind of website data for the provider's domains: cookies,
    /// storage, caches.
    func signOut(_ provider: UsageProvider) async {
        let domains = provider.signOutDomains
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        let records = await dataStore.dataRecords(ofTypes: types)
        let matching = records.filter { domains.contains($0.displayName.lowercased()) }
        if !matching.isEmpty {
            await dataStore.removeData(ofTypes: types, for: matching)
        }
        // Cookies the usage requests stored also show up as records, but are
        // removed directly too in case one escaped the record list.
        let store = dataStore.httpCookieStore
        for cookie in await store.allCookies() where Self.belongs(cookie.domain, to: domains) {
            await store.deleteCookie(cookie)
        }
    }

    /// A configuration for a sign-in web view that browses with this store.
    func makeConfiguration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore
        return configuration
    }

    private static func belongs(_ cookieDomain: String, to domains: [String]) -> Bool {
        let host = cookieDomain.lowercased().trimmingPrefix(".")
        return domains.contains { host == $0 || host.hasSuffix("." + $0) }
    }
}

import Foundation

/// The parts of a cookie that decide which requests it goes with.
struct UsageCookie: Equatable, Sendable {
    var name: String
    var value: String
    /// A leading dot sends it to the domain and its subdomains; without, only to
    /// that exact host.
    var domain: String
    var path: String
    var isSecure: Bool
    /// `nil` for a session cookie.
    var expiresDate: Date?

    init(name: String, value: String, domain: String, path: String = "/", isSecure: Bool = true, expiresDate: Date? = nil) {
        self.name = name
        self.value = value
        self.domain = domain
        self.path = path
        self.isSecure = isSecure
        self.expiresDate = expiresDate
    }

    init(_ cookie: HTTPCookie) {
        self.init(
            name: cookie.name,
            value: cookie.value,
            domain: cookie.domain,
            path: cookie.path,
            isSecure: cookie.isSecure,
            expiresDate: cookie.expiresDate
        )
    }

    /// Whether a browser would send this cookie with a request to `url` at `now`.
    func matches(_ url: URL, now: Date) -> Bool {
        guard let host = url.host()?.lowercased(), !host.isEmpty else { return false }
        if let expiresDate, expiresDate <= now { return false }
        if isSecure, url.scheme?.lowercased() != "https" { return false }
        return Self.domainMatches(domain.lowercased(), host: host) && Self.pathMatches(path, requestPath: url.path())
    }

    private static func domainMatches(_ domain: String, host: String) -> Bool {
        if domain.hasPrefix(".") {
            let bare = domain.dropFirst()
            return !bare.isEmpty && (host == bare || host.hasSuffix(domain))
        }
        return host == domain
    }

    /// RFC 6265 section 5.1.4.
    private static func pathMatches(_ cookiePath: String, requestPath: String) -> Bool {
        let cookiePath = cookiePath.isEmpty ? "/" : cookiePath
        let requestPath = requestPath.isEmpty ? "/" : requestPath
        if requestPath == cookiePath { return true }
        guard requestPath.hasPrefix(cookiePath) else { return false }
        if cookiePath.hasSuffix("/") { return true }
        return requestPath.dropFirst(cookiePath.count).first == "/"
    }

    /// The `Cookie` header for `url` from `cookies`: only those that match it,
    /// longer paths first as browsers send them; `nil` when none match.
    static func header(for url: URL, from cookies: [UsageCookie], now: Date) -> String? {
        let matching = cookies.enumerated()
            .filter { $0.element.matches(url, now: now) }
            .sorted { lhs, rhs in
                lhs.element.path.count != rhs.element.path.count
                    ? lhs.element.path.count > rhs.element.path.count
                    : lhs.offset < rhs.offset
            }
            .map(\.element)
        guard !matching.isEmpty else { return nil }
        return matching.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    }
}

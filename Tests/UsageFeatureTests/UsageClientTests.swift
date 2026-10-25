import Foundation
import Testing
@testable import UsageFeature

/// Which stored cookies go with a request, as a browser decides it (RFC 6265).
struct UsageCookieTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func header(_ url: String, _ cookies: [UsageCookie]) -> String? {
        UsageCookie.header(for: URL(string: url)!, from: cookies, now: now)
    }

    @Test func aSiteNeverGetsAnotherSitesCookies() {
        let claude = UsageCookie(name: "sessionKey", value: "secret", domain: ".claude.ai")
        #expect(header("https://claude.ai/api/organizations", [claude]) == "sessionKey=secret")
        #expect(header("https://grok.com/rest/subscriptions", [claude]) == nil)
        #expect(header("https://chatgpt.com/api/auth/session", [claude]) == nil)
        // A look-alike host is not a subdomain.
        #expect(header("https://evilclaude.ai/", [claude]) == nil)
    }

    @Test func domainCookiesMatchTheHostAndItsSubdomains() {
        let cookie = UsageCookie(name: "a", value: "1", domain: ".chatgpt.com")
        #expect(header("https://chatgpt.com/", [cookie]) == "a=1")
        #expect(header("https://sub.chatgpt.com/", [cookie]) == "a=1")
    }

    @Test func hostOnlyCookiesMatchOnlyTheirHost() {
        let cookie = UsageCookie(name: "a", value: "1", domain: "chatgpt.com")
        #expect(header("https://chatgpt.com/", [cookie]) == "a=1")
        #expect(header("https://sub.chatgpt.com/", [cookie]) == nil)
        #expect(header("https://CHATGPT.com/", [cookie]) == "a=1")
    }

    @Test func expiredCookiesAreSkipped() {
        let expired = UsageCookie(name: "old", value: "1", domain: ".grok.com", expiresDate: now.addingTimeInterval(-1))
        let valid = UsageCookie(name: "new", value: "2", domain: ".grok.com", expiresDate: now.addingTimeInterval(60))
        let session = UsageCookie(name: "session", value: "3", domain: ".grok.com", expiresDate: nil)
        #expect(header("https://grok.com/", [expired, valid, session]) == "new=2; session=3")
    }

    @Test func pathRules() {
        let api = UsageCookie(name: "api", value: "1", domain: "claude.ai", path: "/api")
        let slash = UsageCookie(name: "dir", value: "2", domain: "claude.ai", path: "/api/")
        let root = UsageCookie(name: "root", value: "3", domain: "claude.ai", path: "/")
        #expect(header("https://claude.ai/api", [api, slash, root]) == "api=1; root=3")
        // Longer paths first.
        #expect(header("https://claude.ai/api/organizations", [root, api, slash]) == "dir=2; api=1; root=3")
        #expect(header("https://claude.ai/apiary", [api, slash, root]) == "root=3")
        #expect(header("https://claude.ai/", [api]) == nil)
    }

    @Test func secureCookiesOnlyOverHTTPS() {
        let secure = UsageCookie(name: "s", value: "1", domain: "claude.ai", isSecure: true)
        let plain = UsageCookie(name: "p", value: "2", domain: "claude.ai", isSecure: false)
        #expect(header("http://claude.ai/", [secure, plain]) == "p=2")
        #expect(header("https://claude.ai/", [secure, plain]) == "s=1; p=2")
    }
}

/// How an answer is classified, following common.js (`getJson`, `postGrpcWeb`)
/// and the never-follow-redirects rule.
struct UsageResponseKindTests {
    @Test func jsonAnswers() {
        let json = UsageResponseKind.json
        #expect(json.problem(status: 200, contentType: "application/json; charset=utf-8") == nil)
        #expect(json.problem(status: 401, contentType: "text/html") == .signedOut)
        #expect(json.problem(status: 403, contentType: "application/json") == .signedOut)
        #expect(json.problem(status: 403, contentType: "text/html") == .needsVerification)
        #expect(json.problem(status: 200, contentType: "text/html") == .needsVerification)
        #expect(json.problem(status: 503, contentType: nil) == .needsVerification)
        #expect(json.problem(status: 500, contentType: "application/json") == .failed(.status(500)))
        #expect(json.problem(status: 302, contentType: nil) == .signedOut)
    }

    @Test func grpcAnswers() {
        let grpc = UsageResponseKind.grpcWeb
        #expect(grpc.problem(status: 200, contentType: "application/grpc-web+proto") == nil)
        #expect(grpc.problem(status: 403, contentType: "application/grpc-web+proto") == .signedOut)
        #expect(grpc.problem(status: 200, contentType: "application/json") == .needsVerification)
        #expect(grpc.problem(status: 404, contentType: "application/grpc-web") == .failed(.status(404)))
    }
}

/// A settings object on its own defaults domain, removed after `body`.
@MainActor
private func withSettings(_ body: (UserDefaults, () -> UsageSettings) throws -> Void) rethrows {
    let suite = "UsageSettingsTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    try body(defaults) { UsageSettings(defaults: defaults) }
}

@MainActor
struct UsageSettingsTests {
    @Test func noneShownByDefault() {
        withSettings { _, make in
            #expect(make().shownProviders.isEmpty)
        }
    }

    @Test func choiceSurvivesARelaunchInProviderOrder() {
        withSettings { defaults, make in
            let settings = make()
            settings.setProvider(.grok, shown: true)
            settings.setProvider(.claude, shown: true)
            #expect(settings.shownProviders == [.claude, .grok])
            #expect(defaults.stringArray(forKey: UsageSettings.providersKey) == ["claude", "grok"])
            #expect(make().shownProviders == [.claude, .grok])
            settings.setProvider(.claude, shown: false)
            #expect(make().shownProviders == [.grok])
        }
    }

    @Test func unknownSavedValuesAreIgnored() {
        withSettings { defaults, make in
            defaults.set(["gemini", "codex", 3, "claude"], forKey: UsageSettings.providersKey)
            #expect(make().shownProviders == [.claude, .codex])
            defaults.set("claude", forKey: UsageSettings.providersKey)
            #expect(make().shownProviders.isEmpty)
        }
    }
}

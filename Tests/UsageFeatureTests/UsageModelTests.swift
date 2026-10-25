import Foundation
import Testing
@testable import UsageFeature

/// A model whose settings and web session use their own defaults domain, with
/// no provider shown, so `refreshIfNeeded` starts no request. Removed after `body`.
@MainActor
private func withModel(_ body: (UsageModel, UserDefaults) throws -> Void) rethrows {
    let suite = "UsageModelTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let model = UsageModel(settings: UsageSettings(defaults: defaults), webSession: UsageWebSession(defaults: defaults))
    try body(model, defaults)
}

@MainActor
struct UsageModelSampleTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func aSampleEndsWhenAFreshReportWould() {
        withModel { model, _ in
            model.showSample(.reports(now: start))
            #expect(model.displayedProviders == UsageProvider.allCases)
            model.refreshIfNeeded(now: start.addingTimeInterval(299))
            #expect(model.sample != nil)
            model.refreshIfNeeded(now: start.addingTimeInterval(300))
            #expect(model.sample == nil)
            #expect(model.displayedProviders.isEmpty)
        }
    }

    @Test func aStatusSampleExpiresToo() {
        withModel { model, _ in
            model.showSample(.state(.signedOut, now: start))
            #expect(model.status(of: .claude).state == .signedOut)
            model.refreshIfNeeded(now: start.addingTimeInterval(301))
            #expect(model.status(of: .claude).state == .loading)
        }
    }

    @Test func aUserActionEndsTheSample() {
        withModel { model, _ in
            model.showSample(.state(.signedOut, now: Date()))
            model.dropSample()
            #expect(model.sample == nil)
        }
        withModel { model, _ in
            model.showSample(.reports(now: Date()))
            // Retry: a forced refresh. Stopped before its task first runs, so
            // no request goes out.
            model.refresh(.codex, force: true)
            model.stop()
            #expect(model.sample == nil)
            #expect(!model.isRefreshing(.codex))
        }
    }
}

@MainActor
struct UsageUserAgentTests {
    private static let safari = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko)"

    @Test func aNormalUserAgentIsKept() {
        withModel { _, defaults in
            let session = UsageWebSession(defaults: defaults)
            session.recordUserAgent(Self.safari)
            #expect(session.userAgent == Self.safari)
        }
    }

    @Test func unsafeValuesAreRejected() {
        withModel { _, defaults in
            let session = UsageWebSession(defaults: defaults)
            session.recordUserAgent(Self.safari)
            for value in ["", "Mozilla\r\nX-Injected: 1", "Mozilla\u{0}", "Mozilla\t5.0", "Mozilla 5.0 é", "Mozilla 🦊", String(repeating: "a", count: 513)] {
                session.recordUserAgent(value)
                #expect(session.userAgent == Self.safari)
            }
            #expect(UsageWebSession.isAcceptableUserAgent(String(repeating: "a", count: 512)))
        }
    }
}

struct UsageCookieWriteBackTests {
    private func url(_ text: String) -> URL { URL(string: text)! }

    @Test func onlyTheResponsesOwnDomainsAreStored() {
        let chatgpt = url("https://chatgpt.com/api/auth/session")
        #expect(UsageWebSession.mayStore(domain: "chatgpt.com", from: chatgpt))
        #expect(UsageWebSession.mayStore(domain: ".chatgpt.com", from: chatgpt))
        #expect(!UsageWebSession.mayStore(domain: ".openai.com", from: chatgpt))
        #expect(!UsageWebSession.mayStore(domain: "claude.ai", from: chatgpt))
        #expect(!UsageWebSession.mayStore(domain: "sub.chatgpt.com", from: chatgpt))
        #expect(UsageWebSession.mayStore(domain: ".grok.com", from: url("https://grok.com/rest/subscriptions")))
    }
}

struct CodexHeaderTests {
    @Test func accountIDHeaderOnlyWhenNonEmpty() {
        #expect(CodexUsage.usageHeaders(token: "t", accountID: "acct-1") == [
            "Authorization": "Bearer t",
            "ChatGPT-Account-Id": "acct-1",
        ])
        #expect(CodexUsage.usageHeaders(token: "t", accountID: "") == ["Authorization": "Bearer t"])
        #expect(CodexUsage.usageHeaders(token: "t", accountID: nil) == ["Authorization": "Bearer t"])
    }
}

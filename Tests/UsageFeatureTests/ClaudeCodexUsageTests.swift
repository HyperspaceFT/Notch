import Foundation
import Testing
@testable import UsageFeature

/// `JSONSerialization` output for `text`, as the client hands it to the parsers.
func json(_ text: String) throws -> Any {
    try JSONSerialization.jsonObject(with: Data(text.utf8), options: [.fragmentsAllowed])
}

/// 2026-10-25T12:00:00Z and 2026-10-30T09:00:00Z.
let sessionReset = Date(timeIntervalSince1970: 1_792_929_600)
let weeklyReset = Date(timeIntervalSince1970: 1_793_350_800)

/// Expected values follow claude.js (`parseUsage`, `planName`, `pickOrganization`).
struct ClaudeUsageTests {
    @Test func limitsMakeOneWindowPerGroupWithScopedParts() throws {
        let report = try ClaudeUsage.parseUsage(json("""
        {"limits": [
            {"kind": "rate", "group": "session", "percent": 42, "resets_at": "2026-10-25T12:00:00.250Z", "scope": null},
            {"group": "weekly", "percent": 18, "resets_at": "2026-10-30T09:00:00Z", "scope": null},
            {"group": "weekly", "percent": 74, "resets_at": "2026-10-30T09:00:00Z", "scope": {"model": {"display_name": "Fable"}}},
            {"group": "monthly", "percent": 5, "resets_at": null, "scope": null}
        ]}
        """))
        #expect(report.plan == "")
        #expect(report.windows.count == 2)
        let session = report.windows[0]
        #expect(session.duration == 18000)
        #expect(session.percent == 42)
        #expect(session.resetsAt == sessionReset.addingTimeInterval(0.25))
        #expect(session.scoped.isEmpty)
        let weekly = report.windows[1]
        #expect(weekly.duration == 604800)
        #expect(weekly.percent == 18)
        #expect(weekly.resetsAt == weeklyReset)
        #expect(weekly.scoped == [UsageScope(label: "Fable", percent: 74, resetsAt: weeklyReset)])
    }

    @Test func groupFallsBackToKindAndScopeToSurface() throws {
        let report = try ClaudeUsage.parseUsage(json("""
        {"limits": [
            {"kind": "weekly", "utilization": 10, "scope": null},
            {"kind": "weekly", "utilization": 30, "scope": {"surface": {"display_name": "Claude Code"}}},
            {"kind": "weekly", "utilization": 20, "scope": {"surface": "desktop"}},
            {"kind": "weekly", "utilization": 5, "scope": {"other": true}}
        ]}
        """))
        #expect(report.windows.count == 1)
        #expect(report.windows[0].percent == 10)
        #expect(report.windows[0].scoped.map(\.label) == ["Claude Code", "desktop", nil])
    }

    @Test func percentIsPreferredOverUtilizationAndClamped() throws {
        let report = try ClaudeUsage.parseUsage(json("""
        {"limits": [
            {"group": "session", "percent": 30, "utilization": 80, "scope": null},
            {"group": "weekly", "percent": -4, "scope": null},
            {"group": "weekly", "percent": 104, "scope": {"model": {"display_name": "Fable"}}}
        ]}
        """))
        #expect(report.windows[0].percent == 30)
        #expect(report.windows[1].percent == 0)
        #expect(report.windows[1].scoped.first?.percent == 104)
    }

    @Test func numericStringsCount() throws {
        let report = try ClaudeUsage.parseUsage(json("""
        {"five_hour": {"utilization": "42.5", "resets_at": "2026-10-25T12:00:00Z"}, "seven_day": {"utilization": "x"}}
        """))
        #expect(report.windows.map(\.percent) == [42.5, 0])
    }

    @Test func unknownGroupsFallBackToTheOlderKeys() throws {
        let report = try ClaudeUsage.parseUsage(json("""
        {"limits": [{"group": "monthly", "percent": 5}],
         "five_hour": {"utilization": 12, "resets_at": "2026-10-25T12:00:00Z"},
         "seven_day": {"utilization": 34, "resets_at": "2026-10-30T09:00:00.123456+00:00"}}
        """))
        #expect(report.windows.count == 2)
        #expect(report.windows[0] == UsageWindow(duration: 18000, percent: 12, resetsAt: sessionReset))
        #expect(report.windows[1].duration == 604800)
        #expect(report.windows[1].percent == 34)
        let reset = try #require(report.windows[1].resetsAt)
        #expect(abs(reset.timeIntervalSince(weeklyReset) - 0.123456) < 0.000_01)
    }

    @Test func nullWindowShowsZeroWithoutReset() throws {
        let report = try ClaudeUsage.parseUsage(json("""
        {"five_hour": {"utilization": 50, "resets_at": null}, "seven_day": null}
        """))
        #expect(report.windows.count == 2)
        #expect(report.windows[1] == UsageWindow(duration: 604800, percent: 0, resetsAt: nil))
        #expect(report.windows[0].resetsAt == nil)
    }

    @Test func neitherKeyMeansTheFormatChanged() throws {
        #expect(throws: UsageFetchError.failed(.formatChanged)) {
            try ClaudeUsage.parseUsage(json(#"{"something_else": {}}"#))
        }
        #expect(throws: UsageFetchError.failed(.formatChanged)) {
            try ClaudeUsage.parseUsage(json(#"{"limits": []}"#))
        }
        #expect(throws: UsageFetchError.failed(.formatChanged)) {
            try ClaudeUsage.parseUsage(json("[]"))
        }
    }

    @Test func planNames() throws {
        func plan(_ text: String) throws -> String {
            ClaudeUsage.planName(try #require(json(text) as? [String: Any]))
        }
        #expect(try plan(#"{"raven_type": "team", "rate_limit_tier": "default_claude_max_5x"}"#) == "Team")
        #expect(try plan(#"{"raven_type": "", "rate_limit_tier": "default_claude_max_5x"}"#) == "Max 5x")
        #expect(try plan(#"{"rate_limit_tier": "default_claude_max_20x", "capabilities": ["chat", "claude_pro"]}"#) == "Max 20x")
        #expect(try plan(#"{"capabilities": ["chat", "claude_max"]}"#) == "Max")
        #expect(try plan(#"{"capabilities": ["chat", "claude_pro"]}"#) == "Pro")
        #expect(try plan(#"{"capabilities": ["chat"]}"#) == "")
        #expect(try plan("{}") == "")
    }

    @Test func pickOrganizationPrefersTheChatCapableOne() throws {
        let organizations = try #require(json("""
        [{"uuid": "api", "capabilities": ["api"]}, {"uuid": "chat", "capabilities": ["chat", "claude_max"]}]
        """) as? [Any])
        #expect(ClaudeUsage.pickOrganization(organizations)?["uuid"] as? String == "chat")
        let none = try #require(json(#"[{"uuid": "first"}, {"uuid": "second", "capabilities": []}]"#) as? [Any])
        #expect(ClaudeUsage.pickOrganization(none)?["uuid"] as? String == "first")
        #expect(ClaudeUsage.pickOrganization([]) == nil)
    }
}

/// Expected values follow codex.js (`parseUsage`, `accountId`).
struct CodexUsageTests {
    private let now = Date(timeIntervalSince1970: 1_792_900_000)

    @Test func windowsFromPrimaryAndSecondary() throws {
        let report = try CodexUsage.parseUsage(json("""
        {"plan_type": "plus", "rate_limit": {
            "primary_window": {"used_percent": 76, "limit_window_seconds": 18000, "reset_at": 1792929600},
            "secondary_window": {"used_percent": "93", "limit_window_seconds": 604800, "reset_at": 1793350800000}
        }}
        """), now: now)
        #expect(report.plan == "Plus")
        #expect(report.windows == [
            UsageWindow(duration: 18000, percent: 76, resetsAt: sessionReset),
            UsageWindow(duration: 604800, percent: 93, resetsAt: weeklyReset),
        ])
    }

    @Test func resetFromAnISOStringOrSecondsAfter() throws {
        let report = try CodexUsage.parseUsage(json("""
        {"rate_limit": {
            "primary_window": {"used_percent": -3, "limit_window_seconds": 18000, "reset_at": "2026-10-25T12:00:00Z"},
            "secondary_window": {"used_percent": 10, "reset_after_seconds": 600}
        }}
        """), now: now)
        #expect(report.plan == "")
        #expect(report.windows[0].resetsAt == sessionReset)
        #expect(report.windows[0].percent == 0)
        #expect(report.windows[1].resetsAt == now.addingTimeInterval(600))
        #expect(report.windows[1].duration == nil)
    }

    @Test func unknownPlanPassesThrough() throws {
        let report = try CodexUsage.parseUsage(json("""
        {"plan_type": "pro_lite", "rate_limit": {"secondary_window": {"used_percent": 1, "limit_window_seconds": 604800}}}
        """), now: now)
        #expect(report.plan == "pro_lite")
        #expect(report.windows.count == 1)
        #expect(report.windows[0].resetsAt == nil)
    }

    @Test func noWindowsMeansTheFormatChanged() throws {
        #expect(throws: UsageFetchError.failed(.formatChanged)) {
            try CodexUsage.parseUsage(json(#"{"plan_type": "plus", "rate_limit": {}}"#), now: now)
        }
        #expect(throws: UsageFetchError.failed(.formatChanged)) {
            try CodexUsage.parseUsage(json(#"{"rate_limit": {"primary_window": null}}"#), now: now)
        }
        #expect(throws: UsageFetchError.failed(.formatChanged)) {
            try CodexUsage.parseUsage(json("{}"), now: now)
        }
    }

    /// A token whose payload carries `claims`, base64url-encoded without padding.
    private func token(_ claims: String) -> String {
        let payload = Data(claims.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "eyJhbGciOiJSUzI1NiJ9.\(payload).signature"
    }

    @Test func accountIDFromTheTokenClaim() throws {
        let claims = #"{"https://api.openai.com/auth": {"chatgpt_account_id": "acct-1?>", "user_id": "user-9"}, "sub": "x"}"#
        let session: [String: Any] = ["accessToken": token(claims), "account": ["id": "fallback"]]
        #expect(CodexUsage.accountID(session: session) == "acct-1?>")
    }

    @Test func accountIDFallsBackToTheSessionAccount() {
        let session: [String: Any] = ["accessToken": token(#"{"sub": "x"}"#), "account": ["id": "acct-2"]]
        #expect(CodexUsage.accountID(session: session) == "acct-2")
        let broken: [String: Any] = ["accessToken": "not-a-jwt", "account": ["id": "acct-3"]]
        #expect(CodexUsage.accountID(session: broken) == "acct-3")
        #expect(CodexUsage.accountID(session: ["accessToken": token("{}")]) == nil)
    }
}

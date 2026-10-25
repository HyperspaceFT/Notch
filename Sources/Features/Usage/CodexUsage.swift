import Foundation

/// Codex's usage on a ChatGPT plan, from the internal endpoints the Codex CLI
/// and chatgpt.com's usage page use:
///
///     GET /api/auth/session        → the web sign-in, with `accessToken` ({} when signed out)
///     GET /backend-api/wham/usage  → { plan_type, rate_limit: { primary_window, secondary_window } }
///       each window: { used_percent, limit_window_seconds, reset_after_seconds, reset_at }
///
/// The usage call needs ChatGPT-Account-Id, without which it answers with an
/// inaccurate total.
enum CodexUsage {
    private static let authClaim = "https://api.openai.com/auth"
    private static let planNames = [
        "free": "Free", "plus": "Plus", "pro": "Pro", "team": "Team",
        "business": "Business", "enterprise": "Enterprise", "edu": "Edu",
    ]

    /// The claims in a JWT's payload; empty when it does not decode.
    private static func jwtPayload(_ token: String) -> [String: Any] {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count > 1 else { return [:] }
        var base64 = String(parts[1]).replacing("-", with: "+").replacing("_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let data = Data(base64Encoded: base64),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return payload
    }

    /// The workspace (account) id: the access token's claim first, then the
    /// session's account. Never the user id.
    static func accountID(session: [String: Any]) -> String? {
        let token = session["accessToken"] as? String ?? ""
        if let id = (jwtPayload(token)[authClaim] as? [String: Any])?["chatgpt_account_id"] as? String {
            return id
        }
        return (session["account"] as? [String: Any])?["id"] as? String
    }

    private static func resetTime(_ window: [String: Any], now: Date) -> Date? {
        if let resetAt = UsageJSON.strictNumber(window["reset_at"]) {
            // Seconds, or milliseconds once past 1e12.
            return Date(timeIntervalSince1970: resetAt < 1e12 ? resetAt : resetAt / 1000)
        }
        if let resetAt = window["reset_at"] as? String {
            return UsageJSON.date(resetAt)
        }
        if let resetAfter = UsageJSON.strictNumber(window["reset_after_seconds"]) {
            return now.addingTimeInterval(resetAfter)
        }
        return nil
    }

    static func parseUsage(_ json: Any, now: Date) throws(UsageFetchError) -> UsageReport {
        let data = json as? [String: Any]
        let limits = data?["rate_limit"] as? [String: Any]
        let windows = [limits?["primary_window"], limits?["secondary_window"]]
            .filter { UsageJSON.isTruthy($0 ?? nil) }
            .map { value in
                let window = value as? [String: Any] ?? [:]
                let seconds = UsageJSON.numberOrZero(window["limit_window_seconds"])
                return UsageWindow(
                    duration: seconds == 0 ? nil : seconds,
                    percent: max(0, UsageJSON.numberOrZero(window["used_percent"])),
                    resetsAt: resetTime(window, now: now)
                )
            }
        guard let data, !windows.isEmpty else { throw .failed(.formatChanged) }
        let plan = (data["plan_type"] as? String).map { planNames[$0] ?? $0 } ?? ""
        return UsageReport(plan: plan, windows: windows)
    }

    /// The usage call's headers: the bearer token, and the account id unless it
    /// is missing or empty (codex.js skips a falsy id).
    static func usageHeaders(token: String, accountID: String?) -> [String: String] {
        var headers = ["Authorization": "Bearer \(token)"]
        if let accountID, !accountID.isEmpty {
            headers["ChatGPT-Account-Id"] = accountID
        }
        return headers
    }

    /// The access token lives only in this call and is never stored.
    @MainActor
    static func fetch(client: UsageClient) async throws(UsageFetchError) -> UsageReport {
        let origin = UsageProvider.codex.origin
        guard let session = try await client.json(origin.appending(path: "api/auth/session"), for: .codex) as? [String: Any],
              let token = session["accessToken"] as? String, !token.isEmpty
        else { throw .signedOut }
        let headers = usageHeaders(token: token, accountID: accountID(session: session))
        let usage = try await client.json(origin.appending(path: "backend-api/wham/usage"), for: .codex, headers: headers)
        return try parseUsage(usage, now: Date())
    }
}

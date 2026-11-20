import Foundation

/// Reads the user's Gemini quota in Antigravity from Google's Cloud Code
/// endpoint — the same `loadCodeAssist` / `fetchAvailableModels` calls the
/// Antigravity app makes — authenticated with the bearer token `GoogleAuth`
/// gets from the app's sign-in. The quota is one rolling pool shared by the
/// Gemini models, reported as a `remainingFraction`; Notch shows what is used.
///
/// The endpoint is undocumented and may change at any time; a failed read only
/// shows as such. Nothing here may log or report the token, headers, or bodies.
@MainActor
enum GoogleUsage {
    /// The Cloud Code host Antigravity's Gemini calls go to.
    nonisolated static let host = "cloudcode-pa.googleapis.com"
    /// Identifies these requests as the Antigravity client, which the endpoint
    /// requires to return the individual (free) tier and its models.
    static let userAgent = "antigravity/1.5.13 darwin/arm64"
    /// The client metadata the endpoint expects alongside the bearer token.
    static let clientMetadata: [String: Any] = [
        "ideType": "ANTIGRAVITY",
        "platform": "PLATFORM_UNSPECIFIED",
        "pluginType": "GEMINI",
    ]
    /// The largest answer read (`fetchAvailableModels` lists every model).
    static let maximumBodySize = 2_000_000

    static func fetch(auth: GoogleAuth) async throws(UsageFetchError) -> UsageReport {
        let token = try await auth.accessToken()
        // The plan is only a label: read beside the quota, and its failure is
        // swallowed so the quota still shows.
        async let plan = fetchPlan(auth: auth, token: token)
        let models: Any
        do throws(UsageFetchError) {
            models = try await call("fetchAvailableModels", auth: auth, token: token, body: ["metadata": clientMetadata])
        } catch {
            // Don't leave the plan request running once the quota has failed.
            _ = await plan
            throw error
        }
        let window = try parseQuota(models, now: Date())
        return UsageReport(plan: await plan, windows: [window])
    }

    /// `loadCodeAssist` → the current tier's display name ("Antigravity"); empty
    /// when it cannot be read, so a label never stands in the way of the quota.
    private static func fetchPlan(auth: GoogleAuth, token: String) async -> String {
        guard let json = try? await call("loadCodeAssist", auth: auth, token: token, body: ["metadata": clientMetadata]),
              let object = json as? [String: Any]
        else { return "" }
        if let tier = object["currentTier"] as? [String: Any], let name = tier["name"] as? String, !name.isEmpty {
            return name
        }
        return ""
    }

    /// The Gemini pool as a window: `100 − remainingFraction%` used, resetting at
    /// `resetTime`. The Gemini models share one pool, so the one that covers the
    /// most of them is taken (ties broken by the soonest reset). Models with no
    /// reset time (the local tab-completion models) are left out.
    static func parseQuota(_ json: Any, now: Date) throws(UsageFetchError) -> UsageWindow {
        guard let models = (json as? [String: Any])?["models"] as? [String: Any] else {
            throw .failed(.formatChanged)
        }
        struct Pool { var remaining: Double; var reset: Date; var count: Int }
        var pools: [String: Pool] = [:]
        for case let model as [String: Any] in models.values {
            let apiProvider = (model["apiProvider"] as? String ?? "").uppercased()
            let modelProvider = (model["modelProvider"] as? String ?? "").uppercased()
            guard apiProvider.contains("GOOGLE") || modelProvider.contains("GOOGLE") else { continue }
            guard let quota = model["quotaInfo"] as? [String: Any],
                  let reset = UsageJSON.date(quota["resetTime"]) else { continue }
            // proto3 omits a zero fraction, so a missing value means none left.
            let remaining = UsageJSON.numberOrZero(quota["remainingFraction"])
            let key = "\(quota["resetTime"] ?? "")|\(remaining)"
            if var pool = pools[key] {
                pool.count += 1
                pools[key] = pool
            } else {
                pools[key] = Pool(remaining: remaining, reset: reset, count: 1)
            }
        }
        guard let pool = pools.values.max(by: { lhs, rhs in
            lhs.count != rhs.count ? lhs.count < rhs.count : lhs.reset > rhs.reset
        }) else { throw .failed(.formatChanged) }
        let percent = max(0, (1 - pool.remaining) * 100)
        return UsageWindow(duration: nil, percent: percent, resetsAt: pool.reset)
    }

    /// POSTs `body` as JSON to `https://host/v1internal:<method>` with the bearer
    /// token and the Antigravity user agent, and decodes the JSON answer.
    private static func call(
        _ method: String,
        auth: GoogleAuth,
        token: String,
        body: [String: Any]
    ) async throws(UsageFetchError) -> Any {
        var request = URLRequest(url: URL(string: "https://\(host)/v1internal:\(method)")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        guard !Task.isCancelled else { throw .cancelled }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await auth.session.data(for: request)
        } catch let error as URLError where error.code == .cancelled {
            throw .cancelled
        } catch is CancellationError {
            throw .cancelled
        } catch {
            throw Task.isCancelled ? .cancelled : .failed(.network)
        }
        guard !Task.isCancelled else { throw .cancelled }
        guard let http = response as? HTTPURLResponse else { throw .failed(.network) }
        // A rejected token: forget the cached one, so a retry re-reads the
        // Antigravity sign-in and refreshes.
        if http.statusCode == 401 || http.statusCode == 403 {
            auth.forget()
            throw .signedOut
        }
        guard (200..<300).contains(http.statusCode) else { throw .failed(.status(http.statusCode)) }
        guard data.count <= maximumBodySize else { throw .failed(.formatChanged) }
        guard let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            throw .failed(.formatChanged)
        }
        return object
    }
}

import Foundation

/// The claude.ai organization whose usage is read, and its plan.
struct ClaudeOrganization: Equatable, Sendable {
    var uuid: String
    var plan: String
    var checkedAt: Date
}

/// Claude's usage, from the internal endpoints claude.ai's Settings → Usage page uses:
///
///     GET /api/organizations               → the organizations (the chat-capable one
///                                            is read), with the plan in `capabilities`
///                                            (e.g. ["chat", "claude_max"]) and
///                                            `rate_limit_tier` (e.g. "default_claude_max_5x")
///     GET /api/organizations/{uuid}/usage  → { five_hour: { utilization, resets_at },
///                                            seven_day: {...}, ...,
///                                            limits: [{ kind, group, percent, resets_at, scope }] }
///
/// Percents may exceed 100; `resets_at` is RFC 3339 or null. `limits` is the
/// newer structured list: `group` is "session" or "weekly", the entry whose
/// `scope` is null is the group's own limit, the others are parts of it (per
/// model, `scope.model.display_name`). Without `limits`, five_hour / seven_day.
enum ClaudeUsage {
    /// The organization (its id and plan) is read again after a day, so a plan
    /// change shows within one.
    static let organizationTTL: TimeInterval = 24 * 60 * 60
    static let sessionDuration: TimeInterval = 5 * 60 * 60
    static let weeklyDuration: TimeInterval = 7 * 24 * 60 * 60

    /// The groups of `limits` Notch shows; others (such as a monthly one) are
    /// left out, so the layout does not change with them.
    private static let limitGroups: [String: TimeInterval] = ["session": sessionDuration, "weekly": weeklyDuration]
    /// The older keys, without per-model parts.
    private static let windowKeys: [(String, TimeInterval)] = [("five_hour", sessionDuration), ("seven_day", weeklyDuration)]

    /// The chat-capable organization: only it has subscription usage (an
    /// API-only one does not); else the first.
    static func pickOrganization(_ organizations: [Any]) -> [String: Any]? {
        let dictionaries = organizations.compactMap { $0 as? [String: Any] }
        return dictionaries.first { ($0["capabilities"] as? [Any])?.contains { $0 as? String == "chat" } == true }
            ?? organizations.first as? [String: Any]
    }

    /// The plan's name: Team and Enterprise from `raven_type`; a personal plan
    /// from the Max multiple in `rate_limit_tier` ("default_claude_max_5x" →
    /// "Max 5x"), else `claude_max` / `claude_pro` in `capabilities`; empty when
    /// none of these says.
    static func planName(_ organization: [String: Any]) -> String {
        if let raven = organization["raven_type"] as? String, let first = raven.first {
            return first.uppercased() + raven.dropFirst()
        }
        if let tier = organization["rate_limit_tier"] as? String, let match = tier.firstMatch(of: /max_(\d+)x/) {
            return "Max \(match.1)x"
        }
        let capabilities = (organization["capabilities"] as? [Any])?.compactMap { $0 as? String } ?? []
        if capabilities.contains("claude_max") { return "Max" }
        if capabilities.contains("claude_pro") { return "Pro" }
        return ""
    }

    private static func limitPercent(_ entry: [String: Any]) -> Double {
        max(0, UsageJSON.numberOrZero(UsageJSON.coalesce(entry["percent"], entry["utilization"])))
    }

    private static func limitResetsAt(_ entry: [String: Any]) -> Date? {
        UsageJSON.isTruthy(entry["resets_at"]) ? UsageJSON.date(entry["resets_at"]) : nil
    }

    /// A part's name: the model's, else the surface's; `nil` for the fallback.
    private static func scopeLabel(_ scope: Any?) -> String? {
        let scope = scope as? [String: Any]
        let surface = scope?["surface"]
        if let name = (scope?["model"] as? [String: Any])?["display_name"] as? String, !name.isEmpty { return name }
        if let name = (surface as? [String: Any])?["display_name"] as? String, !name.isEmpty { return name }
        if let name = surface as? String, !name.isEmpty { return name }
        return nil
    }

    /// `limits` → one window per known group, its unscoped entry as the window's
    /// own limit and the rest as its parts. Malformed entries are skipped.
    private static func parseLimits(_ limits: [Any]) -> [UsageWindow] {
        var order: [String] = []
        var groups: [String: [[String: Any]]] = [:]
        for case let entry as [String: Any] in limits {
            guard let group = UsageJSON.coalesce(entry["group"], entry["kind"]) as? String,
                  limitGroups[group] != nil else { continue }
            if groups[group] == nil { order.append(group) }
            groups[group, default: []].append(entry)
        }
        return order.map { group in
            let entries = groups[group] ?? []
            let mainIndex = entries.firstIndex { !UsageJSON.isTruthy($0["scope"]) } ?? 0
            let main = entries[mainIndex]
            let scoped = entries.indices.filter { $0 != mainIndex }.map { index in
                UsageScope(
                    label: scopeLabel(entries[index]["scope"]),
                    percent: limitPercent(entries[index]),
                    resetsAt: limitResetsAt(entries[index])
                )
            }
            return UsageWindow(
                duration: limitGroups[group],
                percent: limitPercent(main),
                resetsAt: limitResetsAt(main),
                scoped: scoped
            )
        }
    }

    /// The usage answer → its windows; the plan comes from the organization.
    /// A window key present but null shows as 0% without a reset time; with
    /// neither key the format has changed.
    static func parseUsage(_ json: Any) throws(UsageFetchError) -> UsageReport {
        let data = json as? [String: Any]
        if let limits = data?["limits"] as? [Any] {
            let windows = parseLimits(limits)
            if !windows.isEmpty { return UsageReport(plan: "", windows: windows) }
        }
        let windows = windowKeys.compactMap { key, duration -> UsageWindow? in
            guard let data, let value = data[key] else { return nil }
            let entry = value as? [String: Any]
            return UsageWindow(
                duration: duration,
                percent: max(0, UsageJSON.numberOrZero(entry?["utilization"])),
                resetsAt: UsageJSON.isTruthy(entry?["resets_at"]) ? UsageJSON.date(entry?["resets_at"]) : nil
            )
        }
        guard !windows.isEmpty else { throw .failed(.formatChanged) }
        return UsageReport(plan: "", windows: windows)
    }

    /// The organization, from `cache` while it is less than a day old.
    @MainActor
    private static func organization(
        client: UsageClient,
        cache: ClaudeOrganizationCache,
        now: Date
    ) async throws(UsageFetchError) -> ClaudeOrganization {
        if let cached = cache.organization, now.timeIntervalSince(cached.checkedAt) < organizationTTL {
            return cached
        }
        let url = UsageProvider.claude.origin.appending(path: "api/organizations")
        guard let organizations = try await client.json(url, for: .claude) as? [Any], !organizations.isEmpty else {
            throw .signedOut
        }
        // It goes into the next request's path, so only an id's characters pass.
        guard let organization = pickOrganization(organizations),
              let uuid = organization["uuid"] as? String,
              !uuid.isEmpty, uuid.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") })
        else { throw .failed(.formatChanged) }
        let info = ClaudeOrganization(uuid: uuid, plan: planName(organization), checkedAt: now)
        // A sign-out that cancelled this has cleared the cache, which must stay clear.
        guard !Task.isCancelled else { throw .cancelled }
        cache.organization = info
        return info
    }

    @MainActor
    static func fetch(client: UsageClient, cache: ClaudeOrganizationCache) async throws(UsageFetchError) -> UsageReport {
        let organization = try await organization(client: client, cache: cache, now: Date())
        do {
            let url = UsageProvider.claude.origin.appending(path: "api/organizations/\(organization.uuid)/usage")
            var report = try parseUsage(await client.json(url, for: .claude))
            report.plan = organization.plan
            return report
        } catch {
            // A switch of account or organization makes the cached id useless;
            // the next refresh reads it again.
            cache.organization = nil
            throw error
        }
    }
}

/// Claude's organization, kept in memory only and dropped on any failed usage
/// read and on Sign Out.
@MainActor
final class ClaudeOrganizationCache {
    var organization: ClaudeOrganization?
}

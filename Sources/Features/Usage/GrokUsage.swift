import Foundation

/// Grok's usage on grok.com. Since June 2026 the paid plans share one weekly
/// pool (Chat, Imagine, Voice, Build, API); grok.com's Settings → Usage shows
/// the percent used, a part per product, and the weekly reset, read through a
/// gRPC-web call (protobuf, not JSON):
///
///     POST /grok_api_v2.GrokBuildBilling/GetGrokCreditsConfig (empty request)
///       → field 1 is the config: field 1 percent used (float), field 5 the
///         period's end (Timestamp), field 7 the parts (repeated) { 1: product, 2: percent };
///         the parts add up to the percent used
///
/// A free account has no config and falls back to the older per-model counts:
///
///     POST /rest/rate-limits { requestKind: "DEFAULT", modelName } →
///       { windowSizeSeconds, remainingQueries, totalQueries, waitTimeSeconds? }
///
/// The plan comes from what the plan badge reads:
///
///     GET /rest/subscriptions → { subscriptions: [{ tier: "SUBSCRIPTION_TIER_…",
///                                 status: "SUBSCRIPTION_STATUS_ACTIVE" | "…_INACTIVE" }] }
///
/// An upgraded account keeps its old plan as INACTIVE, so only ACTIVE ones
/// count; a free account has none. The endpoints and field numbers come from
/// open-source Grok usage scripts (checked 2026-10) and are just as undocumented.
enum GrokUsage {
    static let weeklyDuration: TimeInterval = 7 * 24 * 60 * 60
    /// Product numbers of the parts; an unknown one shows the fallback name.
    private static let productLabels: [Double: String] = [1: "API", 2: "Build", 4: "Chat", 5: "Imagine", 6: "Voice"]
    /// The model the free account's counts are asked for (an old endpoint; a
    /// model it no longer knows fails as a changed format).
    static let freeModel = "grok-3"
    /// Points by which the headline may differ from the parts' sum before the
    /// sum is taken instead (see `parseCreditsConfig`).
    static let sumTolerance: Double = 3
    private static let tierPrefix = "SUBSCRIPTION_TIER_"
    /// Tier → plan name, from the lowest to the highest: with several active the
    /// highest shows, as on grok.com's badge. GROK_PRO is the first SuperGrok
    /// plan; SUPER_GROK_PRO is the $300 one, SuperGrok Heavy since 2025-07 (some
    /// have seen a separate SUPER_GROK_HEAVY, so both count). An unknown tier
    /// shows its name and ranks above the known ones.
    private static let tiers: [(String, String)] = [
        ("X_BASIC", "X Basic"), ("X_PREMIUM", "X Premium"), ("X_PREMIUM_PLUS", "X Premium+"),
        ("SUPER_GROK_LITE", "SuperGrok Lite"), ("GROK_PRO", "SuperGrok"), ("SUPER_GROK_PLUS", "SuperGrok Plus"),
        ("SUPER_GROK_PRO", "SuperGrok Heavy"), ("SUPER_GROK_HEAVY", "SuperGrok Heavy"),
    ]

    /// A message's fields, or none for a value that is not a message's bytes.
    private static func fields(of value: ProtobufValue?) throws(UsageFetchError) -> [Int: [ProtobufValue]] {
        guard let bytes = value?.bytes else { return [:] }
        return try Protobuf.decodeMessage(bytes)
    }

    /// A google.protobuf.Timestamp; `nil` without seconds.
    private static func timestamp(_ value: ProtobufValue?) throws(UsageFetchError) -> Date? {
        let fields = try fields(of: value)
        guard let seconds = fields[1]?.first?.number, seconds != 0, !seconds.isNaN else { return nil }
        let nanos = fields[2]?.first?.number ?? 0
        return Date(timeIntervalSince1970: seconds + (nanos / 1e6).rounded(.down) / 1000)
    }

    /// A percent field: finite and not negative (it may pass 100 a little).
    private static func percent(_ value: ProtobufValue?) -> Double? {
        guard let number = value?.number, number.isFinite, number >= 0 else { return nil }
        return number
    }

    /// The GetGrokCreditsConfig message → the weekly window, its parts the
    /// products used, most first (left out when there is only one, which would
    /// repeat the total). `nil` when it has no config (a free account); throws
    /// when nothing in it is recognizable.
    static func parseCreditsConfig(_ payload: [UInt8]) throws(UsageFetchError) -> UsageWindow? {
        guard let config = try Protobuf.decodeMessage(payload)[1]?.first else { return nil }
        let fields: [Int: [ProtobufValue]]
        switch config {
        case .bytes(let bytes):
            // Present but empty still counts as present, and fails below.
            fields = try Protobuf.decodeMessage(bytes)
        default:
            // A number in its place: zero reads as absent, anything else as no message.
            guard let number = config.number, number != 0, !number.isNaN else { return nil }
            fields = [:]
        }
        var products: [(label: String?, percent: Double)] = []
        for value in fields[7] ?? [] {
            let entry = try self.fields(of: value)
            let label = entry[1]?.first?.number.flatMap { productLabels[$0] }
            products.append((label, percent(entry[2]?.first) ?? 0))
        }
        let headline = percent(fields[1]?.first)
        // The end is field 5's Timestamp, or field 3 of a period message in field 8.
        let period = try self.fields(of: fields[8]?.first)
        var resetsAt = try timestamp(fields[5]?.first)
        if resetsAt == nil {
            resetsAt = try timestamp(period[3]?.first)
        }
        // proto3 leaves out zero values, so only all three missing means a changed format.
        if headline == nil, products.isEmpty, resetsAt == nil { throw .failed(.formatChanged) }

        // The parts add up to the use; the headline sometimes carries what is
        // left instead, and then the parts win.
        let sum = products.reduce(0) { $0 + $1.percent }
        let total = !products.isEmpty && abs((headline ?? 0) - sum) > sumTolerance ? sum : (headline ?? 0)
        let scoped = products.enumerated()
            .filter { $0.element.percent > 0 }
            .sorted { $0.element.percent != $1.element.percent ? $0.element.percent > $1.element.percent : $0.offset < $1.offset }
            .map { UsageScope(label: $0.element.label, percent: $0.element.percent, resetsAt: nil) }
        return UsageWindow(duration: weeklyDuration, percent: total, resetsAt: resetsAt, scoped: scoped.count > 1 ? scoped : [])
    }

    /// /rest/subscriptions → the plan's name: "Free" without an active plan,
    /// empty when the answer is not recognizable, so a broken endpoint does not
    /// pass for a free account.
    static func parsePlan(_ json: Any) -> String {
        guard let subscriptions = (json as? [String: Any])?["subscriptions"] as? [Any] else { return "" }
        func rank(_ tier: String) -> Int {
            tiers.firstIndex { $0.0 == tier } ?? tiers.count
        }
        let active = subscriptions
            .compactMap { $0 as? [String: Any] }
            .filter { $0["status"] as? String == "SUBSCRIPTION_STATUS_ACTIVE" }
            .compactMap { $0["tier"] as? String }
            .map { $0.replacing(tierPrefix, with: "", maxReplacements: 1) }
            .filter { !$0.isEmpty && $0 != "INVALID" }
        guard let highest = active.enumerated().max(by: { lhs, rhs in
            // The first of equal ranks wins, as the reference's stable sort keeps it first.
            rank(lhs.element) != rank(rhs.element) ? rank(lhs.element) < rank(rhs.element) : lhs.offset > rhs.offset
        })?.element else { return "Free" }
        return tiers.first { $0.0 == highest }?.1 ?? highest
    }

    /// A free account's counts → one window (used = total − remaining).
    static func parseFreeUsage(_ json: Any, now: Date) throws(UsageFetchError) -> UsageWindow {
        let data = json as? [String: Any]
        let total = UsageJSON.number(data?["totalQueries"])
        let remaining = UsageJSON.number(data?["remainingQueries"])
        guard let data, total > 0, remaining.isFinite else { throw .failed(.formatChanged) }
        let wait = UsageJSON.number(data["waitTimeSeconds"])
        let seconds = UsageJSON.numberOrZero(data["windowSizeSeconds"])
        return UsageWindow(
            duration: seconds == 0 ? nil : seconds,
            percent: max(0, (total - remaining) / total * 100),
            resetsAt: wait > 0 ? now.addingTimeInterval(wait) : nil
        )
    }

    @MainActor
    static func fetch(client: UsageClient) async throws(UsageFetchError) -> UsageReport {
        let origin = UsageProvider.grok.origin
        // Read beside the usage; when the usage fails it is cancelled unread.
        async let plan = fetchPlan(client: client)
        let payload = try await client.grpcWeb(
            origin.appending(path: "grok_api_v2.GrokBuildBilling/GetGrokCreditsConfig"),
            for: .grok
        )
        let weekly: UsageWindow
        if let config = try parseCreditsConfig(payload) {
            weekly = config
        } else {
            let counts = try await client.json(
                origin.appending(path: "rest/rate-limits"),
                for: .grok,
                body: ["requestKind": "DEFAULT", "modelName": freeModel]
            )
            weekly = try parseFreeUsage(counts, now: Date())
        }
        return UsageReport(plan: await plan, windows: [weekly])
    }

    /// The plan is only a label: when it cannot be read (a changed endpoint, a
    /// challenge page) it stays empty and the usage shows anyway.
    @MainActor
    private static func fetchPlan(client: UsageClient) async -> String {
        guard let json = try? await client.json(UsageProvider.grok.origin.appending(path: "rest/subscriptions"), for: .grok) else {
            return ""
        }
        return parsePlan(json)
    }
}

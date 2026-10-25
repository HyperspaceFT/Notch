import Foundation
import Testing
@testable import UsageFeature

/// Builds protobuf bytes by hand, for the payloads grok.com's gRPC-web call returns.
private enum PB {
    static func varint(_ value: UInt64) -> [UInt8] {
        var value = value
        var bytes: [UInt8] = []
        repeat {
            var byte = UInt8(value & 0x7f)
            value >>= 7
            if value != 0 { byte |= 0x80 }
            bytes.append(byte)
        } while value != 0
        return bytes
    }

    static func tag(_ field: Int, _ wire: UInt64) -> [UInt8] {
        varint(UInt64(field) << 3 | wire)
    }

    static func varintField(_ field: Int, _ value: UInt64) -> [UInt8] {
        tag(field, 0) + varint(value)
    }

    static func float(_ field: Int, _ value: Float) -> [UInt8] {
        let bits = value.bitPattern
        return tag(field, 5) + (0..<4).map { UInt8(truncatingIfNeeded: bits >> (8 * $0)) }
    }

    static func message(_ field: Int, _ bytes: [UInt8]) -> [UInt8] {
        tag(field, 2) + varint(UInt64(bytes.count)) + bytes
    }

    static func timestamp(_ field: Int, seconds: UInt64, nanos: UInt64 = 0) -> [UInt8] {
        message(field, varintField(1, seconds) + (nanos == 0 ? [] : varintField(2, nanos)))
    }

    static func product(_ number: UInt64, _ percent: Float) -> [UInt8] {
        message(7, varintField(1, number) + float(2, percent))
    }

    /// The response message: the config in field 1.
    static func response(_ config: [UInt8]) -> [UInt8] {
        message(1, config)
    }
}

/// Expected values follow grok.js (`decodeMessage`, `parseCreditsConfig`,
/// `parsePlan`, `fetchFreeUsage`).
struct GrokUsageTests {
    private let end: UInt64 = 1_793_350_800

    @Test func creditsConfigWithHeadlineEndAndProducts() throws {
        let payload = PB.response(
            PB.float(1, 57)
                + PB.timestamp(5, seconds: end, nanos: 500_000_000)
                + PB.product(5, 12)
                + PB.product(4, 41)
                + PB.product(2, 0)
                + PB.product(6, 4)
        )
        let window = try #require(try GrokUsage.parseCreditsConfig(payload))
        #expect(window.duration == 604800)
        #expect(window.percent == 57)
        #expect(window.resetsAt == Date(timeIntervalSince1970: 1_793_350_800.5))
        #expect(window.scoped == [
            UsageScope(label: "Chat", percent: 41, resetsAt: nil),
            UsageScope(label: "Imagine", percent: 12, resetsAt: nil),
            UsageScope(label: "Voice", percent: 4, resetsAt: nil),
        ])
    }

    @Test func headlineFarFromThePartsGivesWayToTheirSum() throws {
        let off = PB.response(PB.float(1, 20) + PB.product(4, 41) + PB.product(5, 12) + PB.product(6, 4))
        #expect(try GrokUsage.parseCreditsConfig(off)?.percent == 57)
        // Within the tolerance the headline stands.
        let close = PB.response(PB.float(1, 59) + PB.product(4, 41) + PB.product(5, 12) + PB.product(6, 4))
        #expect(try GrokUsage.parseCreditsConfig(close)?.percent == 59)
    }

    @Test func oneProductAddsNoParts() throws {
        let payload = PB.response(PB.float(1, 30) + PB.product(4, 30) + PB.product(5, 0))
        let window = try #require(try GrokUsage.parseCreditsConfig(payload))
        #expect(window.percent == 30)
        #expect(window.scoped.isEmpty)
    }

    @Test func unknownProductHasNoName() throws {
        let payload = PB.response(PB.product(9, 10) + PB.product(4, 5))
        let window = try #require(try GrokUsage.parseCreditsConfig(payload))
        #expect(window.percent == 15)
        #expect(window.scoped.map(\.label) == [nil, "Chat"])
    }

    @Test func endFromThePeriodMessage() throws {
        let period = PB.message(8, PB.timestamp(2, seconds: end - 604800) + PB.timestamp(3, seconds: end))
        let window = try #require(try GrokUsage.parseCreditsConfig(PB.response(PB.float(1, 5) + period)))
        #expect(window.resetsAt == Date(timeIntervalSince1970: TimeInterval(end)))
    }

    @Test func absentConfigMeansAFreeAccount() throws {
        #expect(try GrokUsage.parseCreditsConfig([]) == nil)
        #expect(try GrokUsage.parseCreditsConfig(PB.varintField(2, 7)) == nil)
    }

    @Test func emptyConfigMeansTheFormatChanged() {
        #expect(throws: UsageFetchError.failed(.formatChanged)) {
            try GrokUsage.parseCreditsConfig(PB.response([]))
        }
    }

    @Test func malformedMessagesFail() {
        // A varint whose continuation bit runs off the end.
        #expect(throws: UsageFetchError.failed(.formatChanged)) {
            try Protobuf.decodeMessage([0x08, 0x80])
        }
        // Wire type 3, a group.
        #expect(throws: UsageFetchError.failed(.formatChanged)) {
            try Protobuf.decodeMessage([0x0b, 0x00])
        }
        // A length past the end.
        #expect(throws: UsageFetchError.failed(.formatChanged)) {
            try Protobuf.decodeMessage([0x0a, 0x05, 0x01])
        }
        // A fixed32 cut short.
        #expect(throws: UsageFetchError.failed(.formatChanged)) {
            try Protobuf.decodeMessage([0x0d, 0x00, 0x00])
        }
        // Eleven bytes of varint.
        #expect(throws: UsageFetchError.failed(.formatChanged)) {
            try Protobuf.decodeMessage([0x08] + Array(repeating: 0xff, count: 10) + [0x01])
        }
        // A huge length must not overflow.
        #expect(throws: UsageFetchError.failed(.formatChanged)) {
            try Protobuf.decodeMessage([0x0a] + PB.varint(UInt64.max))
        }
    }

    @Test func largeVarintsDecodeExactly() throws {
        let value: UInt64 = (1 << 40) + 5
        let fields = try Protobuf.decodeMessage(PB.varintField(3, value) + PB.varintField(3, UInt64.max))
        #expect(fields[3] == [.varint(value), .varint(UInt64.max)])
    }

    @Test func fixedValuesAreLittleEndian() throws {
        let double = 12.5.bitPattern
        let bytes = PB.tag(1, 1) + (0..<8).map { UInt8(truncatingIfNeeded: double >> (8 * $0)) } + PB.float(2, 0.25)
        let fields = try Protobuf.decodeMessage(bytes)
        #expect(fields[1] == [.fixed64(12.5)])
        #expect(fields[2] == [.fixed32(0.25)])
    }

    @Test func planNames() throws {
        func plan(_ text: String) throws -> String {
            GrokUsage.parsePlan(try json(text))
        }
        #expect(try plan("{}") == "")
        #expect(try plan(#"{"subscriptions": "x"}"#) == "")
        #expect(try plan(#"{"subscriptions": []}"#) == "Free")
        #expect(try plan(#"{"subscriptions": [{"tier": "SUBSCRIPTION_TIER_GROK_PRO", "status": "SUBSCRIPTION_STATUS_INACTIVE"}]}"#) == "Free")
        #expect(try plan("""
        {"subscriptions": [
            {"tier": "SUBSCRIPTION_TIER_SUPER_GROK_HEAVY", "status": "SUBSCRIPTION_STATUS_INACTIVE"},
            {"tier": "SUBSCRIPTION_TIER_GROK_PRO", "status": "SUBSCRIPTION_STATUS_ACTIVE"}
        ]}
        """) == "SuperGrok")
        #expect(try plan("""
        {"subscriptions": [
            {"tier": "SUBSCRIPTION_TIER_X_PREMIUM", "status": "SUBSCRIPTION_STATUS_ACTIVE"},
            {"tier": "SUBSCRIPTION_TIER_SUPER_GROK_PRO", "status": "SUBSCRIPTION_STATUS_ACTIVE"}
        ]}
        """) == "SuperGrok Heavy")
        #expect(try plan("""
        {"subscriptions": [
            {"tier": "SUBSCRIPTION_TIER_SUPER_GROK_PRO", "status": "SUBSCRIPTION_STATUS_ACTIVE"},
            {"tier": "SUBSCRIPTION_TIER_GROK_ULTRA", "status": "SUBSCRIPTION_STATUS_ACTIVE"}
        ]}
        """) == "GROK_ULTRA")
        #expect(try plan("""
        {"subscriptions": [
            {"tier": "SUBSCRIPTION_TIER_INVALID", "status": "SUBSCRIPTION_STATUS_ACTIVE"},
            {"tier": "SUBSCRIPTION_TIER_X_BASIC", "status": "SUBSCRIPTION_STATUS_ACTIVE"}
        ]}
        """) == "X Basic")
        #expect(try plan(#"{"subscriptions": [{"tier": "SUBSCRIPTION_TIER_INVALID", "status": "SUBSCRIPTION_STATUS_ACTIVE"}]}"#) == "Free")
    }

    @Test func freeUsage() throws {
        let now = Date(timeIntervalSince1970: 1_792_900_000)
        let window = try GrokUsage.parseFreeUsage(json("""
        {"windowSizeSeconds": 7200, "remainingQueries": 15, "totalQueries": 20, "waitTimeSeconds": 600}
        """), now: now)
        #expect(window == UsageWindow(duration: 7200, percent: 25, resetsAt: now.addingTimeInterval(600)))
        let noWait = try GrokUsage.parseFreeUsage(json(#"{"remainingQueries": "20", "totalQueries": "20"}"#), now: now)
        #expect(noWait == UsageWindow(duration: nil, percent: 0, resetsAt: nil))
    }

    @Test func freeUsageWithoutATotalFails() {
        #expect(throws: UsageFetchError.failed(.formatChanged)) {
            try GrokUsage.parseFreeUsage(json(#"{"remainingQueries": 0, "totalQueries": 0}"#), now: Date())
        }
        #expect(throws: UsageFetchError.failed(.formatChanged)) {
            try GrokUsage.parseFreeUsage(json(#"{"totalQueries": 10}"#), now: Date())
        }
    }
}

/// Expected values follow common.js (`postGrpcWeb`).
struct GrpcWebTests {
    private func frame(_ flags: UInt8, _ content: [UInt8]) -> [UInt8] {
        let length = UInt32(content.count)
        return [flags] + (0..<4).reversed().map { UInt8(truncatingIfNeeded: length >> (8 * $0)) } + content
    }

    private func trailers(_ text: String) -> [UInt8] {
        frame(0x80, Array(text.utf8))
    }

    @Test func dataFrameWithStatusZero() throws {
        let body = frame(0, [1, 2, 3]) + frame(0, [9]) + trailers("grpc-status: 0\r\ngrpc-message: \r\n")
        #expect(try GrpcWeb.message(from: body, headers: [:]) == [1, 2, 3])
    }

    @Test func unauthenticatedInTrailersMeansSignedOut() {
        let body = frame(0, [1]) + trailers("grpc-status:16\r\n")
        #expect(throws: UsageFetchError.signedOut) {
            try GrpcWeb.message(from: body, headers: [:])
        }
    }

    @Test func otherStatusCarriesTheDecodedMessage() {
        let body = trailers("Grpc-Status: 13\r\nGrpc-Message: bad%20thing\r\n")
        #expect(throws: UsageFetchError.failed(.server("bad thing"))) {
            try GrpcWeb.message(from: body, headers: [:])
        }
    }

    @Test func statusInHeadersWithoutFrames() {
        #expect(throws: UsageFetchError.signedOut) {
            try GrpcWeb.message(from: [], headers: ["Grpc-Status": "16"])
        }
        #expect(throws: UsageFetchError.failed(.server("denied"))) {
            try GrpcWeb.message(from: [], headers: ["grpc-status": "7", "grpc-message": "denied"])
        }
        // The trailers win over the headers.
        #expect(throws: UsageFetchError.signedOut) {
            try GrpcWeb.message(from: trailers("grpc-status: 16"), headers: ["grpc-status": "0"])
        }
    }

    @Test func noDataFrameMeansTheFormatChanged() {
        #expect(throws: UsageFetchError.failed(.formatChanged)) {
            try GrpcWeb.message(from: trailers("grpc-status: 0\r\n"), headers: [:])
        }
    }
}

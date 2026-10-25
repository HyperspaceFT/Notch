import Foundation

/// One value of a decoded protobuf field.
enum ProtobufValue: Equatable, Sendable {
    case varint(UInt64)
    /// A fixed64 field, read as a little-endian double.
    case fixed64(Double)
    /// A fixed32 field, read as a little-endian float.
    case fixed32(Float)
    /// A length-delimited field: bytes, a string, or a nested message.
    case bytes([UInt8])

    /// The value as a number, as JavaScript reads it; `nil` for bytes.
    var number: Double? {
        switch self {
        case .varint(let value): Double(value)
        case .fixed64(let value): value
        case .fixed32(let value): Double(value)
        case .bytes: nil
        }
    }

    var bytes: [UInt8]? {
        if case .bytes(let bytes) = self { return bytes }
        return nil
    }
}

/// Decodes protobuf messages without a schema, one level at a time, for the
/// few fields Grok's usage answer carries.
enum Protobuf {
    /// The longest varint: ten bytes hold 64 bits.
    static let maximumVarintLength = 10

    /// One level of `bytes`: each field number's values in order. Nested messages
    /// stay bytes, decoded again by the caller. A truncated or malformed message
    /// throws `formatChanged`.
    static func decodeMessage(_ bytes: [UInt8]) throws(UsageFetchError) -> [Int: [ProtobufValue]] {
        var fields: [Int: [ProtobufValue]] = [:]
        var position = 0
        while position < bytes.count {
            let tag = try readVarint(bytes, at: &position)
            let field = Int(tag >> 3)
            let value: ProtobufValue
            switch tag & 7 {
            case 0:
                value = .varint(try readVarint(bytes, at: &position))
            case 1:
                let raw = try readFixed(bytes, at: &position, size: 8)
                value = .fixed64(Double(bitPattern: raw))
            case 5:
                let raw = try readFixed(bytes, at: &position, size: 4)
                value = .fixed32(Float(bitPattern: UInt32(raw)))
            case 2:
                let length = try readVarint(bytes, at: &position)
                // Compared before converting, so a huge length cannot overflow.
                guard length <= UInt64(bytes.count - position) else { throw .failed(.formatChanged) }
                let end = position + Int(length)
                value = .bytes(Array(bytes[position..<end]))
                position = end
            default:
                // 3 and 4 are the long-deprecated groups; 6 and 7 do not exist.
                throw .failed(.formatChanged)
            }
            fields[field, default: []].append(value)
        }
        return fields
    }

    private static func readVarint(_ bytes: [UInt8], at position: inout Int) throws(UsageFetchError) -> UInt64 {
        var value: UInt64 = 0
        for index in 0..<maximumVarintLength {
            guard position < bytes.count else { throw .failed(.formatChanged) }
            let byte = bytes[position]
            position += 1
            value |= UInt64(byte & 0x7f) << (7 * index)
            if byte & 0x80 == 0 { return value }
        }
        throw .failed(.formatChanged)
    }

    private static func readFixed(_ bytes: [UInt8], at position: inout Int, size: Int) throws(UsageFetchError) -> UInt64 {
        guard bytes.count - position >= size else { throw .failed(.formatChanged) }
        var value: UInt64 = 0
        for offset in 0..<size {
            value |= UInt64(bytes[position + offset]) << (8 * offset)
        }
        position += size
        return value
    }
}

/// gRPC-web framing: the body is a run of frames, each a flag byte (its high
/// bit marks the trailers), a four-byte big-endian length, and the content.
enum GrpcWeb {
    static let trailersFlag: UInt8 = 0x80
    /// gRPC's UNAUTHENTICATED.
    static let unauthenticated = 16
    /// An empty message in one data frame: the request body Grok's usage call takes.
    static let emptyRequest: [UInt8] = [0, 0, 0, 0, 0]

    /// The first data frame's content. The gRPC status comes from the trailers
    /// frame, else from the response headers (an answer without frames carries
    /// it there); UNAUTHENTICATED means signed out, another error carries the
    /// server's message. `headers` are the response's, any capitalization.
    static func message(from body: [UInt8], headers: [String: String]) throws(UsageFetchError) -> [UInt8] {
        var trailers: [String: String] = [:]
        var message: [UInt8]?
        var position = 0
        while body.count - position >= 5 {
            let flags = body[position]
            let length = body[(position + 1)..<(position + 5)].reduce(0) { $0 << 8 | Int($1) }
            let start = position + 5
            let end = min(start + length, body.count)
            let frame = Array(body[start..<end])
            position = start + length
            if flags & trailersFlag != 0 {
                let text = String(decoding: frame, as: UTF8.self)
                for line in text.split(omittingEmptySubsequences: true, whereSeparator: { $0 == "\n" || $0 == "\r\n" || $0 == "\r" }) {
                    guard let colon = line.firstIndex(of: ":"), colon != line.startIndex else { continue }
                    let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
                    trailers[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                }
            } else if message == nil {
                message = frame
            }
        }
        let lowercasedHeaders = Dictionary(headers.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { first, _ in first })
        func header(_ name: String) -> String? {
            trailers[name] ?? lowercasedHeaders[name]
        }
        // A status that is not a number counts as none, as `Number()` makes it NaN.
        let status = header("grpc-status").flatMap { Int($0.trimmingCharacters(in: .whitespaces)) } ?? 0
        if status == unauthenticated { throw .signedOut }
        if status != 0 {
            let text = header("grpc-message").map { $0.removingPercentEncoding ?? $0 } ?? "gRPC \(status)"
            throw .failed(.server(text))
        }
        guard let message else { throw .failed(.formatChanged) }
        return message
    }
}

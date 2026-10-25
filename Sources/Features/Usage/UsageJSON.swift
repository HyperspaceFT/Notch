import Foundation

/// Reads values out of `JSONSerialization` output the way the reference
/// JavaScript reads them, so a number sent as a string still counts.
enum UsageJSON {
    /// `Number(value)`: NaN for a missing value, a non-numeric string, an
    /// array, or an object; 0 for null and the empty string.
    static func number(_ value: Any?) -> Double {
        switch value {
        case nil:
            return .nan
        case is NSNull:
            return 0
        case let number as NSNumber:
            return number.doubleValue
        case let string as String:
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return 0 }
            return Double(trimmed) ?? .nan
        default:
            return .nan
        }
    }

    /// `Number(value) || 0`.
    static func numberOrZero(_ value: Any?) -> Double {
        let number = number(value)
        return number.isNaN ? 0 : number
    }

    /// A JSON number proper (`typeof value === 'number'`), not a string or a Boolean.
    static func strictNumber(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, !isBoolean(number) else { return nil }
        return number.doubleValue
    }

    /// Whether JavaScript would take the value as true: not missing, null,
    /// false, 0, NaN, or the empty string.
    static func isTruthy(_ value: Any?) -> Bool {
        switch value {
        case nil, is NSNull:
            return false
        case let number as NSNumber:
            let double = number.doubleValue
            return double != 0 && !double.isNaN
        case let string as String:
            return !string.isEmpty
        default:
            return true
        }
    }

    /// `a ?? b`: `a` unless it is missing or null.
    static func coalesce(_ first: Any?, _ second: Any?) -> Any? {
        switch first {
        case nil, is NSNull: second
        default: first
        }
    }

    /// An RFC 3339 time, with or without fractional seconds. The fraction is
    /// split off and added back, since sites send anything from milliseconds to
    /// microseconds and the system parser takes only some lengths.
    static func date(_ value: Any?) -> Date? {
        guard let string = value as? String,
              let match = string.wholeMatch(of: /(\d{4}-\d{2}-\d{2}[Tt ]\d{2}:\d{2}:\d{2})(\.\d+)?([Zz]|[+-]\d{2}:?\d{2})/)
        else { return nil }
        let zone = match.3 == "z" ? "Z" : String(match.3)
        let base = match.1.replacing(/[t ]/, with: "T") + zone
        guard let date = try? Date(base, strategy: .iso8601) else { return nil }
        let fraction = match.2.flatMap { Double("0" + $0) } ?? 0
        return date.addingTimeInterval(fraction)
    }

    private static func isBoolean(_ number: NSNumber) -> Bool {
        CFGetTypeID(number) == CFBooleanGetTypeID()
    }
}

import CoreGraphics
import Foundation
import SwiftUI

/// One drawing step of a parsed SVG path, in the path's own units, every point absolute.
enum SVGPathElement: Equatable, Sendable {
    case move(CGPoint)
    case line(CGPoint)
    case quadCurve(to: CGPoint, control: CGPoint)
    case curve(to: CGPoint, control1: CGPoint, control2: CGPoint)
    case close
}

/// Path data that does not parse: an unknown command, or a command without
/// its numbers.
struct SVGPathError: Error, Equatable, Sendable {}

/// Reads SVG path data (the `d` attribute) into drawing steps, for the logos
/// Notch draws without image resources. Handles every command (M L H V C S Q T
/// A Z, absolute and relative), implicit repetition, minified numbers such as
/// "-.5.5", and arc flags written without separators ("01").
enum SVGPath {
    static func elements(_ data: String) throws(SVGPathError) -> [SVGPathElement] {
        var parser = Parser(bytes: Array(data.utf8))
        return try parser.parse()
    }

    /// The steps as a SwiftUI path, in the same units.
    static func path(_ elements: [SVGPathElement]) -> Path {
        var path = Path()
        for element in elements {
            switch element {
            case .move(let point): path.move(to: point)
            case .line(let point): path.addLine(to: point)
            case .quadCurve(let to, let control): path.addQuadCurve(to: to, control: control)
            case .curve(let to, let control1, let control2): path.addCurve(to: to, control1: control1, control2: control2)
            case .close: path.closeSubpath()
            }
        }
        return path
    }

    static func path(_ data: String) throws(SVGPathError) -> Path {
        path(try elements(data))
    }

    private struct Parser {
        let bytes: [UInt8]
        var index = 0
        var elements: [SVGPathElement] = []
        var current = CGPoint.zero
        var subpathStart = CGPoint.zero
        /// The last curve's second control point, for S and T, with whether it
        /// was a cubic (C, S) or a quadratic (Q, T) one.
        var lastControl: (point: CGPoint, isCubic: Bool)?

        init(bytes: [UInt8]) {
            self.bytes = bytes
        }

        mutating func parse() throws(SVGPathError) -> [SVGPathElement] {
            var command: UInt8?
            while true {
                skipSeparators()
                guard index < bytes.count else { break }
                let byte = bytes[index]
                if Self.isCommand(byte) {
                    command = byte
                    index += 1
                } else if command == nil || !Self.startsNumber(byte) {
                    throw SVGPathError()
                }
                guard let letter = command else { throw SVGPathError() }
                try run(letter)
                // Pairs after a move are line-tos.
                if letter == UInt8(ascii: "M") { command = UInt8(ascii: "L") }
                if letter == UInt8(ascii: "m") { command = UInt8(ascii: "l") }
                if letter == UInt8(ascii: "Z") || letter == UInt8(ascii: "z") { command = nil }
            }
            return elements
        }

        private mutating func run(_ letter: UInt8) throws(SVGPathError) {
            let relative = letter >= UInt8(ascii: "a")
            let base = relative ? current : .zero
            func offset(_ point: CGPoint) -> CGPoint {
                CGPoint(x: point.x + base.x, y: point.y + base.y)
            }
            switch letter | 0x20 {
            case UInt8(ascii: "m"):
                let point = offset(try pair())
                elements.append(.move(point))
                current = point
                subpathStart = point
                lastControl = nil
            case UInt8(ascii: "l"):
                lineTo(offset(try pair()))
            case UInt8(ascii: "h"):
                let x = try number()
                lineTo(CGPoint(x: relative ? current.x + x : x, y: current.y))
            case UInt8(ascii: "v"):
                let y = try number()
                lineTo(CGPoint(x: current.x, y: relative ? current.y + y : y))
            case UInt8(ascii: "c"):
                let control1 = offset(try pair())
                let control2 = offset(try pair())
                curveTo(offset(try pair()), control1, control2)
            case UInt8(ascii: "s"):
                let control2 = offset(try pair())
                let end = offset(try pair())
                curveTo(end, reflected(cubic: true), control2)
            case UInt8(ascii: "q"):
                let control = offset(try pair())
                quadTo(offset(try pair()), control)
            case UInt8(ascii: "t"):
                quadTo(offset(try pair()), reflected(cubic: false))
            case UInt8(ascii: "a"):
                let rx = try number()
                let ry = try number()
                let rotation = try number()
                let large = try flag()
                let sweep = try flag()
                arcTo(offset(try pair()), rx: rx, ry: ry, rotation: rotation, large: large, sweep: sweep)
            case UInt8(ascii: "z"):
                elements.append(.close)
                current = subpathStart
                lastControl = nil
            default:
                throw SVGPathError()
            }
        }

        private mutating func lineTo(_ point: CGPoint) {
            elements.append(.line(point))
            current = point
            lastControl = nil
        }

        private mutating func curveTo(_ end: CGPoint, _ control1: CGPoint, _ control2: CGPoint) {
            elements.append(.curve(to: end, control1: control1, control2: control2))
            current = end
            lastControl = (control2, true)
        }

        private mutating func quadTo(_ end: CGPoint, _ control: CGPoint) {
            elements.append(.quadCurve(to: end, control: control))
            current = end
            lastControl = (control, false)
        }

        /// The last control point mirrored through the current point when the
        /// last curve was of the same kind; else the current point.
        private func reflected(cubic: Bool) -> CGPoint {
            guard let lastControl, lastControl.isCubic == cubic else { return current }
            return CGPoint(x: 2 * current.x - lastControl.point.x, y: 2 * current.y - lastControl.point.y)
        }

        /// An elliptical arc as cubic Béziers, per the SVG implementation notes
        /// (endpoint to center parameterization, section B.2.4 of SVG 2).
        private mutating func arcTo(_ end: CGPoint, rx: CGFloat, ry: CGFloat, rotation: CGFloat, large: Bool, sweep: Bool) {
            let start = current
            guard start != end else {
                lastControl = nil
                return
            }
            var rx = abs(rx)
            var ry = abs(ry)
            guard rx > 0, ry > 0 else {
                lineTo(end)
                return
            }
            let phi = rotation * .pi / 180
            let cosPhi = cos(phi)
            let sinPhi = sin(phi)
            let dx = (start.x - end.x) / 2
            let dy = (start.y - end.y) / 2
            let x1 = cosPhi * dx + sinPhi * dy
            let y1 = -sinPhi * dx + cosPhi * dy
            // Radii too small to reach the end are scaled up just enough.
            let lambda = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
            if lambda > 1 {
                rx *= lambda.squareRoot()
                ry *= lambda.squareRoot()
            }
            let numerator = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
            let denominator = rx * rx * y1 * y1 + ry * ry * x1 * x1
            let factor = (denominator == 0 ? 0 : max(0, numerator / denominator)).squareRoot() * (large == sweep ? -1 : 1)
            let cx1 = factor * rx * y1 / ry
            let cy1 = -factor * ry * x1 / rx
            let center = CGPoint(
                x: cosPhi * cx1 - sinPhi * cy1 + (start.x + end.x) / 2,
                y: sinPhi * cx1 + cosPhi * cy1 + (start.y + end.y) / 2
            )
            func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
                atan2(ux * vy - uy * vx, ux * vx + uy * vy)
            }
            let theta = angle(1, 0, (x1 - cx1) / rx, (y1 - cy1) / ry)
            var delta = angle((x1 - cx1) / rx, (y1 - cy1) / ry, (-x1 - cx1) / rx, (-y1 - cy1) / ry)
            if !sweep, delta > 0 { delta -= 2 * .pi }
            if sweep, delta < 0 { delta += 2 * .pi }

            func point(_ a: CGFloat) -> CGPoint {
                CGPoint(
                    x: center.x + rx * cos(a) * cosPhi - ry * sin(a) * sinPhi,
                    y: center.y + rx * cos(a) * sinPhi + ry * sin(a) * cosPhi
                )
            }
            func derivative(_ a: CGFloat) -> CGPoint {
                CGPoint(
                    x: -rx * sin(a) * cosPhi - ry * cos(a) * sinPhi,
                    y: -rx * sin(a) * sinPhi + ry * cos(a) * cosPhi
                )
            }
            let count = max(1, Int((abs(delta) / (.pi / 2)).rounded(.up)))
            let step = delta / CGFloat(count)
            let handle = 4.0 / 3.0 * tan(step / 4)
            var from = start
            for segment in 0..<count {
                let a1 = theta + step * CGFloat(segment)
                let a2 = a1 + step
                let d1 = derivative(a1)
                let d2 = derivative(a2)
                // The last segment ends exactly at the endpoint, not at a rounded copy.
                let to = segment == count - 1 ? end : point(a2)
                let control1 = CGPoint(x: from.x + handle * d1.x, y: from.y + handle * d1.y)
                let control2 = CGPoint(x: to.x - handle * d2.x, y: to.y - handle * d2.y)
                elements.append(.curve(to: to, control1: control1, control2: control2))
                from = to
            }
            current = end
            lastControl = nil
        }

        // MARK: Tokens

        private static func isCommand(_ byte: UInt8) -> Bool {
            "MmLlHhVvCcSsQqTtAaZz".utf8.contains(byte)
        }

        private static func startsNumber(_ byte: UInt8) -> Bool {
            isDigit(byte) || byte == UInt8(ascii: "-") || byte == UInt8(ascii: "+") || byte == UInt8(ascii: ".")
        }

        private static func isDigit(_ byte: UInt8) -> Bool {
            byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9")
        }

        private mutating func skipSeparators() {
            while index < bytes.count, [UInt8(ascii: " "), UInt8(ascii: ","), 0x09, 0x0A, 0x0D, 0x0C].contains(bytes[index]) {
                index += 1
            }
        }

        private mutating func pair() throws(SVGPathError) -> CGPoint {
            let x = try number()
            let y = try number()
            return CGPoint(x: x, y: y)
        }

        /// An arc flag: one "0" or "1", which needs no separator after it.
        private mutating func flag() throws(SVGPathError) -> Bool {
            skipSeparators()
            guard index < bytes.count else { throw SVGPathError() }
            switch bytes[index] {
            case UInt8(ascii: "0"):
                index += 1
                return false
            case UInt8(ascii: "1"):
                index += 1
                return true
            default:
                throw SVGPathError()
            }
        }

        /// A number: a sign, digits with at most one point, an exponent. A second
        /// point or a sign starts the next number, as minified data relies on.
        private mutating func number() throws(SVGPathError) -> CGFloat {
            skipSeparators()
            let start = index
            if index < bytes.count, bytes[index] == UInt8(ascii: "-") || bytes[index] == UInt8(ascii: "+") {
                index += 1
            }
            var digits = 0
            while index < bytes.count, Self.isDigit(bytes[index]) {
                index += 1
                digits += 1
            }
            if index < bytes.count, bytes[index] == UInt8(ascii: ".") {
                index += 1
                while index < bytes.count, Self.isDigit(bytes[index]) {
                    index += 1
                    digits += 1
                }
            }
            guard digits > 0 else {
                index = start
                throw SVGPathError()
            }
            if index < bytes.count, bytes[index] == UInt8(ascii: "e") || bytes[index] == UInt8(ascii: "E") {
                var lookahead = index + 1
                if lookahead < bytes.count, bytes[lookahead] == UInt8(ascii: "-") || bytes[lookahead] == UInt8(ascii: "+") {
                    lookahead += 1
                }
                if lookahead < bytes.count, Self.isDigit(bytes[lookahead]) {
                    index = lookahead
                    while index < bytes.count, Self.isDigit(bytes[index]) {
                        index += 1
                    }
                }
            }
            guard let value = Double(String(decoding: bytes[start..<index], as: UTF8.self)) else { throw SVGPathError() }
            return CGFloat(value)
        }
    }
}

/// An SVG path drawn in a `viewBox` square, scaled uniformly into the rect and centered.
struct SVGShape: Shape {
    let path: Path
    var viewBox: CGFloat = 24

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / viewBox
        let transform = CGAffineTransform(
            translationX: rect.midX - viewBox * scale / 2,
            y: rect.midY - viewBox * scale / 2
        )
        .scaledBy(x: scale, y: scale)
        return path.applying(transform)
    }
}

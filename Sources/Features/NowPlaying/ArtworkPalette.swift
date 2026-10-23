import Foundation

/// A color as hue, saturation, and brightness, each 0…1.
struct HSBColor: Sendable, Equatable {
    var hue: Double
    var saturation: Double
    var brightness: Double
}

/// The two colors the pulse icon is painted in, picked from the cover.
struct Palette: Sendable, Equatable {
    var primary: HSBColor
    var secondary: HSBColor
}

enum ArtworkPalette {
    static let bucketCount = 12
    /// Below these a pixel counts as gray or black and casts no vote.
    static let minimumSaturation = 0.18
    static let minimumBrightness = 0.15
    /// Limits for drawing on the black island: never dim, never neon.
    static let displayMinimumBrightness = 0.8
    static let displayMaximumSaturation = 0.85

    /// The cover's dominant hue and a second one at least two buckets away, from
    /// premultiplied RGBA bytes, as a bitmap context draws them (a small image,
    /// about 20×20, is plenty; opaque pixels are the same either way).
    static func extract(fromRGBA bytes: [UInt8], width: Int, height: Int) -> Palette {
        var buckets = [Bucket](repeating: Bucket(), count: bucketCount)
        let pixelCount = min(width * height, bytes.count / 4)
        for pixel in 0..<max(pixelCount, 0) {
            let offset = pixel * 4
            let alpha = Double(bytes[offset + 3]) / 255
            guard alpha > 0 else { continue }
            let scale = 1 / alpha
            let red = min(Double(bytes[offset]) / 255 * scale, 1)
            let green = min(Double(bytes[offset + 1]) / 255 * scale, 1)
            let blue = min(Double(bytes[offset + 2]) / 255 * scale, 1)
            let color = hsb(red: red, green: green, blue: blue)
            guard color.saturation >= minimumSaturation, color.brightness >= minimumBrightness else { continue }
            let weight = color.saturation * color.brightness * alpha
            let index = min(Int(color.hue * Double(bucketCount)), bucketCount - 1)
            buckets[index].add(color, weight: weight)
        }

        let ranked = buckets.indices.filter { buckets[$0].weight > 0 }.sorted { buckets[$0].weight > buckets[$1].weight }
        let totalWeight = ranked.reduce(0) { $0 + buckets[$1].weight }
        // Hardly any colored pixel: a black-and-white cover gets light grays.
        guard let first = ranked.first, totalWeight >= 0.02 * Double(max(pixelCount, 1)) else {
            return Palette(
                primary: HSBColor(hue: 0, saturation: 0, brightness: 0.92),
                secondary: HSBColor(hue: 0, saturation: 0, brightness: 0.8)
            )
        }
        let primary = buckets[first].mean
        let secondary: HSBColor
        if let second = ranked.dropFirst().first(where: { bucketDistance($0, first) >= 2 }) {
            secondary = buckets[second].mean
        } else {
            secondary = HSBColor(
                hue: (primary.hue + 25.0 / 360).truncatingRemainder(dividingBy: 1),
                saturation: primary.saturation * 0.8,
                brightness: min(primary.brightness + 0.15, 1)
            )
        }
        return Palette(primary: forDisplay(primary), secondary: forDisplay(secondary))
    }

    static func hsb(red: Double, green: Double, blue: Double) -> HSBColor {
        let maximum = max(red, green, blue)
        let minimum = min(red, green, blue)
        let delta = maximum - minimum
        var hue = 0.0
        if delta > 0 {
            if maximum == red {
                hue = ((green - blue) / delta).truncatingRemainder(dividingBy: 6)
            } else if maximum == green {
                hue = (blue - red) / delta + 2
            } else {
                hue = (red - green) / delta + 4
            }
            hue /= 6
            if hue < 0 { hue += 1 }
        }
        return HSBColor(hue: hue, saturation: maximum > 0 ? delta / maximum : 0, brightness: maximum)
    }

    private static func forDisplay(_ color: HSBColor) -> HSBColor {
        HSBColor(
            hue: color.hue,
            saturation: min(color.saturation, displayMaximumSaturation),
            brightness: max(color.brightness, displayMinimumBrightness)
        )
    }

    /// Distance between two buckets around the hue circle.
    private static func bucketDistance(_ a: Int, _ b: Int) -> Int {
        let distance = abs(a - b)
        return min(distance, bucketCount - distance)
    }

    private struct Bucket {
        var weight = 0.0
        // Hue is averaged on the circle, so reds either side of 0 do not average to cyan.
        var hueX = 0.0
        var hueY = 0.0
        var saturation = 0.0
        var brightness = 0.0

        mutating func add(_ color: HSBColor, weight: Double) {
            self.weight += weight
            hueX += cos(2 * .pi * color.hue) * weight
            hueY += sin(2 * .pi * color.hue) * weight
            saturation += color.saturation * weight
            brightness += color.brightness * weight
        }

        var mean: HSBColor {
            var hue = atan2(hueY, hueX) / (2 * .pi)
            if hue < 0 { hue += 1 }
            return HSBColor(hue: hue, saturation: saturation / weight, brightness: brightness / weight)
        }
    }
}

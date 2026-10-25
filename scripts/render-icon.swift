// Draws an SVG into the PNGs of a macOS .iconset, each at its own pixel size.
// Usage: swift scripts/render-icon.swift <icon.svg> <dir.iconset>
import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    FileHandle.standardError.write(Data("usage: render-icon.swift <icon.svg> <dir.iconset>\n".utf8))
    exit(64)
}
let svgURL = URL(fileURLWithPath: arguments[1])
let iconsetURL = URL(fileURLWithPath: arguments[2], isDirectory: true)

// AppKit reads SVG natively (no Xcode or third-party renderer needed).
guard let image = NSImage(contentsOf: svgURL) else {
    FileHandle.standardError.write(Data("error: cannot read \(svgURL.path) as an image\n".utf8))
    exit(1)
}

let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        guard let context = CGContext(
            data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { exit(1) }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
        NSGraphicsContext.restoreGraphicsState()

        let rep = NSBitmapImageRep(cgImage: context.makeImage()!)
        rep.size = NSSize(width: points, height: points)
        let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        do {
            try rep.representation(using: .png, properties: [:])!.write(to: iconsetURL.appendingPathComponent(name))
        } catch {
            FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }
}

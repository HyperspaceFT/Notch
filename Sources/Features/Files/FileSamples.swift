import AppKit
import ImageIO
import NotchKit
import UniformTypeIdentifiers

/// The files the Debug pane puts on the shelf (`FilesFeature.debugItems`): a few
/// small ones of different kinds, written to a folder of their own in the
/// temporary directory so that nothing of the user's is involved.
@MainActor
enum FileSamples {
    static let folderName = "Notch Debug Files"

    static var directory: URL {
        FileManager.default.temporaryDirectory.appending(path: folderName, directoryHint: .isDirectory)
    }

    /// Writes the files anew into `directory` and returns their URLs; empty when
    /// the folder cannot be written. A file that fails to write is left out.
    static func create(in directory: URL = FileSamples.directory) -> [URL] {
        let manager = FileManager.default
        try? manager.removeItem(at: directory)
        guard (try? manager.createDirectory(at: directory, withIntermediateDirectories: true)) != nil else { return [] }

        let folder = directory.appending(path: localized(en: "Sample Folder", zh: "示例文件夹"), directoryHint: .isDirectory)
        let note = localized(en: "A sample file for checking the shelf.\n", zh: "用于检查文件暂存区的示例文件。\n")
        let written: [URL?] = [
            writeText(note, to: directory.appending(path: localized(en: "Sample Note.txt", zh: "示例文本.txt"))),
            writePNG(to: directory.appending(path: localized(en: "Sample Image.png", zh: "示例图片.png"))),
            writePDF(to: directory.appending(path: localized(en: "Sample Document.pdf", zh: "示例文档.pdf"))),
            (try? manager.createDirectory(at: folder, withIntermediateDirectories: true)) == nil ? nil : folder,
        ]
        return written.compactMap { $0 }
    }

    /// Deletes the folder and everything in it.
    static func delete(in directory: URL = FileSamples.directory) {
        try? FileManager.default.removeItem(at: directory)
    }

    private static func writeText(_ text: String, to url: URL) -> URL? {
        (try? text.write(to: url, atomically: true, encoding: .utf8)) == nil ? nil : url
    }

    /// A 128-point square with a diagonal gradient.
    private static func writePNG(to url: URL) -> URL? {
        let side = 128
        guard
            let context = CGContext(
                data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ),
            let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [NSColor.systemBlue.cgColor, NSColor.systemPink.cgColor] as CFArray,
                locations: [0, 1]
            ),
            let image = {
                context.drawLinearGradient(
                    gradient, start: .zero, end: CGPoint(x: side, y: side), options: []
                )
                return context.makeImage()
            }(),
            let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? url : nil
    }

    /// A one-page document with a line of text.
    private static func writePDF(to url: URL) -> URL? {
        var box = CGRect(x: 0, y: 0, width: 240, height: 160)
        guard let context = CGContext(url as CFURL, mediaBox: &box, nil) else { return nil }
        context.beginPDFPage(nil)
        let graphics = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        NSAttributedString(
            string: localized(en: "Sample Document", zh: "示例文档"),
            attributes: [.font: NSFont.systemFont(ofSize: 20), .foregroundColor: NSColor.black]
        ).draw(at: NSPoint(x: 24, y: 70))
        NSGraphicsContext.restoreGraphicsState()
        context.endPDFPage()
        context.closePDF()
        return url
    }
}

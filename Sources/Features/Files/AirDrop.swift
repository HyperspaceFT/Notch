import AppKit
import NotchKit
import NotchUI
import Observation
import SwiftUI
import UniformTypeIdentifiers

/// Drop zone that sends the dropped files with AirDrop.
struct AirDropZone: View {
    @Bindable var target: DropTarget

    var body: some View {
        // AirDrop's own blue.
        NotchCard(tint: .blue) {
            VStack(spacing: 6) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 26, weight: .regular))
                    .foregroundStyle(Color.blue.gradient)
                Text(localized(en: "AirDrop", zh: "隔空投送"))
                    .font(.system(size: 12, weight: .semibold))
                Text(localized(en: "Drop here to send", zh: "拖到这里发送"))
                    .font(.system(size: 10))
                    .foregroundStyle(NotchTheme.secondaryText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .dropZone(isTargeted: target.isTargeted)
        .onDrop(of: [.fileURL], isTargeted: $target.isTargeted) { providers in
            Task { @MainActor in
                AirDrop.send(await loadFileURLs(from: providers))
            }
            return true
        }
    }
}

@MainActor
enum AirDrop {
    static func send(_ urls: [URL]) {
        guard
            !urls.isEmpty,
            let service = NSSharingService(named: .sendViaAirDrop),
            service.canPerform(withItems: urls)
        else {
            NSSound.beep()
            return
        }
        // This accessory app is never active on its own, and the AirDrop window the
        // service opens only comes to the front while its app is active.
        NSApp.activate()
        service.perform(withItems: urls)
    }
}

/// Loads the URLs behind dropped item providers, in drop order. Failed loads are skipped.
@MainActor
func loadFileURLs(from providers: [NSItemProvider]) async -> [URL] {
    var urls: [URL] = []
    for provider in providers {
        let url: URL? = await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                continuation.resume(returning: url)
            }
        }
        if let url {
            urls.append(url)
        }
    }
    return urls
}

/// Whether a drag is currently over a drop zone. Owned by the feature rather than
/// the view (`@State` needs a macro plugin the Command Line Tools do not ship).
@MainActor
@Observable
final class DropTarget {
    var isTargeted = false
}

extension View {
    /// The dashed border of a drop target, highlighted while a drag is over it.
    func dropZone(isTargeted: Bool) -> some View {
        overlay {
            let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
            shape
                .fill(.white.opacity(isTargeted ? 0.08 : 0))
                .overlay {
                    shape.strokeBorder(
                        .white.opacity(isTargeted ? 0.55 : 0.15),
                        style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                    )
                }
                .allowsHitTesting(false)
        }
        .animation(.snappy(duration: 0.2), value: isTargeted)
    }
}

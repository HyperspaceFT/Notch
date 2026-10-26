import AppKit

/// The app a notification came from.
struct ResolvedApp: Equatable, Sendable {
    var bundleIdentifier: String?
    var url: URL
}

/// Finds the app behind a banner from the only thing the banner says about it:
/// its displayed, localized name. Running apps are checked on every lookup;
/// otherwise the application folders are searched once per name, off the main
/// thread, and the outcome (a miss too) is kept for the rest of the launch.
@MainActor
final class NotificationAppResolver {
    /// Called when a search that `resolve` started finds the app, with the name
    /// it was asked for.
    var onResolved: (@MainActor (String, ResolvedApp) -> Void)?

    /// Search outcomes by `key(for:)`; `.some(nil)` is a miss.
    private var searched: [String: ResolvedApp?] = [:]
    private var searching: Set<String> = []
    private var icons: [URL: NSImage] = [:]

    /// The app named `name`, if a running app has that name or an earlier search
    /// found it. Otherwise starts a search, once per name, and returns `nil`;
    /// `onResolved` reports what the search finds.
    func resolve(_ name: String) -> ResolvedApp? {
        let key = Self.key(for: name)
        guard !key.isEmpty else { return nil }
        if let running = Self.runningApp(key: key) {
            return running
        }
        if let outcome = searched[key] {
            return outcome
        }
        guard searching.insert(key).inserted else { return nil }
        Task { [weak self] in
            let found = await Task.detached(priority: .utility) {
                Self.searchApplicationFolders(key: key, name: name)
            }.value
            guard let self else { return }
            searching.remove(key)
            let app = found.map(Self.normalized)
            searched[key] = .some(app)
            if let app {
                onResolved?(name, app)
            }
        }
        return nil
    }

    /// The app's icon, or `nil` while the app is not known.
    func icon(for url: URL?) -> NSImage? {
        guard let url else { return nil }
        if let icon = icons[url] { return icon }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icons[url] = icon
        return icon
    }

    /// Brings the app forward: the running copy if there is one, else launches it.
    /// Opening the app's bundle does both. `activate()` would not: Notch is an
    /// accessory app that is almost never active, and macOS lets only the active
    /// app hand activation over. `false` when there is no app to open; whether
    /// the launch itself succeeds is only known later and not reported.
    @discardableResult
    func open(bundleIdentifier: String?, url: URL?) -> Bool {
        let running = bundleIdentifier.flatMap { identifier in
            NSRunningApplication.runningApplications(withBundleIdentifier: identifier).first { !$0.isTerminated }
        }
        guard let target = running?.bundleURL
            ?? url
            ?? bundleIdentifier.flatMap(NSWorkspace.shared.urlForApplication(withBundleIdentifier:))
        else { return false }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: target, configuration: configuration)
        return true
    }

    /// How names are compared: without bidi controls and surrounding whitespace,
    /// case-insensitively.
    nonisolated static func key(for name: String) -> String {
        BannerScan.strippingBidiControls(name).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// The app a helper or web content process belongs to: `com.apple.WebKit.*`
    /// and `com.apple.Safari.*` are Safari's, and anything from a "helper"
    /// component on is dropped (`com.google.Chrome.helper` is Chrome).
    nonisolated static func normalizedBundleIdentifier(_ identifier: String) -> String {
        let lowercased = identifier.lowercased()
        if lowercased.hasPrefix("com.apple.webkit.") || lowercased.hasPrefix("com.apple.safari.") {
            return "com.apple.Safari"
        }
        let components = identifier.split(separator: ".", omittingEmptySubsequences: false)
        guard let helper = components.firstIndex(where: { $0.lowercased() == "helper" }), helper > 0 else {
            return identifier
        }
        return components[..<helper].joined(separator: ".")
    }

    /// Normalizes the bundle identifier, and moves to the app it names when that changed it.
    private static func normalized(_ app: ResolvedApp) -> ResolvedApp {
        guard let identifier = app.bundleIdentifier else { return app }
        let normalized = normalizedBundleIdentifier(identifier)
        guard normalized != identifier else { return app }
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: normalized) ?? app.url
        return ResolvedApp(bundleIdentifier: normalized, url: url)
    }

    /// The running app with that name, preferring regular apps (with a Dock icon)
    /// over agents, then the oldest process.
    private static func runningApp(key: String) -> ResolvedApp? {
        let best = NSWorkspace.shared.runningApplications
            .filter { app in
                !app.isTerminated && app.localizedName.map { Self.key(for: $0) == key } == true
            }
            .min { lhs, rhs in
                let lhsRegular = lhs.activationPolicy == .regular
                let rhsRegular = rhs.activationPolicy == .regular
                if lhsRegular != rhsRegular { return lhsRegular }
                return lhs.processIdentifier < rhs.processIdentifier
            }
        guard let best, let url = best.bundleURL else { return nil }
        return normalized(ResolvedApp(bundleIdentifier: best.bundleIdentifier, url: url))
    }

    /// `<name>.app` or `<name without spaces>.app` in an application folder (or
    /// its Utilities folder), else
    /// any app there whose localized name, display name, or bundle name matches.
    /// Reads the disk, so it runs off the main thread.
    private nonisolated static func searchApplicationFolders(key: String, name: String) -> ResolvedApp? {
        let fileManager = FileManager.default
        let folders = [
            URL(filePath: "/Applications"),
            URL(filePath: "/Applications/Utilities"),
            fileManager.homeDirectoryForCurrentUser.appending(path: "Applications"),
            URL(filePath: "/System/Applications"),
            URL(filePath: "/System/Applications/Utilities"),
        ]
        let trimmed = BannerScan.strippingBidiControls(name).trimmingCharacters(in: .whitespacesAndNewlines)
        let fileNames = [trimmed, trimmed.replacingOccurrences(of: " ", with: "")]
        for folder in folders {
            for fileName in fileNames where !fileName.isEmpty {
                let url = folder.appending(path: "\(fileName).app")
                if fileManager.fileExists(atPath: url.path) {
                    return ResolvedApp(bundleIdentifier: infoPlist(of: url)?["CFBundleIdentifier"] as? String, url: url)
                }
            }
        }
        for folder in folders {
            guard let contents = try? fileManager.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }
            for url in contents where url.pathExtension == "app" {
                var displayName = fileManager.displayName(atPath: url.path)
                if displayName.hasSuffix(".app") {
                    displayName.removeLast(4)
                }
                // Read as a plain dictionary, not through `Bundle`, which would keep
                // every app it opened cached for the rest of the launch.
                let info = infoPlist(of: url)
                let names = [displayName, info?["CFBundleDisplayName"] as? String, info?["CFBundleName"] as? String]
                if names.contains(where: { $0.map { Self.key(for: $0) == key } == true }) {
                    return ResolvedApp(bundleIdentifier: info?["CFBundleIdentifier"] as? String, url: url)
                }
            }
        }
        return nil
    }

    nonisolated static func infoPlist(of app: URL) -> [String: Any]? {
        NSDictionary(contentsOf: app.appending(path: "Contents/Info.plist")) as? [String: Any]
    }
}

import Foundation
import Observation

/// Whether Now Playing reads the system's now-playing information through the
/// bundled MediaRemote adapter (any app, browsers included) or only Music and
/// Spotify through their own scripting dictionaries.
@MainActor
@Observable
public final class NowPlayingSettings {
    public static let shared = NowPlayingSettings(defaults: .standard)

    static let usesMediaRemoteKey = "NotchNowPlayingUsesMediaRemote"

    /// Off by default: the adapter gets around a macOS restriction by running
    /// third-party code inside an Apple-signed process (`/usr/bin/perl`), so the
    /// user turns it on knowingly, in the Island settings pane.
    public var usesMediaRemote: Bool {
        didSet { defaults.set(usesMediaRemote, forKey: Self.usesMediaRemoteKey) }
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
        usesMediaRemote = defaults.object(forKey: Self.usesMediaRemoteKey) as? Bool ?? false
    }
}

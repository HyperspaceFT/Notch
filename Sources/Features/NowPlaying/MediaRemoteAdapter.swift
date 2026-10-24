import Foundation

/// The bundled mediaremote-adapter (`Vendor/MediaRemoteAdapter`). macOS lets only
/// Apple-signed processes read the system's now-playing information, so the adapter
/// is a framework that `/usr/bin/perl` loads: `stream` prints what the system's
/// now-playing app (a browser tab, Music, Spotify, ...) plays as JSON lines, `send`
/// sends it a command, `seek` moves its position, and `get` prints the current
/// state once. `stream`, and the `get` after a seek, run with `--micros`, which
/// gives the times as whole microseconds and the moment of the position as epoch time.
struct MediaRemoteAdapter: Sendable {
    static let perl = URL(fileURLWithPath: "/usr/bin/perl")
    /// MediaRemote's `kMRTogglePlayPause`.
    static let togglePlayPauseCommand = 2
    /// MediaRemote's `kMRNextTrack`.
    static let nextTrackCommand = 4
    /// MediaRemote's `kMRPreviousTrack`.
    static let previousTrackCommand = 5
    /// A one-shot `send`, `seek`, or `get` that runs longer than this is killed.
    static let oneShotTimeout: TimeInterval = 5

    let script: URL
    let framework: URL

    /// The adapter inside `bundle` (`Contents/Resources/mediaremote-adapter.pl` and
    /// `Contents/Frameworks/MediaRemoteAdapter.framework`, put there by
    /// `scripts/build-app.sh`); `nil` when either is missing, as outside the app bundle.
    static func bundled(in bundle: Bundle = .main) -> MediaRemoteAdapter? {
        guard
            let script = bundle.url(forResource: "mediaremote-adapter", withExtension: "pl"),
            let frameworks = bundle.privateFrameworksURL
        else { return nil }
        let framework = frameworks.appendingPathComponent("MediaRemoteAdapter.framework", isDirectory: true)
        guard FileManager.default.fileExists(atPath: framework.path) else { return nil }
        return MediaRemoteAdapter(script: script, framework: framework)
    }

    /// A perl process that runs `arguments` (the function and its options); the
    /// caller sets `standardOutput` and runs it.
    func makeProcess(_ arguments: [String]) -> Process {
        let process = Process()
        process.executableURL = Self.perl
        process.arguments = [script.path, framework.path] + arguments
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        return process
    }

    /// Runs one function to its end and returns what it printed; `nil` when it did
    /// not start, failed, or ran past `oneShotTimeout`.
    func output(of arguments: [String]) async -> Data? {
        await Task.detached(priority: .utility) { () -> Data? in
            let process = makeProcess(arguments)
            let pipe = Pipe()
            process.standardOutput = pipe
            do {
                try process.run()
            } catch {
                return nil
            }
            // Only the child may hold the write end, or reading never reaches the end.
            try? pipe.fileHandleForWriting.close()
            let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + Self.oneShotTimeout, execute: watchdog)
            let data = try? pipe.fileHandleForReading.readToEnd()
            process.waitUntilExit()
            watchdog.cancel()
            return process.terminationStatus == 0 ? data : nil
        }.value
    }
}

/// How one key changed in a stream line: left as it was, removed (JSON `null`),
/// or set. Only a diff line can keep or remove a key.
enum Change<Value: Sendable & Equatable>: Sendable, Equatable {
    case keep
    case clear
    case set(Value)
}

/// One decoded line of the adapter's `stream` (or the output of `get`), reduced to
/// the keys Now Playing uses. Decoding is plain value work, done off the main actor.
struct MediaRemoteUpdate: Sendable, Equatable {
    /// `true` when the line lists only what changed since the previous line.
    var isDiff = false
    var bundleIdentifier: Change<String> = .keep
    /// Set when the playing process is a helper (a browser's media process) of another app.
    var parentBundleIdentifier: Change<String> = .keep
    var title: Change<String> = .keep
    var artist: Change<String> = .keep
    var album: Change<String> = .keep
    var isPlaying: Change<Bool> = .keep
    var artworkData: Change<Data> = .keep
    /// Seconds, from `durationMicros`.
    var duration: Change<TimeInterval> = .keep
    /// Seconds into the track at `timestamp`, from `elapsedTimeMicros`.
    var elapsedTime: Change<TimeInterval> = .keep
    /// From `timestampEpochMicros`.
    var timestamp: Change<Date> = .keep
    var playbackRate: Change<Double> = .keep

    init() {}

    /// A line of `stream`: `{"type": "data", "diff": false, "payload": {...}}`. Other
    /// lines (and anything that is not JSON) are not updates.
    init?(streamLine line: String) {
        guard
            let data = line.data(using: .utf8),
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
            object["type"] == nil || object["type"] as? String == "data",
            let payload = object["payload"] as? [String: Any]
        else { return nil }
        self.init(payload: payload, isDiff: object["diff"] as? Bool ?? false)
    }

    /// The output of `get`: the bare payload, always complete.
    init?(getOutput data: Data) {
        guard let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        self.init(payload: payload, isDiff: false)
    }

    private init(payload: [String: Any], isDiff: Bool) {
        self.isDiff = isDiff
        bundleIdentifier = Self.change("bundleIdentifier", in: payload) { $0 as? String }
        parentBundleIdentifier = Self.change("parentApplicationBundleIdentifier", in: payload) { $0 as? String }
        title = Self.change("title", in: payload) { $0 as? String }
        artist = Self.change("artist", in: payload) { $0 as? String }
        album = Self.change("album", in: payload) { $0 as? String }
        isPlaying = Self.change("playing", in: payload) { ($0 as? NSNumber)?.boolValue }
        artworkData = Self.change("artworkData", in: payload) { value in
            (value as? String).flatMap { Data(base64Encoded: $0, options: .ignoreUnknownCharacters) }
        }
        duration = Self.change("durationMicros", in: payload) { Self.seconds(fromMicros: $0) }
        elapsedTime = Self.change("elapsedTimeMicros", in: payload) { Self.seconds(fromMicros: $0) }
        timestamp = Self.change("timestampEpochMicros", in: payload) { value in
            Self.seconds(fromMicros: value).map { Date(timeIntervalSince1970: $0) }
        }
        playbackRate = Self.change("playbackRate", in: payload) { ($0 as? NSNumber)?.doubleValue }
    }

    private static func seconds(fromMicros value: Any) -> TimeInterval? {
        guard let micros = (value as? NSNumber)?.doubleValue, micros.isFinite else { return nil }
        return micros / 1_000_000
    }

    /// A value that is there but not of the expected type is as good as removed:
    /// keeping the previous track's would show it on the new one.
    private static func change<Value>(
        _ key: String,
        in payload: [String: Any],
        _ convert: (Any) -> Value?
    ) -> Change<Value> {
        guard let raw = payload[key] else { return .keep }
        if raw is NSNull { return .clear }
        return convert(raw).map { .set($0) } ?? .clear
    }
}

/// What the stream's lines add up to: the system's now-playing item.
struct MediaRemoteState: Sendable, Equatable {
    var bundleIdentifier: String?
    var parentBundleIdentifier: String?
    var title: String?
    var artist: String?
    var album: String?
    var isPlaying: Bool?
    var artworkData: Data?
    var duration: TimeInterval?
    var elapsedTime: TimeInterval?
    var timestamp: Date?
    var playbackRate: Double?

    /// A full line replaces everything (an empty payload means nothing plays); a
    /// diff line changes only the keys it names.
    mutating func apply(_ update: MediaRemoteUpdate) {
        if !update.isDiff {
            self = MediaRemoteState()
        }
        bundleIdentifier.apply(update.bundleIdentifier)
        parentBundleIdentifier.apply(update.parentBundleIdentifier)
        title.apply(update.title)
        artist.apply(update.artist)
        album.apply(update.album)
        isPlaying.apply(update.isPlaying)
        artworkData.apply(update.artworkData)
        applyTiming(of: update)
    }

    /// Only the length, position, and rate of `update`, as the diff of a line would.
    mutating func applyTiming(of update: MediaRemoteUpdate) {
        duration.apply(update.duration)
        elapsedTime.apply(update.elapsedTime)
        timestamp.apply(update.timestamp)
        playbackRate.apply(update.playbackRate)
    }

    /// Moves the position's anchor to `now`: to `elapsed` when given (a seek),
    /// else to where playback has got to, so a change of play state held before
    /// the stream confirms it neither jumps nor runs on while paused.
    mutating func reanchor(at now: Date, elapsed: TimeInterval? = nil) {
        guard let elapsed = elapsed ?? snapshot?.elapsed(at: now) else { return }
        elapsedTime = elapsed
        timestamp = now
    }

    /// The position, when the line gave both its time and its moment. The rate is
    /// 0 while paused, and the play state may be held ahead of it (see
    /// `MediaRemoteMonitor.togglePlayPause`), so only a positive rate counts;
    /// the play state decides whether the position moves.
    private var position: PlaybackPosition? {
        guard let elapsedTime, let timestamp else { return nil }
        let rate = playbackRate.flatMap { $0 > 0 ? $0 : nil } ?? 1
        return PlaybackPosition(elapsed: elapsedTime, date: timestamp, rate: rate)
    }

    /// `nil` without a title: nothing worth showing is playing.
    var snapshot: PlaybackSnapshot? {
        PlaybackSnapshot(
            bundleIdentifier: parentBundleIdentifier ?? bundleIdentifier ?? "",
            isPlaying: isPlaying ?? false,
            title: title ?? "",
            artist: artist,
            album: album,
            artworkData: artworkData,
            duration: duration,
            position: position
        )
    }
}

private extension Optional where Wrapped: Sendable & Equatable {
    mutating func apply(_ change: Change<Wrapped>) {
        switch change {
        case .keep: break
        case .clear: self = nil
        case .set(let value): self = value
        }
    }
}

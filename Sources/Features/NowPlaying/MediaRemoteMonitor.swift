import Foundation

/// Follows what the system's now-playing app plays, whichever app that is, by
/// keeping the adapter's `stream` running, and calls `onChange` on the main actor
/// with every reading (`nil` = nothing playing).
///
/// A stream that ends is started again after `restartDelay`. When it keeps ending
/// within `quickExit` of its start (the adapter cannot run here), `onUnavailable`
/// is called once and the monitor stops, so the caller can fall back to another source.
@MainActor
final class MediaRemoteMonitor {
    static let quickExit: Duration = .seconds(5)
    static let maximumQuickExits = 3
    static let restartDelay: Duration = .seconds(1)
    /// Lets the app act on a command before its state is read back.
    static let settleDelay: Duration = .milliseconds(500)
    /// Title, cover, and play state of a change arrive as separate events; the
    /// adapter merges those within this many milliseconds into one line.
    static let debounceMilliseconds = 100

    private let adapter: MediaRemoteAdapter
    private let restartDelay: Duration
    private let settleDelay: Duration
    private let onChange: @MainActor (PlaybackSnapshot?) -> Void
    private let onUnavailable: @MainActor () -> Void
    private var task: Task<Void, Never>?
    private var process: Process?
    private var state = MediaRemoteState()
    /// How many stream lines have set the play state (a full line does); lets a
    /// read-back tell that the stream has spoken since it started.
    private var playStateLines = 0
    /// The same for the position, for the read-back after a seek.
    private var positionLines = 0

    init(
        adapter: MediaRemoteAdapter,
        restartDelay: Duration = MediaRemoteMonitor.restartDelay,
        settleDelay: Duration = MediaRemoteMonitor.settleDelay,
        onChange: @escaping @MainActor (PlaybackSnapshot?) -> Void,
        onUnavailable: @escaping @MainActor () -> Void
    ) {
        self.adapter = adapter
        self.restartDelay = restartDelay
        self.settleDelay = settleDelay
        self.onChange = onChange
        self.onUnavailable = onUnavailable
    }

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            await self?.run()
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        process?.terminate()
        process = nil
        state = MediaRemoteState()
    }

    /// Sends `command` to the now-playing app. Skipping is left to the stream: a
    /// skip it obeys changes the title, which the stream always reports, and one
    /// it ignores showed nothing in advance that would need taking back.
    func perform(_ command: PlaybackCommand) async {
        switch command {
        case .playPause:
            await togglePlayPause()
        case .next:
            _ = await adapter.output(of: ["send", String(MediaRemoteAdapter.nextTrackCommand)])
        case .previous:
            _ = await adapter.output(of: ["send", String(MediaRemoteAdapter.previousTrackCommand)])
        case .seek(let seconds):
            await seek(to: seconds)
        }
    }

    /// Plays or pauses the now-playing app, then reads its play state back so a
    /// command it ignored does not leave the wings showing the wrong one. The stream
    /// reports a change on its own; it cannot report that nothing changed.
    ///
    /// Until the app answers, the flipped state is held here too, so a stream line
    /// about something else (a cover) does not flip the wings back. Only the play
    /// state is taken from the read-back, and not at all when the stream has set it
    /// meanwhile: the read-back may be the older of the two.
    func togglePlayPause() async {
        if let isPlaying = state.isPlaying {
            state.reanchor(at: Date())
            state.isPlaying = !isPlaying
        }
        _ = await adapter.output(of: ["send", String(MediaRemoteAdapter.togglePlayPauseCommand)])
        try? await Task.sleep(for: settleDelay)
        let linesBefore = playStateLines
        guard
            task != nil,
            let data = await adapter.output(of: ["get"]),
            task != nil,
            playStateLines == linesBefore,
            case .set(let isPlaying)? = MediaRemoteUpdate(getOutput: data)?.isPlaying,
            state.isPlaying != isPlaying
        else { return }
        state.isPlaying = isPlaying
        onChange(state.snapshot)
    }

    /// Moves the now-playing app to `seconds`, then reads its position back, for
    /// the same reasons as `togglePlayPause`: the stream reports a seek the app
    /// made, not one it ignored. The new position is held meanwhile, and the
    /// read-back is dropped once the stream has given a position of its own.
    func seek(to seconds: TimeInterval) async {
        let seconds = max(seconds, 0)
        // Also rules out a length an app made up so large it has no Int64 in microseconds.
        guard let micros = Int64(exactly: (seconds * 1_000_000).rounded()) else { return }
        state.reanchor(at: Date(), elapsed: seconds)
        _ = await adapter.output(of: ["seek", String(micros)])
        try? await Task.sleep(for: settleDelay)
        let linesBefore = positionLines
        guard
            task != nil,
            let data = await adapter.output(of: ["get", "--micros"]),
            task != nil,
            positionLines == linesBefore,
            let update = MediaRemoteUpdate(getOutput: data)
        else { return }
        let held = state
        state.applyTiming(of: update)
        guard state != held else { return }
        onChange(state.snapshot)
    }

    private func run() async {
        var quickExits = 0
        while !Task.isCancelled {
            let start = ContinuousClock.now
            await streamOnce()
            guard !Task.isCancelled else { return }
            state = MediaRemoteState()
            onChange(nil)
            quickExits = start.duration(to: .now) < Self.quickExit ? quickExits + 1 : 0
            if quickExits >= Self.maximumQuickExits {
                onUnavailable()
                return
            }
            try? await Task.sleep(for: restartDelay)
        }
    }

    /// Runs one stream process to its end.
    private func streamOnce() async {
        let process = adapter.makeProcess(["stream", "--debounce=\(Self.debounceMilliseconds)", "--micros"])
        let pipe = Pipe()
        process.standardOutput = pipe
        do {
            try process.run()
        } catch {
            return
        }
        // Only the child may hold the write end, or the reader never sees the end.
        try? pipe.fileHandleForWriting.close()
        self.process = process
        await withTaskCancellationHandler {
            for await update in Self.updates(from: pipe.fileHandleForReading) {
                guard !Task.isCancelled else { break }
                apply(update)
            }
        } onCancel: {
            process.terminate()
        }
        if process.isRunning {
            process.terminate()
        }
        if self.process === process {
            self.process = nil
        }
    }

    private func apply(_ update: MediaRemoteUpdate) {
        if !update.isDiff || update.isPlaying != .keep {
            playStateLines += 1
        }
        if !update.isDiff || update.elapsedTime != .keep {
            positionLines += 1
        }
        state.apply(update)
        onChange(state.snapshot)
    }

    /// The decoded lines of `handle`, read and decoded off the main actor. The
    /// sequence ends when the process does.
    private nonisolated static func updates(from handle: FileHandle) -> AsyncStream<MediaRemoteUpdate> {
        AsyncStream { continuation in
            let reader = Task.detached(priority: .utility) {
                do {
                    for try await line in handle.bytes.lines {
                        if let update = MediaRemoteUpdate(streamLine: line) {
                            continuation.yield(update)
                        }
                    }
                } catch {}
                continuation.finish()
            }
            continuation.onTermination = { _ in reader.cancel() }
        }
    }
}

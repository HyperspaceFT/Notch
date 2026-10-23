import Observation

/// Reminders ticked off but not yet written: each commits after `delay`
/// unless ticked again first, so a mistaken tap can be taken back.
@MainActor
@Observable
final class CompletionQueue {
    private(set) var pending: Set<String> = []

    @ObservationIgnored private let delay: Duration
    @ObservationIgnored private let commit: @MainActor (String) -> Void
    @ObservationIgnored private var timers: [String: Task<Void, Never>] = [:]

    init(delay: Duration, commit: @escaping @MainActor (String) -> Void) {
        self.delay = delay
        self.commit = commit
    }

    func isPending(_ id: String) -> Bool {
        pending.contains(id)
    }

    /// Pends `id`, or takes it back when it is pending.
    func toggle(_ id: String) {
        if pending.contains(id) {
            cancel(id)
            return
        }
        pending.insert(id)
        let delay = delay
        timers[id] = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            self.timers[id] = nil
            guard self.pending.remove(id) != nil else { return }
            self.commit(id)
        }
    }

    /// Drops `id` without committing it, as when the reminder is deleted.
    func cancel(_ id: String) {
        timers.removeValue(forKey: id)?.cancel()
        pending.remove(id)
    }

    /// Commits every pending id now, each once; their timers no longer fire.
    func flush() {
        for timer in timers.values {
            timer.cancel()
        }
        timers = [:]
        let ids = pending.sorted()
        pending = []
        for id in ids {
            commit(id)
        }
    }
}

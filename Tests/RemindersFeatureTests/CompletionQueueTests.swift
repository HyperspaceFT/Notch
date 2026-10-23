import Testing
@testable import RemindersFeature

/// The ids a queue committed, in order.
@MainActor
private final class Commits {
    var ids: [String] = []
}

@MainActor
private func makeQueue(delay: Duration, into commits: Commits) -> CompletionQueue {
    CompletionQueue(delay: delay) { id in
        commits.ids.append(id)
    }
}

@MainActor
struct CompletionQueueTests {
    @Test func commitsOnceAfterTheDelay() async {
        let commits = Commits()
        let queue = makeQueue(delay: .milliseconds(50), into: commits)
        queue.toggle("a")
        #expect(queue.isPending("a"))
        #expect(commits.ids.isEmpty)
        try? await Task.sleep(for: .milliseconds(400))
        #expect(commits.ids == ["a"])
        #expect(!queue.isPending("a"))
        try? await Task.sleep(for: .milliseconds(200))
        #expect(commits.ids == ["a"])
    }

    @Test func togglingTwiceWithinTheDelayCommitsNothing() async {
        let commits = Commits()
        let queue = makeQueue(delay: .milliseconds(100), into: commits)
        queue.toggle("a")
        queue.toggle("a")
        #expect(!queue.isPending("a"))
        try? await Task.sleep(for: .milliseconds(400))
        #expect(commits.ids.isEmpty)
    }

    @Test func flushCommitsPendingAtOnceAndOnlyOnce() async {
        let commits = Commits()
        let queue = makeQueue(delay: .milliseconds(100), into: commits)
        queue.toggle("a")
        queue.toggle("b")
        queue.flush()
        #expect(commits.ids.sorted() == ["a", "b"])
        #expect(!queue.isPending("a"))
        #expect(!queue.isPending("b"))
        try? await Task.sleep(for: .milliseconds(400))
        #expect(commits.ids.sorted() == ["a", "b"])
    }

    @Test func idsAreIndependent() async {
        let commits = Commits()
        let queue = makeQueue(delay: .milliseconds(100), into: commits)
        queue.toggle("a")
        queue.toggle("b")
        queue.toggle("a")
        #expect(!queue.isPending("a"))
        #expect(queue.isPending("b"))
        try? await Task.sleep(for: .milliseconds(400))
        #expect(commits.ids == ["b"])
    }

    @Test func aCancelledIDIsNeverCommittedByItsTimer() async {
        let commits = Commits()
        let queue = makeQueue(delay: .milliseconds(50), into: commits)
        queue.toggle("a")
        queue.cancel("a")
        #expect(!queue.isPending("a"))
        try? await Task.sleep(for: .milliseconds(400))
        #expect(commits.ids.isEmpty)
    }

    @Test func flushSkipsACancelledID() async {
        let commits = Commits()
        let queue = makeQueue(delay: .milliseconds(100), into: commits)
        queue.toggle("a")
        queue.toggle("b")
        queue.cancel("a")
        queue.flush()
        #expect(commits.ids == ["b"])
        try? await Task.sleep(for: .milliseconds(400))
        #expect(commits.ids == ["b"])
    }
}

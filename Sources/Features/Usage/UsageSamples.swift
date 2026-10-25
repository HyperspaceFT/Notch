import Foundation

/// What the Debug pane shows in place of the real usage, in memory only.
struct UsageSample: Equatable, Sendable {
    var providers: [UsageProvider]
    var statuses: [UsageProvider: UsageStatus]
    /// When the sample ends by itself: as long as a fresh report would last, so
    /// one left behind with the Debug pane gone does not stay for good.
    var expiresAt: Date

    /// Every provider with a report: all three levels of color show, and the
    /// parts of a limit after its percent.
    static func reports(for providers: [UsageProvider] = UsageProvider.allCases, now: Date) -> UsageSample {
        UsageSample(
            providers: providers,
            statuses: Dictionary(uniqueKeysWithValues: providers.map { provider in
                (provider, UsageStatus(state: .ok, report: report(for: provider, now: now), checkedAt: now))
            }),
            expiresAt: now.addingTimeInterval(UsageRefreshPolicy.staleAfter)
        )
    }

    /// Every provider in `state`, without a report.
    static func state(_ state: UsageStatus.State, now: Date) -> UsageSample {
        let checkedAt: Date? = state == .loading ? nil : now
        return UsageSample(
            providers: UsageProvider.allCases,
            statuses: Dictionary(uniqueKeysWithValues: UsageProvider.allCases.map { provider in
                (provider, UsageStatus(state: state, report: nil, checkedAt: checkedAt))
            }),
            expiresAt: now.addingTimeInterval(UsageRefreshPolicy.staleAfter)
        )
    }

    static func report(for provider: UsageProvider, now: Date) -> UsageReport {
        let hour: TimeInterval = 60 * 60
        switch provider {
        case .claude:
            let weeklyReset = now.addingTimeInterval(3.5 * 24 * hour)
            return UsageReport(plan: "Max 5x", windows: [
                UsageWindow(duration: ClaudeUsage.sessionDuration, percent: 42, resetsAt: now.addingTimeInterval(2.3 * hour)),
                UsageWindow(
                    duration: ClaudeUsage.weeklyDuration,
                    percent: 18,
                    resetsAt: weeklyReset,
                    scoped: [UsageScope(label: "Fable", percent: 74, resetsAt: weeklyReset)]
                ),
            ])
        case .codex:
            return UsageReport(plan: "Plus", windows: [
                UsageWindow(duration: 5 * hour, percent: 76, resetsAt: now.addingTimeInterval(1.2 * hour)),
                UsageWindow(duration: 7 * 24 * hour, percent: 93, resetsAt: now.addingTimeInterval(5 * 24 * hour)),
            ])
        case .grok:
            return UsageReport(plan: "SuperGrok", windows: [
                UsageWindow(
                    duration: GrokUsage.weeklyDuration,
                    percent: 57,
                    resetsAt: now.addingTimeInterval(2.2 * 24 * hour),
                    scoped: [
                        UsageScope(label: "Chat", percent: 41, resetsAt: nil),
                        UsageScope(label: "Imagine", percent: 12, resetsAt: nil),
                        UsageScope(label: "Voice", percent: 4, resetsAt: nil),
                    ]
                ),
            ])
        }
    }
}

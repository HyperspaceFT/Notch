import Foundation
import NotchKit
import Observation

/// Each provider's usage and how its last refresh went. Refreshes only when a
/// usage view asks (`refreshIfNeeded`, from their minute loops while mounted),
/// the settings pane appears, a provider is turned on, a sign-in window closes,
/// or Retry is pressed; nothing runs while no usage view is on screen. Reports
/// stay in memory.
@MainActor
@Observable
public final class UsageModel {
    public static let shared = UsageModel(settings: .shared, webSession: .shared)

    private var statuses: [UsageProvider: UsageStatus] = [:]
    /// Providers with a refresh in flight.
    public private(set) var refreshing: Set<UsageProvider> = []
    /// The Debug pane's sample, which overrides the real usage while it lasts:
    /// until "Use Real Usage", for as long as a fresh report would last
    /// (`UsageSample.expiresAt`), or until the user acts on the real usage (the
    /// Settings switch, Retry, Sign Out, a sign-in window closing), so it cannot
    /// outlive the Debug pane that set it.
    private(set) var sample: UsageSample?

    @ObservationIgnored let settings: UsageSettings
    @ObservationIgnored private let webSession: UsageWebSession
    @ObservationIgnored private lazy var client = UsageClient(webSession: webSession)
    @ObservationIgnored private let claudeOrganization = ClaudeOrganizationCache()
    @ObservationIgnored private var tasks: [UsageProvider: Task<Void, Never>] = [:]
    /// Sign-outs in progress. They always run to completion and clear their own
    /// entry, which `signOutIDs` tells apart from a later sign-out's.
    @ObservationIgnored private var signOutTasks: [UsageProvider: Task<Void, Never>] = [:]
    @ObservationIgnored private var signOutIDs: [UsageProvider: Int] = [:]
    /// Bumped whenever a provider's refresh is superseded, so a task that ends
    /// afterwards does not write its stale result back.
    @ObservationIgnored private var generations: [UsageProvider: Int] = [:]

    init(settings: UsageSettings, webSession: UsageWebSession) {
        self.settings = settings
        self.webSession = webSession
    }

    /// The providers the views show: the sample's while one shows, else the user's choice.
    public var displayedProviders: [UsageProvider] {
        sample?.providers ?? settings.shownProviders
    }

    public func status(of provider: UsageProvider) -> UsageStatus {
        if let sample { return sample.statuses[provider] ?? UsageStatus() }
        return statuses[provider] ?? UsageStatus()
    }

    public func isRefreshing(_ provider: UsageProvider) -> Bool {
        sample == nil && refreshing.contains(provider)
    }

    /// Refreshes each shown provider that is due (`UsageRefreshPolicy`).
    public func refreshIfNeeded(now: Date = Date()) {
        if let sample, now >= sample.expiresAt {
            self.sample = nil
        }
        guard sample == nil else { return }
        for provider in settings.shownProviders
        where UsageRefreshPolicy.isDue(status(of: provider), isInFlight: tasks[provider] != nil, now: now) {
            refresh(provider, force: true)
        }
    }

    /// Refreshes `provider` unless it is fresh; `force` refreshes it at once,
    /// replacing a refresh in flight (which may have started with an older sign-in).
    /// A forced refresh is the user's (Retry, the Settings switch) or comes after
    /// the sample is gone, so it ends any sample first.
    public func refresh(_ provider: UsageProvider, force: Bool = false) {
        if force {
            dropSample()
        }
        // Not while a sign-out still removes the cookies a request would send.
        guard sample == nil, signOutTasks[provider] == nil else { return }
        if !force, !UsageRefreshPolicy.isDue(status(of: provider), isInFlight: tasks[provider] != nil, now: Date()) {
            return
        }
        cancelRefresh(of: provider)
        let generation = generations[provider, default: 0]
        refreshing.insert(provider)
        tasks[provider] = Task { [weak self] in
            // `stop()` may come before the task first runs.
            guard !Task.isCancelled, let self else { return }
            let result: Result<UsageReport, UsageFetchError>
            do throws(UsageFetchError) {
                result = .success(try await fetch(provider))
            } catch {
                result = .failure(error)
            }
            finish(provider, generation: generation, with: result)
        }
    }

    /// Removes the provider's website data, forgets what was read with it, and
    /// shows it signed out.
    public func signOut(_ provider: UsageProvider) {
        dropSample()
        // A cancelled refresh may still be storing the cookies of an answer it
        // already has, so the removal waits for it to end; so does a sign-out
        // still in progress.
        let pending = [tasks[provider], signOutTasks[provider]].compactMap { $0 }
        cancelRefresh(of: provider)
        if provider == .claude {
            claudeOrganization.organization = nil
        }
        statuses[provider] = UsageStatus(state: .signedOut, report: nil, checkedAt: Date())
        let id = signOutIDs[provider, default: 0] + 1
        signOutIDs[provider] = id
        signOutTasks[provider] = Task { [weak self, webSession] in
            for task in pending {
                await task.value
            }
            await webSession.signOut(provider)
            guard let self, signOutIDs[provider] == id else { return }
            signOutTasks[provider] = nil
        }
    }

    /// The provider's sign-in window closed: reads its usage again with what was
    /// signed in there. Claude's organization is read again too, in case the
    /// window switched accounts.
    public func signInWindowClosed(_ provider: UsageProvider) {
        dropSample()
        if provider == .claude {
            claudeOrganization.organization = nil
        }
        refresh(provider, force: true)
    }

    /// Ends the Debug pane's sample, if one shows, for an action on the real usage.
    public func dropSample() {
        sample = nil
    }

    /// Cancels every refresh in flight; their results are dropped. Sign-outs run
    /// on to completion, so no refresh starts before their data is gone.
    public func stop() {
        for provider in UsageProvider.allCases {
            cancelRefresh(of: provider)
        }
    }

    // MARK: Debug samples

    /// For the Debug pane: shows `sample` in place of the real usage, without
    /// refreshing, until `useRealUsage()`, its expiry, or a user action (see `sample`).
    func showSample(_ sample: UsageSample) {
        stop()
        self.sample = sample
    }

    /// For the Debug pane: drops the sample and reads the shown providers again now.
    func useRealUsage() {
        sample = nil
        for provider in settings.shownProviders {
            refresh(provider, force: true)
        }
    }

    // MARK: Private

    private func cancelRefresh(of provider: UsageProvider) {
        generations[provider, default: 0] += 1
        tasks[provider]?.cancel()
        tasks[provider] = nil
        refreshing.remove(provider)
    }

    private func fetch(_ provider: UsageProvider) async throws(UsageFetchError) -> UsageReport {
        switch provider {
        case .claude: try await ClaudeUsage.fetch(client: client, cache: claudeOrganization)
        case .codex: try await CodexUsage.fetch(client: client)
        case .grok: try await GrokUsage.fetch(client: client)
        }
    }

    private func finish(_ provider: UsageProvider, generation: Int, with result: Result<UsageReport, UsageFetchError>) {
        // Superseded, signed out, or stopped meanwhile: none of this applies any more.
        guard generations[provider, default: 0] == generation, !Task.isCancelled else { return }
        tasks[provider] = nil
        refreshing.remove(provider)
        // The previous report stays on screen beside the failure.
        var status = statuses[provider] ?? UsageStatus()
        switch result {
        case .success(let report):
            status.state = .ok
            status.report = report
        case .failure(.cancelled):
            // Not a failure: the previous status and its time stay.
            return
        case .failure(.signedOut):
            status.state = .signedOut
        case .failure(.needsVerification):
            status.state = .needsVerification
        case .failure(.failed(let failure)):
            status.state = .failed(failure)
        }
        status.checkedAt = Date()
        statuses[provider] = status
    }
}

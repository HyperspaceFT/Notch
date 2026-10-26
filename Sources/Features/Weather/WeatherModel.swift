import Foundation
import NotchKit
import Observation

/// The last weather report and what the module shows about it. Refreshes only
/// when the module's view asks (`refreshIfNeeded`) or the Weather settings'
/// Refresh button does (`refreshNow`), so nothing runs on its own while the
/// panel is closed or the module is not on Home.
@MainActor
@Observable
public final class WeatherModel {
    /// The one the Weather feature shows and the Weather settings refresh.
    public static let shared = WeatherModel()

    public enum Status: Equatable {
        /// No report yet, and none failed.
        case loading
        /// Location access is denied or restricted.
        case locationNotAllowed
        /// No report, and the last attempt failed.
        case failed
        case ready
    }

    private(set) var report: WeatherReport?
    public private(set) var status = Status.loading
    /// When the last report arrived (or a Debug sample was shown).
    public private(set) var lastSuccess: Date?
    /// When the last refresh failed, kept until the next success.
    public private(set) var lastFailure: Date?

    @ObservationIgnored private let location = LocationProvider()
    /// Observed, for the settings' Refresh button and its spinner.
    private var refreshTask: Task<Void, Never>?
    /// The last place a fix found, used when a later fix fails.
    @ObservationIgnored private var lastCoordinate: Coordinate?

    /// Whether a refresh, location fix included, is in progress.
    public var isRefreshing: Bool { refreshTask != nil }

    init() {
        location.onAccessGranted = { [weak self] in
            self?.accessGranted()
        }
        location.onLateFix = { [weak self] coordinate in
            self?.lateFix(coordinate)
        }
    }

    func refreshIfNeeded(now: Date = Date()) {
        guard WeatherRefreshPolicy.shouldRefresh(
            now: now,
            lastSuccess: lastSuccess,
            lastFailure: lastFailure,
            isInFlight: refreshTask != nil
        ) else { return }
        startRefresh(reusingRecentFix: true)
    }

    /// For the Weather settings' Refresh button: drops the refresh in progress
    /// and starts one now with a new location fix, however fresh the report is.
    /// The report stays on screen meanwhile, and after a failure while recent
    /// enough, as for any refresh.
    public func refreshNow() {
        cancelRefresh()
        startRefresh(reusingRecentFix: false)
    }

    private func startRefresh(reusingRecentFix: Bool) {
        refreshTask = Task { [weak self, location] in
            // `stop()` may come before the task first runs.
            guard !Task.isCancelled else { return }
            let result = await location.requestLocation(reusingRecentFix: reusingRecentFix)
            guard !Task.isCancelled, let coordinate = self?.coordinate(for: result) else { return }
            do {
                let report = try await OpenMeteo.fetch(for: coordinate)
                guard !Task.isCancelled else { return }
                self?.succeeded(with: report)
            } catch {
                guard !Task.isCancelled else { return }
                self?.failed()
            }
        }
    }

    /// For the Debug pane: shows `report` as if just fetched, in place of the
    /// real one and for as long as a fresh one lasts. Leaves `Daylight` alone,
    /// so the island's edge keeps following the real sun.
    func showSample(_ report: WeatherReport) {
        cancelRefresh()
        lastSuccess = Date()
        lastFailure = nil
        self.report = report
        status = .ready
    }

    /// For the Debug pane: shows `status`, which has no report, for as long as a
    /// fresh report would last.
    func showStatus(_ status: Status) {
        cancelRefresh()
        lastSuccess = Date()
        lastFailure = nil
        report = nil
        self.status = status
    }

    /// For the Debug pane: drops any sample and fetches the real weather now.
    func useRealWeather() {
        lastSuccess = nil
        lastFailure = nil
        report = nil
        status = .loading
        refreshIfNeeded()
    }

    /// Lets no fetch in progress replace a sample, or the refresh that replaces
    /// it, when it ends.
    private func cancelRefresh() {
        if refreshTask != nil {
            stop()
        }
    }

    /// Cancels the refresh in progress and the location request with it.
    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
        location.cancel()
    }

    /// The place to fetch for, or `nil` after recording why there is none.
    private func coordinate(for result: LocationResult) -> Coordinate? {
        switch result {
        case .coordinate(let coordinate):
            lastCoordinate = coordinate
            return coordinate
        case .failed:
            if let lastCoordinate { return lastCoordinate }
            failed()
            return nil
        case .notAllowed:
            // Checking access again costs nothing, so the next check tries again
            // at once and finds access granted meanwhile.
            refreshTask = nil
            lastSuccess = nil
            lastFailure = nil
            status = .locationNotAllowed
            return nil
        }
    }

    /// Access was just granted: refresh now instead of after the retry delay.
    private func accessGranted() {
        lastFailure = nil
        refreshIfNeeded()
    }

    /// A fix came after its request had timed out: refresh now, which reuses it
    /// as the manager's recent location, unless the report is fresh anyway.
    private func lateFix(_ coordinate: Coordinate) {
        lastCoordinate = coordinate
        lastFailure = nil
        refreshIfNeeded()
    }

    private func succeeded(with report: WeatherReport) {
        refreshTask = nil
        lastSuccess = Date()
        lastFailure = nil
        self.report = report
        status = .ready
        // The island's edge follows the sun at the same place.
        Daylight.shared.update(report.sunTimes)
    }

    /// Keeps the previous report, if any, on screen while it is recent enough.
    private func failed() {
        refreshTask = nil
        let now = Date()
        lastFailure = now
        if let report, !WeatherRefreshPolicy.keepsReport(observedAt: report.current.time, now: now) {
            self.report = nil
        }
        status = report == nil ? .failed : .ready
    }
}

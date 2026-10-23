import Foundation
import Observation

/// The last weather report and what the module shows about it. Refreshes only
/// when the module's view asks (`refreshIfNeeded`), so nothing runs while the
/// panel is closed or the module is not on Home.
@MainActor
@Observable
final class WeatherModel {
    enum Status: Equatable {
        /// No report yet, and none failed.
        case loading
        /// Location access is denied or restricted.
        case locationNotAllowed
        /// No report, and the last attempt failed.
        case failed
        case ready
    }

    private(set) var report: WeatherReport?
    private(set) var status = Status.loading

    @ObservationIgnored private let location = LocationProvider()
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var lastSuccess: Date?
    @ObservationIgnored private var lastFailure: Date?
    /// The last place a fix found, used when a later fix fails.
    @ObservationIgnored private var lastCoordinate: Coordinate?

    init() {
        location.onAccessGranted = { [weak self] in
            self?.accessGranted()
        }
    }

    func refreshIfNeeded(now: Date = Date()) {
        guard WeatherRefreshPolicy.shouldRefresh(
            now: now,
            lastSuccess: lastSuccess,
            lastFailure: lastFailure,
            isInFlight: refreshTask != nil
        ) else { return }
        refreshTask = Task { [weak self, location] in
            // `stop()` may come before the task first runs.
            guard !Task.isCancelled else { return }
            let result = await location.requestLocation()
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

    private func succeeded(with report: WeatherReport) {
        refreshTask = nil
        lastSuccess = Date()
        lastFailure = nil
        self.report = report
        status = .ready
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

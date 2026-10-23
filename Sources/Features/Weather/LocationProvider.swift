import CoreLocation
import Foundation

/// What a one-shot location request ended with.
enum LocationResult: Equatable, Sendable {
    case coordinate(Coordinate)
    /// Location access is denied or restricted.
    case notAllowed
    case failed
}

/// One-shot approximate location from CoreLocation, asking for access the first
/// time. On macOS the granted status is `.authorizedAlways`.
@MainActor
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    /// How long a request may wait, for the user's answer included, before it ends
    /// with `.failed`; without a limit, a prompt that never shows would stall it.
    static let requestTimeout: Duration = .seconds(30)

    /// Called when access is granted while no request waits for it, such as in
    /// System Settings or after a request timed out on the prompt.
    var onAccessGranted: (@MainActor () -> Void)?

    private var manager: CLLocationManager?
    private var pending: CheckedContinuation<LocationResult, Never>?
    private var timeout: Task<Void, Never>?
    /// The last status the manager reported. It reports the current one once on
    /// creation; only changes count.
    private var lastStatus: CLAuthorizationStatus?

    /// The current location, after asking for access if the user has not decided yet.
    func requestLocation() async -> LocationResult {
        finish(.failed)
        return await withCheckedContinuation { continuation in
            pending = continuation
            timeout = Task { [weak self] in
                try? await Task.sleep(for: Self.requestTimeout)
                guard !Task.isCancelled else { return }
                self?.finish(.failed)
            }
            let manager = self.manager ?? makeManager()
            switch manager.authorizationStatus {
            case .notDetermined:
                // Continues in `authorizationChanged` once the user answers.
                manager.requestWhenInUseAuthorization()
            case .authorizedAlways:
                manager.requestLocation()
            default:
                finish(.notAllowed)
            }
        }
    }

    /// Drops the request in progress, which then ends with `.failed`.
    func cancel() {
        manager?.stopUpdatingLocation()
        manager?.delegate = nil
        manager = nil
        finish(.failed)
    }

    private func makeManager() -> CLLocationManager {
        let manager = CLLocationManager()
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        manager.delegate = self
        lastStatus = manager.authorizationStatus
        self.manager = manager
        return manager
    }

    private func finish(_ result: LocationResult) {
        timeout?.cancel()
        timeout = nil
        let continuation = pending
        pending = nil
        continuation?.resume(returning: result)
    }

    private func authorizationChanged(_ status: CLAuthorizationStatus) {
        guard status != lastStatus, let manager else { return }
        lastStatus = status
        switch status {
        case .notDetermined:
            break
        case .authorizedAlways:
            if pending != nil {
                manager.requestLocation()
            } else {
                onAccessGranted?()
            }
        default:
            finish(.notAllowed)
        }
    }

    // The manager calls its delegate on the run loop it was created on (the main
    // one), but the protocol is not main-actor isolated, so the callbacks copy out
    // Sendable values and hop to the main actor.

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor [weak self] in
            self?.authorizationChanged(status)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let coordinate = Coordinate(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        )
        Task { @MainActor [weak self] in
            self?.finish(.coordinate(coordinate))
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        let isDenied = (error as? CLError)?.code == .denied
        Task { @MainActor [weak self] in
            self?.finish(isDenied ? .notAllowed : .failed)
        }
    }
}

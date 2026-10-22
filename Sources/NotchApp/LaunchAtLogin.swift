import Observation
import ServiceManagement

/// Whether Notch opens at login. The system owns this setting (the user can also
/// change it in System Settings → General → Login Items), so it is read back from
/// `SMAppService` instead of being stored by the app.
@MainActor
@Observable
final class LaunchAtLogin {
    private(set) var status: SMAppService.Status
    /// Why the last change failed; cleared by the next one that succeeds.
    private(set) var errorMessage: String?

    init() {
        status = SMAppService.mainApp.status
    }

    /// On while registered, including while the login item still waits for the
    /// user's approval in System Settings.
    var isEnabled: Bool {
        get { status == .enabled || status == .requiresApproval }
        set {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
            refresh()
        }
    }

    /// Reads the state again, since System Settings may have changed it meanwhile.
    func refresh() {
        status = SMAppService.mainApp.status
    }
}

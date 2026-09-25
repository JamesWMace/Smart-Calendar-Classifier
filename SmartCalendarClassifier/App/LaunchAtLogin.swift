import ServiceManagement

/// Starts the app when the user logs in, so the shortcut always works.
@MainActor
@Observable
final class LaunchAtLogin {
    static let shared = LaunchAtLogin()

    private(set) var isEnabled = SMAppService.mainApp.status == .enabled
    private(set) var error: String?

    func set(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        isEnabled = SMAppService.mainApp.status == .enabled
    }
}

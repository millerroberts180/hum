import HumCore
import Observation
import ServiceManagement

/// Open at login, through `SMAppService.mainApp`.
///
/// Hum registers itself only when the user switches this on. The system's list
/// of login items is the truth, so the status is read back after every change
/// and whenever Settings comes forward.
@Observable
final class LoginItem {
    private(set) var status: SMAppService.Status
    private(set) var failure: String?
    private let service: any LoginItemService

    init(service: any LoginItemService = SMAppService.mainApp) {
        self.service = service
        status = service.status
    }

    /// On, or waiting for the user to allow it in System Settings.
    var isOn: Bool {
        status == .enabled || status == .requiresApproval
    }

    var needsApproval: Bool {
        status == .requiresApproval
    }

    func refresh() {
        status = service.status
    }

    func set(_ isOn: Bool) {
        failure = nil
        do {
            if isOn {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            HumLog.app.error("Login item \(isOn ? "register" : "unregister", privacy: .public) failed: \(String(describing: error), privacy: .public)")
            failure = isOn
                ? "Hum couldn’t add itself to your login items."
                : "Hum couldn’t remove itself from your login items."
        }
        refresh()
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

/// The part of `SMAppService` that `LoginItem` uses, so tests can stand in for
/// the system's list of login items.
protocol LoginItemService {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
}

extension SMAppService: LoginItemService {}

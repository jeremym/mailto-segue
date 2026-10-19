import Foundation
import ServiceManagement

/// Open at login, only for the opt-in resident mode. Uses SMAppService, so
/// it shows up in System Settings → General → Login Items.
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func set(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            Log.write("login item: \(error.localizedDescription)")
        }
    }
}

import ServiceManagement
import os.log

private nonisolated(unsafe) let logger = Logger(subsystem: "com.feishuspeech.app", category: "LoginItem")

enum LoginItemService {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
                logger.info("Login item registered")
            } else {
                try SMAppService.mainApp.unregister()
                logger.info("Login item unregistered")
            }
        } catch {
            logger.error("Failed to \(enabled ? "register" : "unregister") login item: \(error.localizedDescription)")
        }
    }
}

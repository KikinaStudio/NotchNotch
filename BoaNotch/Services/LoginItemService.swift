import Foundation
import ServiceManagement
import os.log

final class LoginItemService: ObservableObject {
    @Published var isEnabled: Bool

    private let logger = OSLog(subsystem: "com.kikinastudio.notchnotch", category: "LoginItem")

    init() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ newValue: Bool) {
        do {
            if newValue {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            isEnabled = SMAppService.mainApp.status == .enabled
        } catch {
            os_log("Failed to %{public}@ login item: %{public}@",
                   log: logger, type: .error,
                   newValue ? "register" : "unregister",
                   error.localizedDescription)
            isEnabled = SMAppService.mainApp.status == .enabled
        }
    }
}

import Foundation
import AppKit
import Combine
import Sparkle

private let pendingHintKey = "pendingPostUpdateGatekeeperHint"
private let pendingHintVersionKey = "pendingPostUpdateGatekeeperVersion"

/// Captures the version Sparkle is about to install so AppDelegate can show a
/// Gatekeeper hint dialog after the relaunch. Lives in its own class because
/// `SPUStandardUpdaterController` only accepts the delegate at init time.
private final class UpdaterDelegate: NSObject, SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: pendingHintKey)
        defaults.set(item.displayVersionString, forKey: pendingHintVersionKey)
    }
}

@MainActor
final class UpdaterService: ObservableObject {
    static let shared = UpdaterService()

    private let delegate = UpdaterDelegate()
    private let controller: SPUStandardUpdaterController

    init() {
        self.controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: delegate,
            userDriverDelegate: nil
        )
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    /// Called once at app launch from AppDelegate. If a Sparkle install just
    /// completed, show the Gatekeeper hint dialog and clear the flag.
    func presentPostUpdateGatekeeperHintIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: pendingHintKey) else { return }
        let version = defaults.string(forKey: pendingHintVersionKey) ?? ""
        defaults.removeObject(forKey: pendingHintKey)
        defaults.removeObject(forKey: pendingHintVersionKey)

        let alert = NSAlert()
        alert.messageText = version.isEmpty
            ? "Mise à jour installée"
            : "Mise à jour installée — v\(version)"
        alert.informativeText = """
        macOS va peut-être vous demander d'autoriser cette nouvelle version.

        Allez dans Réglages Système → Confidentialité et sécurité → \
        section Sécurité, puis cliquez « Ouvrir quand même » à côté de notchnotch.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Ouvrir Réglages")
        alert.addButton(withTitle: "Lire le guide")
        alert.addButton(withTitle: "OK")

        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?General") {
                NSWorkspace.shared.open(url)
            }
        case .alertSecondButtonReturn:
            if let url = URL(string: "https://github.com/KikinaStudio/NotchNotch/blob/master/docs/GATEKEEPER_FIRST_LAUNCH.md") {
                NSWorkspace.shared.open(url)
            }
        default:
            break
        }
    }
}

import AppKit
import Foundation
import SwiftUI
import os.log

/// Owns detection, install, and macOS privacy-panel deeplinks for the
/// `computer_use` system capability (Hermes 0.14.0+ `cua-driver`).
///
/// Pattern mirrors `GoogleConnectionState`: `@MainActor` so `@Published`
/// mutations from async `Task`s stay on the main runloop, singleton
/// (`shared`) so the same state is observable from any panel. Refresh on
/// init triggers a `which cua-driver` probe and logs the resolved state in
/// DEBUG builds — this is the signal of Session 1 wiring.
///
/// Install is an explicit user action: nothing here calls `install()`
/// automatically — that hook is reserved for the UI added in later sessions.
@MainActor
final class ComputerUseService: ObservableObject {
    static let shared = ComputerUseService()

    /// UserDefaults key for the last known TCC state of cua-driver
    /// (Accessibility + Screen Recording). The TCC grants belong to
    /// cua-driver's own identity (`com.trycua.driver`), so NotchNotch can't
    /// read them itself: `refreshState()` asks Hermes and stores every real
    /// answer here. The flag is only read when Hermes can't tell (no CuaDriver
    /// daemon running, Hermes older than v0.21.6): then it is the user's
    /// "C'est bon" click, a UI-side act of faith as before H13.
    private static let permissionsConfirmedKey = "computerUsePermissionsConfirmed"

    @Published var state: SystemCapabilityState = .notInstalled
    @Published var isInstalling: Bool = false
    @Published var installProgress: String = ""
    @Published var installError: String?
    /// True when Hermes can raise the macOS prompt itself
    /// (`hermes computer-use permissions grant`): its status answered in JSON,
    /// sees its cua-driver and reports `can_grant`. False on an older Hermes,
    /// where the views keep the System Settings links only.
    @Published var canGrant: Bool = false
    @Published var isGranting: Bool = false
    @Published var grantError: String?

    /// Only the latest `refreshState()` may write `state`: the Hermes check
    /// takes seconds and refreshes can overlap.
    private var refreshGeneration = 0

    private init() {
        Task { await refreshState() }
    }

    /// `which cua-driver`, then the real TCC state from Hermes → updates
    /// `state`. Spawns Hermes's CLI (~1 s, up to ~30 s with its own cua-driver
    /// timeouts): call it on events (launch, install, "C'est bon", opening the
    /// detail view), never from a view body.
    /// State derivation: missing binary → `.notInstalled`; Hermes reports both
    /// grants → `.ready`; Hermes reports one missing → `.installedPendingPermissions`;
    /// Hermes can't tell → the stored flag decides, as before H13.
    ///
    /// The session-1 console log goes through `os_log` (NOT `print`) so it
    /// shows up in Console.app and `log show` for both Debug and Release
    /// builds — Swift `print` doesn't reach the unified log for GUI bundles
    /// launched via `open`. Matches the existing `os_log` usage in
    /// `LoginItemService`.
    func refreshState() async {
        refreshGeneration += 1
        let generation = refreshGeneration
        let exists = await ShellRunner.commandExists("cua-driver")
        let status = exists ? await Self.fetchPermissionsStatus() : nil
        let granted = status?.granted
        // A newer refresh or an install started meanwhile: they own `state`.
        guard generation == refreshGeneration, !isInstalling else { return }
        canGrant = status?.canOfferGrant ?? false
        if !exists {
            state = .notInstalled
        } else if let granted {
            UserDefaults.standard.set(granted, forKey: Self.permissionsConfirmedKey)
            state = granted ? .ready : .installedPendingPermissions
        } else if UserDefaults.standard.bool(forKey: Self.permissionsConfirmedKey) {
            state = .ready
        } else {
            state = .installedPendingPermissions
        }
        os_log("[notchnotch] cua-driver state: %{public}@ (permissions: %{public}@)", type: .info,
               String(describing: state),
               granted.map { $0 ? "granted" : "missing" } ?? (exists ? "unknown" : "-"))
    }

    /// Called from the "C'est bon" buttons (detail view, onboarding). The user
    /// has walked through the System Settings panels: the state goes to
    /// `.ready` at once, then Hermes is asked. A real "missing" answer brings
    /// it back to `.installedPendingPermissions`; no answer keeps the click.
    func confirmPermissions() {
        UserDefaults.standard.set(true, forKey: Self.permissionsConfirmedKey)
        state = .ready
        Task { await refreshState() }
    }

    /// "Autoriser" button: `hermes computer-use permissions grant` (Hermes
    /// v0.21.6+, only offered when `canGrant`). cua-driver launches
    /// CuaDriver.app through LaunchServices so macOS asks for Accessibility +
    /// Screen Recording in CuaDriver's name, waits up to ~3 min for both, then
    /// asks for Tahoe's direct-capture consent; exit 0 = all granted and a live
    /// capture verified. Its daemon keeps running afterwards, so the status
    /// check that follows gets a real answer. The notch panel is lowered for
    /// the whole wait, else it would cover the system dialogs. Never called
    /// automatically: it opens system windows.
    func requestPermissionsGrant() async {
        guard !isGranting else { return }
        isGranting = true
        grantError = nil
        let hermesBinary = "\(NSHomeDirectory())/.local/bin/hermes"
        let result = await NotchPanel.withLoweredLevel {
            try? await ShellRunner.run("\(hermesBinary) computer-use permissions grant </dev/null")
        }
        let succeeded = result?.exitCode == 0
        os_log("[notchnotch] cua-driver permissions grant: exit %{public}d", type: .info,
               result?.exitCode ?? -1)
        if let output = result?.output {
            // cua-driver's own wording (English): what was granted, or what is
            // missing and how to recover. No secrets: paths and grant names.
            os_log("[notchnotch] cua-driver permissions grant output: %{public}@", type: .info,
                   String(output.suffix(600)))
        }
        // Fallback for refreshState when the status can't tell.
        UserDefaults.standard.set(succeeded, forKey: Self.permissionsConfirmedKey)
        isGranting = false
        await refreshState()
        if state != .ready {
            grantError = "macOS n'a pas encore tout accordé à CuaDriver. Réessaie, ou passe par les Réglages Système."
        }
    }

    /// `hermes computer-use permissions status --json` (Hermes v0.21.6+),
    /// read-only. Hermes asks cua-driver, which answers through its running
    /// daemon so the grants are CuaDriver's, not Hermes's nor NotchNotch's
    /// (`tools/computer_use/permissions.py`). Exit code is 1 whenever not
    /// ready, so only stdout counts; stderr is dropped.
    /// nil = no JSON: an older Hermes without the subcommand.
    private static func fetchPermissionsStatus() async -> PermissionsStatus? {
        let hermesBinary = "\(NSHomeDirectory())/.local/bin/hermes"
        guard let result = try? await ShellRunner.run(
            "\(hermesBinary) computer-use permissions status --json 2>/dev/null </dev/null"
        ), let data = result.output.data(using: .utf8)
        else { return nil }
        return try? JSONDecoder().decode(PermissionsStatus.self, from: data)
    }

    /// The fields NotchNotch reads from `permissions status --json`. Hermes
    /// also sends `ready`, but it is false for "unknown" too, so the two
    /// grants are read directly.
    private struct PermissionsStatus: Decodable {
        let installed: Bool
        let accessibility: Bool?
        let screenRecording: Bool?
        let canGrant: Bool?
        let error: String?

        enum CodingKeys: String, CodingKey {
            case installed, accessibility, error
            case screenRecording = "screen_recording"
            case canGrant = "can_grant"
        }

        /// true = both grants, false = at least one explicitly missing,
        /// nil = unknown: no CuaDriver daemon running (cua-driver reports
        /// `unknown`, Hermes `null`), cua-driver timeout, or a PM-less install
        /// Hermes doesn't see.
        var granted: Bool? {
            guard installed, error == nil else { return nil }
            if accessibility == false || screenRecording == false { return false }
            if accessibility == true, screenRecording == true { return true }
            return nil
        }

        /// macOS, cua-driver backend (not another computer-use plugin), and a
        /// binary Hermes can launch.
        var canOfferGrant: Bool { installed && canGrant == true }
    }

    /// Wraps `hermes computer-use install`. The underlying script downloads
    /// the cua-driver binary (~50MB) and may take 10–90s. `ShellRunner.run`
    /// is bulk-blocking so we surface progress as a single static message
    /// rather than streaming per-line — line-level streaming will require a
    /// dedicated AsyncSequence variant in a later session.
    ///
    /// On success, writes `approvals.mode: manual` into `~/.hermes/config.yaml`.
    /// This is the safe default for non-technical users — Hermes will ask
    /// before running anything sensitive. For most users the value is already
    /// `manual` (it's the Hermes default), so the write is a no-op; matters
    /// for fresh installs where the user may have explicitly set another value.
    ///
    /// Never called automatically; an explicit UI button must trigger this.
    func install() async {
        isInstalling = true
        installError = nil
        installProgress = "Installation de cua-driver en cours…"
        state = .installing

        let hermesBinary = "\(NSHomeDirectory())/.local/bin/hermes"
        do {
            let result = try await ShellRunner.run("\(hermesBinary) computer-use install")
            if result.exitCode != 0 {
                let raw = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
                installError = raw.isEmpty
                    ? "Échec de l'installation (code \(result.exitCode))"
                    : String(raw.prefix(500))
            } else {
                // Hermes CLI exit-0 ≠ install réussie : `cmd_computer_use`
                // dans hermes_cli/main.py:11351 ignore la valeur de retour de
                // `install_cua_driver()` et exit toujours 0. Si l'upstream
                // install.sh a échoué silencieusement (réseau, curl manquant,
                // permission de download), le binaire n'est pas sur PATH et
                // l'user retombait sur pitchPhase "comme s'il n'avait pas
                // cliqué". On re-vérifie le binaire et on synthétise une
                // erreur explicite si absent.
                let exists = await ShellRunner.commandExists("cua-driver")
                if exists {
                    HermesConfig.shared.setImmediate("approvals.mode", value: "manual")
                } else {
                    let raw = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
                    let suffix = raw.isEmpty ? "" : "\n\n\(String(raw.prefix(400)))"
                    installError = "L'installation s'est terminée sans réussir à poser cua-driver sur ton PATH. Vérifie ta connexion et réessaie, ou consulte la doc.\(suffix)"
                }
            }
        } catch {
            installError = error.localizedDescription
        }

        isInstalling = false
        await refreshState()
    }

    // MARK: - macOS privacy-panel deeplinks
    //
    // Each `openX` method opens the corresponding pane in System Settings.
    // `NSWorkspace.shared.open(URL)` returns Bool but we ignore it — on
    // macOS 14+ this scheme is always honored.

    func openAccessibilitySettings() {
        NSWorkspace.shared.open(
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        )
    }

    func openScreenRecordingSettings() {
        NSWorkspace.shared.open(
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        )
    }

    func openAutomationSettings() {
        NSWorkspace.shared.open(
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!
        )
    }
}

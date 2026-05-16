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

    /// UserDefaults key for the user's confirmation that they've granted
    /// macOS TCC permissions (Accessibility / Screen Recording / Automation).
    /// We cannot verify these programmatically — cua-driver is a separate
    /// binary with its own bundle-id, scoped TCC grants. The flag is a
    /// UI-side act of faith: the user clicks "C'est bon" after walking
    /// through the panels.
    private static let permissionsConfirmedKey = "computerUsePermissionsConfirmed"

    @Published var state: SystemCapabilityState = .notInstalled
    @Published var isInstalling: Bool = false
    @Published var installProgress: String = ""
    @Published var installError: String?

    private init() {
        Task { await refreshState() }
    }

    /// `which cua-driver` → updates `state`. Cheap; safe to call after any
    /// install attempt or whenever the user returns from a permission panel.
    /// State derivation: missing binary → `.notInstalled`; binary present and
    /// the UserDefaults confirmation flag is true → `.ready`; otherwise
    /// `.installedPendingPermissions` (binary on PATH but permissions not
    /// confirmed yet).
    ///
    /// The session-1 console log goes through `os_log` (NOT `print`) so it
    /// shows up in Console.app and `log show` for both Debug and Release
    /// builds — Swift `print` doesn't reach the unified log for GUI bundles
    /// launched via `open`. Matches the existing `os_log` usage in
    /// `AppDelegate.probeCompressionEndpointOnce` and `LoginItemService`.
    func refreshState() async {
        let exists = await ShellRunner.commandExists("cua-driver")
        if !exists {
            state = .notInstalled
        } else if UserDefaults.standard.bool(forKey: Self.permissionsConfirmedKey) {
            state = .ready
        } else {
            state = .installedPendingPermissions
        }
        os_log("[notchnotch] cua-driver state: %{public}@", type: .info, String(describing: state))
    }

    /// Called from the detail view's "C'est bon" button. The user has just
    /// walked through the 3 System Settings panels and tells us they've
    /// granted the permissions. We persist the flag and bump the state to
    /// `.ready` so the UI updates immediately without waiting for a refresh.
    func confirmPermissions() {
        UserDefaults.standard.set(true, forKey: Self.permissionsConfirmedKey)
        state = .ready
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
                HermesConfig.shared.setImmediate("approvals.mode", value: "manual")
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

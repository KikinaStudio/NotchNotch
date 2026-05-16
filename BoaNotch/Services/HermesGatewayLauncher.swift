import AppKit
import Foundation
import os.log

/// Owns the user-scoped LaunchAgent that auto-starts the Hermes gateway at
/// login (and keeps it running). Hermes's own install.sh does NOT register
/// any launchd service, so without this NotchNotch users would need to keep
/// a Terminal window open with `hermes gateway run` — exactly the friction
/// we're trying to remove for non-tech users.
///
/// Doctrine matches `ComputerUseService`: `@MainActor` singleton so
/// `@Published` state stays main-thread-safe across async Tasks. The
/// service is touched once at `applicationDidFinishLaunching` to kick off
/// the lazy init (`private init() → refreshState()`).
///
/// LaunchAgent path is user-scoped (`~/Library/LaunchAgents/`), so no sudo,
/// no admin password, no TCC grants required. The plist Label
/// `ai.hermes.gateway` matches the existing Hermes community convention
/// (so we don't shadow / port-collide with manually-installed agents).
///
/// Documented exception to "everything-through-chat" — see CLAUDE.md
/// "Documented exception — LaunchAgent for hermes gateway".
@MainActor
final class HermesGatewayLauncher: ObservableObject {
    static let shared = HermesGatewayLauncher()

    /// Label used as the launchd Job's identifier AND as the plist filename.
    /// Matches the existing Hermes community convention so this code
    /// transparently takes over plists installed by the user manually or by
    /// older NotchNotch builds with the same label.
    static let label = "ai.hermes.gateway"

    enum LaunchAgentState: Equatable {
        /// No plist at our expected path.
        case notInstalled
        /// Plist on disk AND launchctl reports the job is loaded.
        case installedAndLoaded
        /// Plist on disk but launchctl can't find it (e.g. user logged out,
        /// or unloaded manually). Calling `install()` re-loads it.
        case installedNotLoaded
    }

    enum LauncherError: LocalizedError {
        case hermesNotInstalled
        case plistWriteFailed(String)
        case launchctlFailed(stage: String, code: Int32, output: String)

        var errorDescription: String? {
            switch self {
            case .hermesNotInstalled:
                return "Hermes n'est pas installé (~/.hermes/hermes-agent introuvable). Termine d'abord l'installation."
            case .plistWriteFailed(let path):
                return "Impossible d'écrire le LaunchAgent à \(path)."
            case .launchctlFailed(let stage, let code, let output):
                let snippet = output.trimmingCharacters(in: .whitespacesAndNewlines)
                if snippet.isEmpty {
                    return "launchctl \(stage) a échoué (code \(code))."
                }
                return "launchctl \(stage) a échoué (code \(code)): \(snippet.prefix(200))"
            }
        }
    }

    @Published var state: LaunchAgentState = .notInstalled

    /// Resolved at init from `NSHomeDirectory()`. All paths in the plist are
    /// absolute strings (never `~` literals — launchd does not expand them).
    private let home: String
    private let plistPath: String
    private let venvPython: String
    private let hermesEntrypoint: String
    private let workingDir: String
    private let logsDir: String

    private init() {
        self.home = NSHomeDirectory()
        self.plistPath = "\(home)/Library/LaunchAgents/\(Self.label).plist"
        self.workingDir = "\(home)/.hermes/hermes-agent"
        self.venvPython = "\(workingDir)/venv/bin/python3"
        self.hermesEntrypoint = "\(workingDir)/hermes"
        self.logsDir = "\(home)/.hermes/logs"
        refreshState()
    }

    // MARK: - State detection

    /// Recompute `state` from disk + `launchctl print`. Cheap (~10ms). Call
    /// after install / uninstall / kickstart, or on `applicationDidFinishLaunching`.
    func refreshState() {
        let fm = FileManager.default
        let plistExists = fm.fileExists(atPath: plistPath)
        guard plistExists else {
            state = .notInstalled
            return
        }
        // `launchctl print gui/<uid>/<label>` returns exit 0 when loaded,
        // non-zero (typically 113 = ESRCH) when not. We don't parse the
        // output — just the exit code tells us what we need.
        let printed = runLaunchctlSync(["print", "gui/\(getuid())/\(Self.label)"])
        state = printed.exitCode == 0 ? .installedAndLoaded : .installedNotLoaded
        os_log("[notchnotch] LaunchAgent state: %{public}@",
               type: .info,
               String(describing: state))
    }

    // MARK: - Reachability probe (1s timeout)

    /// GET http://localhost:8642/health with a 1-second timeout. Used to
    /// decide whether to advance after install, and whether the actionable
    /// toast should offer "install" or "kickstart".
    func isHermesReachable() async -> Bool {
        guard let url = URL(string: "http://localhost:8642/health") else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 1.0
        request.httpMethod = "GET"

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 1.0
        config.timeoutIntervalForResource = 1.0
        let session = URLSession(configuration: config)

        do {
            let (_, response) = try await session.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    // MARK: - Install / uninstall / kickstart

    /// Write the plist (if missing or outdated) and bootstrap it into
    /// launchd's gui domain. Idempotent: a no-op on a healthy install (plist
    /// content matches AND launchctl reports loaded). On a partial state
    /// (plist matches but not loaded, or plist outdated), the helper does
    /// the minimum work to reconcile.
    ///
    /// Throws `LauncherError.hermesNotInstalled` if the venv binary is
    /// missing — installing a plist that points to a non-existent program
    /// would crash-loop forever under KeepAlive.
    func install() throws {
        let fm = FileManager.default

        // Refuse to install a broken plist. Hermes's venv must exist or
        // KeepAlive turns this into a crash-loop nightmare.
        guard fm.fileExists(atPath: venvPython),
              fm.fileExists(atPath: hermesEntrypoint) else {
            throw LauncherError.hermesNotInstalled
        }

        // Ensure ~/.hermes/logs/ exists so launchd doesn't error on
        // StandardOutPath. Created idempotently — failures here are
        // non-fatal; launchd will surface a permission error in the log
        // if writing fails downstream.
        try? fm.createDirectory(atPath: logsDir, withIntermediateDirectories: true)

        let desiredPlist = renderPlist()
        let existingPlist = (try? String(contentsOfFile: plistPath, encoding: .utf8)) ?? ""

        // If contents are byte-identical AND the job is already loaded,
        // we're done — no need to bootout/bootstrap.
        if existingPlist == desiredPlist && state == .installedAndLoaded {
            os_log("[notchnotch] LaunchAgent already healthy — no-op", type: .info)
            return
        }

        // Ensure the parent dir exists (it does on every macOS but cheap
        // to be defensive).
        let plistDir = (plistPath as NSString).deletingLastPathComponent
        try? fm.createDirectory(atPath: plistDir, withIntermediateDirectories: true)

        // Atomically replace the plist if contents differ.
        if existingPlist != desiredPlist {
            do {
                try desiredPlist.write(toFile: plistPath, atomically: true, encoding: .utf8)
            } catch {
                throw LauncherError.plistWriteFailed(plistPath)
            }
            os_log("[notchnotch] LaunchAgent plist written to %{public}@", type: .info, plistPath)
        }

        // If currently loaded, bootout first so the new plist takes effect.
        // `launchctl bootout` (macOS 11+) is the modern replacement for
        // `unload -w`. Ignore exit code — a "not loaded" error here is
        // benign and means the work below is correct anyway.
        if state == .installedAndLoaded {
            _ = runLaunchctlSync(["bootout", "gui/\(getuid())/\(Self.label)"])
        }

        // Bootstrap into the gui domain so it runs as the user (not root).
        // On macOS 11+ this is the canonical entry point. We fall back to
        // `load -w` for older systems just in case.
        let bootstrap = runLaunchctlSync(["bootstrap", "gui/\(getuid())", plistPath])
        if bootstrap.exitCode != 0 {
            os_log("[notchnotch] bootstrap failed (code %d), trying load -w fallback: %{public}@",
                   type: .info,
                   bootstrap.exitCode,
                   bootstrap.output)
            let load = runLaunchctlSync(["load", "-w", plistPath])
            if load.exitCode != 0 {
                refreshState()
                throw LauncherError.launchctlFailed(
                    stage: "bootstrap",
                    code: bootstrap.exitCode,
                    output: bootstrap.output.isEmpty ? load.output : bootstrap.output
                )
            }
        }

        refreshState()
    }

    /// Stop and remove our LaunchAgent. Best-effort: missing plist or
    /// already-unloaded job are silent successes.
    func uninstall() throws {
        // Bootout first (no-op if not loaded).
        _ = runLaunchctlSync(["bootout", "gui/\(getuid())/\(Self.label)"])
        // Then drop the plist file.
        if FileManager.default.fileExists(atPath: plistPath) {
            try? FileManager.default.removeItem(atPath: plistPath)
        }
        refreshState()
    }

    /// Force-restart a loaded job. Useful when /health is silent but
    /// launchctl reports the job is loaded (most likely scenario: stuck
    /// agent task, transient process hang).
    func kickstart() {
        // -k = kill the running instance, launchd will relaunch via RunAtLoad/KeepAlive
        _ = runLaunchctlSync(["kickstart", "-k", "gui/\(getuid())/\(Self.label)"])
    }

    /// Reveal the gateway log file in Finder if it exists, otherwise reveal
    /// the logs directory. Used by the Settings → Hermes section.
    func revealLogs() {
        let mainLog = "\(logsDir)/gateway.log"
        let url: URL
        if FileManager.default.fileExists(atPath: mainLog) {
            url = URL(fileURLWithPath: mainLog)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            url = URL(fileURLWithPath: logsDir)
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - launchctl helper

    private struct LaunchctlResult {
        let output: String
        let exitCode: Int32
    }

    private func runLaunchctlSync(_ arguments: [String]) -> LaunchctlResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            return LaunchctlResult(output: output, exitCode: process.terminationStatus)
        } catch {
            return LaunchctlResult(output: error.localizedDescription, exitCode: -1)
        }
    }

    // MARK: - Plist template

    /// Render the canonical NotchNotch LaunchAgent plist. All paths absolute.
    /// `--replace` on `gateway run` is the safety net: if any other gateway
    /// instance is already bound to :8642 when launchd starts ours, it kills
    /// the predecessor and takes over cleanly. Combined with our idempotent
    /// install, this also handles the "user has Hermes running in Terminal"
    /// case without a confirmation dialog — the LaunchAgent wins gracefully.
    private func renderPlist() -> String {
        let pathEntries = [
            "\(workingDir)/venv/bin",
            "\(workingDir)/node_modules/.bin",
            "\(home)/.hermes/node/bin",
            "\(home)/.local/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
        ]
        let pathValue = pathEntries.joined(separator: ":")

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(Self.label)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(venvPython)</string>
                <string>\(hermesEntrypoint)</string>
                <string>gateway</string>
                <string>run</string>
                <string>--replace</string>
            </array>
            <key>WorkingDirectory</key>
            <string>\(workingDir)</string>
            <key>EnvironmentVariables</key>
            <dict>
                <key>PATH</key>
                <string>\(pathValue)</string>
                <key>VIRTUAL_ENV</key>
                <string>\(workingDir)/venv</string>
                <key>HERMES_HOME</key>
                <string>\(home)/.hermes</string>
            </dict>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <dict>
                <key>SuccessfulExit</key>
                <false/>
            </dict>
            <key>StandardOutPath</key>
            <string>\(logsDir)/gateway.log</string>
            <key>StandardErrorPath</key>
            <string>\(logsDir)/gateway.error.log</string>
        </dict>
        </plist>
        """
    }
}

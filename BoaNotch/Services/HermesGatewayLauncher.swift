import AppKit
import Foundation
import Security
import os.log

/// Keeps the Hermes gateway running at login and its API server reachable.
///
/// Hermes owns its LaunchAgent (`~/Library/LaunchAgents/ai.hermes.gateway.plist`,
/// osascript wrapper + `--external-supervisor`, rewritten by `hermes update`).
/// NotchNotch never writes that plist: it delegates to `hermes gateway
/// start / restart / uninstall`, and only reads launchd state to drive the UI.
/// It also owns the `API_SERVER_*` lines of `~/.hermes/.env` that Hermes needs
/// to open :8642 (see `ensureApiServerEnv()`).
///
/// Doctrine matches `ComputerUseService`: `@MainActor` singleton so
/// `@Published` state stays main-thread-safe across async Tasks. The
/// service is touched once at `applicationDidFinishLaunching` to kick off
/// the lazy init (`private init() → refreshState()`).
///
/// Documented exceptions to "everything-through-chat" — see CLAUDE.md
/// "Documented exception — LaunchAgent for hermes gateway" and
/// "Documented exception — `API_SERVER_ENABLED` + `API_SERVER_KEY` + `model.max_tokens` direct writes".
@MainActor
final class HermesGatewayLauncher: ObservableObject {
    static let shared = HermesGatewayLauncher()

    /// Label of Hermes's launchd job, also the plist filename.
    static let label = "ai.hermes.gateway"

    enum LaunchAgentState: Equatable {
        /// No plist at the expected path.
        case notInstalled
        /// Plist on disk AND launchctl reports the job is loaded.
        case installedAndLoaded
        /// Plist on disk but launchctl can't find it (e.g. user logged out,
        /// or unloaded manually). Calling `install()` re-loads it.
        case installedNotLoaded
    }

    enum LauncherError: LocalizedError {
        case hermesNotInstalled
        case commandFailed(command: String, code: Int32, output: String)

        var errorDescription: String? {
            switch self {
            case .hermesNotInstalled:
                return "Hermes n'est pas installé (~/.local/bin/hermes introuvable). Termine d'abord l'installation."
            case .commandFailed(let command, let code, let output):
                let snippet = output.trimmingCharacters(in: .whitespacesAndNewlines)
                if snippet.isEmpty {
                    return "\(command) a échoué (code \(code))."
                }
                return "\(command) a échoué (code \(code)) : \(snippet.suffix(200))"
            }
        }
    }

    @Published var state: LaunchAgentState = .notInstalled

    private let plistPath: String
    private let hermesCLI: String
    private let logsDir: String

    private init() {
        let home = NSHomeDirectory()
        self.plistPath = "\(home)/Library/LaunchAgents/\(Self.label).plist"
        self.hermesCLI = "\(home)/.local/bin/hermes"
        self.logsDir = "\(home)/.hermes/logs"
        refreshState()
    }

    // MARK: - State detection

    /// Recompute `state` from disk + `launchctl print`. Cheap (~10ms). Call
    /// after install / uninstall / restart, or on `applicationDidFinishLaunching`.
    func refreshState() {
        let plistExists = FileManager.default.fileExists(atPath: plistPath)
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
    /// toast should offer "install" or "restart". `/health` needs no key.
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

    // MARK: - API server env (.env)

    /// Make sure ~/.hermes/.env lets Hermes open :8642. Writes
    /// `API_SERVER_ENABLED=true` and `API_SERVER_CORS_ORIGINS=*` only when absent
    /// (an explicit value is respected), and `API_SERVER_KEY` only when absent or
    /// unusable — v0.21.6+ keeps the port closed without a 16+ char key. A valid
    /// key is NEVER replaced: other clients use it. Restarts the gateway once when
    /// something was written and the job is loaded. Returns true when it wrote.
    /// Called at boot, at onboarding and by the chat repair flow.
    @discardableResult
    func ensureApiServerEnv() async -> Bool {
        // No Hermes yet → don't create an orphan .env.
        guard FileManager.default.fileExists(atPath: hermesCLI) else { return false }
        let config = HermesConfig.shared
        var wrote = false
        for (key, value) in [("API_SERVER_ENABLED", "true"), ("API_SERVER_CORS_ORIGINS", "*")]
        where config.readRawEnv(key: key) == nil {
            config.writeRawEnv(key: key, value: value)
            wrote = true
        }
        if !Self.isUsableKey(config.readRawEnv(key: "API_SERVER_KEY")), let key = Self.generateKey() {
            config.writeRawEnv(key: "API_SERVER_KEY", value: key)
            wrote = true
        }
        guard wrote else { return false }
        os_log("[notchnotch] Wrote missing API_SERVER_* vars to ~/.hermes/.env", type: .info)
        refreshState()
        if state == .installedAndLoaded { await restart() }
        return true
    }

    /// Mirrors `has_usable_secret(min_length=16)` in hermes_cli/auth.py:
    /// length, `your_…_here` and all-x placeholders.
    static func isUsableKey(_ key: String?) -> Bool {
        guard let key = key?.trimmingCharacters(in: .whitespaces).lowercased(),
              key.count >= 16 else { return false }
        if key.hasPrefix("your_") && key.hasSuffix("_here") { return false }
        return key.contains { !"x-_ ".contains($0) }
    }

    /// 32 random bytes as hex: no `#`, quote or space for the dotenv parser to trip on.
    private static func generateKey() -> String? {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { return nil }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Install / uninstall / restart (delegated to Hermes)

    /// `hermes gateway start`: Hermes writes its plist when missing, refreshes
    /// an outdated one (older NotchNotch template included), loads it and
    /// starts the gateway — a no-op when it already runs.
    /// (`install --if-missing` would leave an unloaded plist unloaded.)
    func install() async throws {
        defer { refreshState() }
        try await runHermes("gateway start")
    }

    /// `hermes gateway uninstall`: bootout + plist removal. Best-effort.
    func uninstall() async {
        defer { refreshState() }
        do {
            try await runHermes("gateway uninstall")
        } catch {
            os_log("[notchnotch] gateway uninstall failed: %{public}@", type: .info, error.localizedDescription)
        }
    }

    /// `hermes gateway restart`: graceful drain, then relaunch (reloads an
    /// unloaded job). Used when /health is silent or .env changed. Can take
    /// tens of seconds while in-flight runs drain.
    func restart() async {
        do {
            try await runHermes("gateway restart")
        } catch {
            os_log("[notchnotch] gateway restart failed: %{public}@", type: .info, error.localizedDescription)
        }
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

    // MARK: - Process helpers

    private func runHermes(_ arguments: String) async throws {
        guard FileManager.default.fileExists(atPath: hermesCLI) else {
            throw LauncherError.hermesNotInstalled
        }
        let result = try await ShellRunner.run("\"\(hermesCLI)\" \(arguments)")
        guard result.exitCode == 0 else {
            throw LauncherError.commandFailed(command: "hermes \(arguments)", code: result.exitCode, output: result.output)
        }
    }

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
}

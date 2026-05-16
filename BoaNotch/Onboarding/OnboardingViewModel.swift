import Foundation
import AppKit
import SwiftUI

class OnboardingViewModel: ObservableObject {
    // MARK: - Step state

    @Published var currentStep: Int {
        didSet { UserDefaults.standard.set(currentStep, forKey: "onboardingStep") }
    }

    @Published var selectedProvider: String {
        didSet { UserDefaults.standard.set(selectedProvider, forKey: "selectedProvider") }
    }

    // MARK: - Install state

    @Published var isInstalling = false
    @Published var installStatus = ""
    @Published var installError: String?
    @Published var needsGitInstall = false

    // MARK: - Telegram state

    @Published var telegramToken = ""
    @Published var telegramConnected = false

    // MARK: - Connect-provider step state

    /// Which provider's "paste your own key" panel is currently open in the
    /// Connect step. nil = nothing selected (only the big OAuth button is
    /// visible). Defaults to nil at session start; the segmented row reveals
    /// the API-key field as soon as the user picks a provider.
    @Published var advancedProvider: String? = nil
    @Published var advancedAPIKey: String = ""
    @Published var isConnecting: Bool = false
    @Published var connectError: String?

    /// Pages where each provider lets you generate / view API keys. Shown as a
    /// small "Get a key at …" link below the API-key field.
    static let providerKeyURLs: [String: String] = [
        "openrouter": "https://openrouter.ai/settings/keys",
        "openai":     "https://platform.openai.com/api-keys",
        "anthropic":  "https://console.anthropic.com/settings/keys",
        "minimax":    "https://www.minimax.io/platform/user-center/basic-information/interface-key",
    ]

    // Reference to notchVM for suppressing auto-close
    weak var notchVM: NotchViewModel?

    private let hermesHome: String

    /// Sticky flag — set once at init, only cleared by `completeOnboarding()`.
    @Published var needsOnboarding: Bool

    // MARK: - Init

    init() {
        let home = ProcessInfo.processInfo.environment["HERMES_HOME"]
            ?? "\(NSHomeDirectory())/.hermes"
        self.hermesHome = home

        let step = UserDefaults.standard.integer(forKey: "onboardingStep")
        self.currentStep = step
        self.selectedProvider = UserDefaults.standard.string(forKey: "selectedProvider") ?? "openrouter"

        // Determine once at launch whether onboarding is needed
        if UserDefaults.standard.bool(forKey: "onboardingCompleted") {
            self.needsOnboarding = false
        } else if step > 0 {
            // Mid-flow from a previous launch
            self.needsOnboarding = true
        } else {
            let configExists = FileManager.default.fileExists(atPath: "\(home)/config.yaml")
            self.needsOnboarding = !configExists
        }
    }

    // MARK: - Navigation

    func advance() {
        withAnimation {
            currentStep += 1
        }
    }

    func goBack() {
        withAnimation {
            currentStep = max(0, currentStep - 1)
        }
    }

    // MARK: - Connect-provider step actions

    /// OAuth PKCE flow against OpenRouter. Writes the resulting key into
    /// ~/.hermes/.env, sets provider/base_url/model.default in config.yaml,
    /// then advances. User-cancelled errors are swallowed silently.
    @MainActor
    func connectOpenRouter() async {
        isConnecting = true
        connectError = nil
        do {
            _ = try await OpenRouterOAuthService.shared.connect()
            selectedProvider = "openrouter"
            isConnecting = false
            advance()
        } catch let err as OpenRouterOAuthService.OAuthError {
            isConnecting = false
            if case .userCancelled = err { return }
            connectError = err.localizedDescription
        } catch {
            isConnecting = false
            connectError = error.localizedDescription
        }
    }

    /// Aborts the in-flight OAuth wait. The OAuth task's `catch` clause sees
    /// `.userCancelled` and silently flips `isConnecting` back to false.
    @MainActor
    func cancelOpenRouterOAuth() {
        OpenRouterOAuthService.shared.cancelInFlight()
    }

    /// "Paste your own key" path for non-OpenRouter providers. Writes the key
    /// into .env, points config.yaml at the provider + its default base URL,
    /// and seeds model.default with the first model in HermesConfig's list.
    func saveAdvancedKey(provider: String) {
        let trimmed = advancedAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let cfg = HermesConfig.shared
        cfg.writeAPIKey(provider: provider, key: trimmed)
        cfg.modelProvider = provider
        cfg.setImmediate("model.provider", value: provider)
        if let baseURL = HermesConfig.defaultBaseURL(for: provider) {
            cfg.setImmediate("model.base_url", value: baseURL)
        }
        if let firstModel = cfg.availableModels.first {
            cfg.setImmediate("model.default", value: firstModel.value)
        }
        selectedProvider = provider
        advancedAPIKey = ""
        advance()
    }

    // MARK: - Hermes installation

    func installHermes() {
        isInstalling = true
        installError = nil
        installStatus = "Checking installation..."

        Task { @MainActor in
            // If Hermes is already installed, skip the installer entirely
            let configExists = FileManager.default.fileExists(atPath: "\(hermesHome)/config.yaml")
            let hermesInLocalBin = FileManager.default.fileExists(atPath: "\(NSHomeDirectory())/.local/bin/hermes")
            let hermesRepoExists = FileManager.default.fileExists(atPath: "\(hermesHome)/.git")

            if configExists || hermesInLocalBin || hermesRepoExists {
                // Already installed — if config.yaml is missing, try running hermes init
                if !configExists && hermesInLocalBin {
                    installStatus = "Configuring..."
                    let _ = try? await ShellRunner.run("\(NSHomeDirectory())/.local/bin/hermes init --non-interactive")
                }
                // Ensure the gateway auto-starts at login. Even if Hermes
                // was already installed, an existing user may have it
                // running only via a Terminal window (or not at all). The
                // LaunchAgent makes the chat work after every reboot
                // without any manual command. Idempotent.
                await ensureLaunchAgentAndAwaitHealth()
                installStatus = "Done!"
                isInstalling = false
                advance()
                return
            }

            // Check git first
            let hasGit = await ShellRunner.commandExists("git")
            if !hasGit {
                needsGitInstall = true
                installStatus = "Installing developer tools..."
                // Trigger Xcode CLT install
                let _ = try? await ShellRunner.run("/usr/bin/xcode-select --install")
                // Wait and re-check
                for _ in 0..<60 {
                    try? await Task.sleep(for: .seconds(5))
                    if await ShellRunner.commandExists("git") {
                        needsGitInstall = false
                        break
                    }
                }
                if needsGitInstall {
                    installError = "Git installation timed out. Please install Xcode Command Line Tools and try again."
                    isInstalling = false
                    return
                }
            }

            // Start cosmetic status timer
            let statusTask = Task { @MainActor in
                let statuses = [
                    "Downloading Hermes Agent...",
                    "Installing dependencies...",
                    "Setting up Python environment...",
                    "Configuring...",
                    "Almost ready...",
                ]
                for (i, status) in statuses.enumerated() {
                    if i > 0 {
                        try? await Task.sleep(for: .seconds(18))
                    }
                    guard !Task.isCancelled else { return }
                    self.installStatus = status
                }
            }

            // Run the installer
            do {
                let result = try await ShellRunner.run(
                    "curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh | bash"
                )
                statusTask.cancel()

                if result.exitCode == 0 {
                    // Verify config.yaml was created
                    let configExists = FileManager.default.fileExists(atPath: "\(hermesHome)/config.yaml")
                    if configExists {
                        // Auto-start Hermes at login + wait for /health so
                        // the chat actually works on the very first message.
                        // The 10s poll is the typical cold-start window.
                        installStatus = "Starting Hermes..."
                        await ensureLaunchAgentAndAwaitHealth()
                        installStatus = "Done!"
                        isInstalling = false
                        advance()
                    } else {
                        installError = "Installation completed but config.yaml was not created.\n\n\(lastLines(result.output, count: 5))"
                        isInstalling = false
                    }
                } else {
                    installError = "Installation failed (exit code \(result.exitCode)).\n\n\(lastLines(result.output, count: 8))"
                    isInstalling = false
                }
            } catch {
                statusTask.cancel()
                installError = "Installation error: \(error.localizedDescription)"
                isInstalling = false
            }
        }
    }

    // MARK: - Telegram

    func connectTelegram() {
        guard !telegramToken.isEmpty else { return }

        let envPath = "\(hermesHome)/.env"
        var content = (try? String(contentsOfFile: envPath, encoding: .utf8)) ?? ""
        if !content.isEmpty && !content.hasSuffix("\n") {
            content += "\n"
        }
        content += "TELEGRAM_BOT_TOKEN=\(telegramToken)\n"
        content += "TELEGRAM_ALLOWED_USERS=*\n"
        try? content.write(toFile: envPath, atomically: true, encoding: .utf8)

        telegramConnected = true
    }

    // MARK: - Complete

    func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "onboardingCompleted")
        UserDefaults.standard.removeObject(forKey: "onboardingStep")
        needsOnboarding = false
        notchVM?.suppressAutoClose = false
    }

    // MARK: - LaunchAgent + health bridge

    /// Idempotently install the LaunchAgent and wait up to 10s for the
    /// gateway to answer `/health`. The 10s window covers Hermes's normal
    /// cold-start (Python import + socket bind). Any failure here is
    /// soft — we still advance so the user can keep onboarding; the
    /// actionable "Hermes ne répond pas" toast handles the retry path on
    /// the chat side if we couldn't bring it up here.
    @MainActor
    private func ensureLaunchAgentAndAwaitHealth() async {
        // API_SERVER_ENABLED=true gates Platform.API_SERVER in
        // gateway/config.py:1478 — without it Hermes runs in cron-only
        // mode (no port 8642) and NotchNotch can't reach it. The
        // upstream install.sh doesn't set this, so we do it here on
        // every onboarding pass. CORS=* lets the browser-based Clipper
        // extension talk to the local gateway. writeRawEnv is idempotent.
        HermesConfig.shared.writeRawEnv(key: "API_SERVER_ENABLED", value: "true")
        HermesConfig.shared.writeRawEnv(key: "API_SERVER_CORS_ORIGINS", value: "*")

        let launcher = HermesGatewayLauncher.shared
        do {
            try launcher.install()
        } catch {
            // Hermes binary missing or launchctl refused — log and bail.
            // The chat-side actionable toast covers this case on first
            // unreachable response.
            print("[notchnotch] LaunchAgent install during onboarding failed: \(error.localizedDescription)")
            return
        }
        for _ in 0..<10 {
            if await launcher.isHermesReachable() { return }
            try? await Task.sleep(for: .seconds(1))
        }
    }

    // MARK: - Helpers

    private func lastLines(_ text: String, count: Int) -> String {
        let lines = text.components(separatedBy: "\n").filter { !$0.isEmpty }
        return lines.suffix(count).joined(separator: "\n")
    }

    private func withAnimation(_ body: () -> Void) {
        SwiftUI.withAnimation(.easeInOut(duration: 0.25)) {
            body()
        }
    }
}

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

    // MARK: - Model selection

    @Published var selectedModel = ""

    // Reference to notchVM for suppressing auto-close
    weak var notchVM: NotchViewModel?
    // Reference to hermesConfig for writing model choice
    weak var hermesConfig: HermesConfig?

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
        self.selectedProvider = UserDefaults.standard.string(forKey: "selectedProvider") ?? ""

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

    // MARK: - API key storage (~/.hermes/.env)

    func writeAPIKey(provider: String, key: String) {
        let envKey: String
        switch provider {
        case "openai": envKey = "OPENAI_API_KEY"
        case "anthropic": envKey = "ANTHROPIC_API_KEY"
        default: envKey = "OPENROUTER_API_KEY"
        }

        let dir = hermesHome
        let envPath = "\(dir)/.env"

        // Create directory if needed
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        // Read existing content (if any) and append
        var content = (try? String(contentsOfFile: envPath, encoding: .utf8)) ?? ""
        if !content.isEmpty && !content.hasSuffix("\n") {
            content += "\n"
        }
        content += "\(envKey)=\(key)\n"

        try? content.write(toFile: envPath, atomically: true, encoding: .utf8)
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

    // MARK: - Model choice

    func writeModelChoice() {
        guard !selectedModel.isEmpty else { return }

        let provider: String
        switch selectedProvider {
        case "openai": provider = "openai"
        case "anthropic": provider = "anthropic"
        case "openrouter": provider = "openrouter"
        default: provider = "nous"
        }

        hermesConfig?.setImmediate("model.default", value: selectedModel)
        hermesConfig?.setImmediate("model.provider", value: provider)
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

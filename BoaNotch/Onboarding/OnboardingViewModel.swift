import Foundation
import AppKit
import SwiftUI
import os.log

/// The four onboarding screens (H14). Raw values are persisted in
/// `onboardingStep`; Contrôle du Mac lives in Settings, Telegram left.
enum OnboardingStep: Int, CaseIterable {
    case welcome, install, connect, ready
}

class OnboardingViewModel: ObservableObject {
    // MARK: - Step state

    @Published var currentStep: OnboardingStep {
        didSet { UserDefaults.standard.set(currentStep.rawValue, forKey: "onboardingStep") }
    }

    /// Set once `onboardingStep` holds the H14 scale (0–3). Absent = the value,
    /// if any, comes from a pre-H14 build (0–6) and is remapped once in `init`.
    private static let stepScaleKey = "onboardingStepScaleH14"

    // MARK: - Install state

    /// One installer stage from `install.sh --manifest`, title in French.
    struct InstallStage: Equatable {
        let name: String
        let title: String
    }

    @Published var isInstalling = false
    @Published var installStatus = ""
    @Published var installError: String?
    @Published var needsGitInstall = false
    /// Stages the installer runs (empty until the manifest is read, and when
    /// Hermes is already installed).
    @Published var installStages: [InstallStage] = []
    /// Stages finished so far: drives the progress bar.
    @Published var completedStages = 0
    /// Full installer output of the last run, kept for "Voir le journal".
    @Published var installLogURL: URL?

    // MARK: - Connect-provider step state

    /// Which provider's "paste your own key" panel is currently open in the
    /// Connect step. nil = nothing selected (only the big OAuth button is
    /// visible). Defaults to nil at session start; the segmented row reveals
    /// the API-key field as soon as the user picks a provider.
    @Published var advancedProvider: String? = nil
    @Published var advancedAPIKey: String = ""
    @Published var isConnecting: Bool = false
    @Published var connectError: String?
    /// Set when OpenRouter is connected but no free model with tools could be
    /// read: the Ready step tells the user to pick one in Settings.
    @Published var modelNotice: String?

    /// Pages where each provider lets you generate / view API keys. Shown as a
    /// small "Obtenir une clé sur …" link below the API-key field.
    static let providerKeyURLs: [String: String] = [
        "openrouter": "https://openrouter.ai/settings/keys",
        "openai":     "https://platform.openai.com/api-keys",
        "anthropic":  "https://console.anthropic.com/settings/keys",
        "minimax":    "https://www.minimax.io/platform/user-center/basic-information/interface-key",
        "gemini":     "https://aistudio.google.com/apikey",
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

        let defaults = UserDefaults.standard
        // Written by pre-H14 builds, never read anywhere.
        defaults.removeObject(forKey: "selectedProvider")

        let storedStep = defaults.integer(forKey: "onboardingStep")
        let step: OnboardingStep
        if defaults.bool(forKey: Self.stepScaleKey) {
            step = OnboardingStep(rawValue: storedStep) ?? .welcome
        } else {
            step = Self.stepFromLegacyScale(storedStep)
            defaults.set(true, forKey: Self.stepScaleKey)
            if defaults.object(forKey: "onboardingStep") != nil {
                defaults.set(step.rawValue, forKey: "onboardingStep")
            }
        }
        self.currentStep = step

        // Determine once at launch whether onboarding is needed
        if defaults.bool(forKey: "onboardingCompleted") {
            self.needsOnboarding = false
        } else if storedStep > 0 {
            // Mid-flow from a previous launch
            self.needsOnboarding = true
        } else {
            let configExists = FileManager.default.fileExists(atPath: "\(home)/config.yaml")
            self.needsOnboarding = !configExists
        }
    }

    /// Pre-H14 scale: 0 Welcome · 1 Privacy · 2 Install · 3 Connect ·
    /// 4 Computer use · 5 Telegram · 6 Ready.
    static func stepFromLegacyScale(_ legacy: Int) -> OnboardingStep {
        switch legacy {
        case ...1: return .welcome
        case 2: return .install
        case 3: return .connect
        default: return .ready
        }
    }

    // MARK: - Navigation

    func advance() {
        withAnimation {
            currentStep = OnboardingStep(rawValue: currentStep.rawValue + 1) ?? .ready
        }
    }

    func goBack() {
        withAnimation {
            currentStep = OnboardingStep(rawValue: currentStep.rawValue - 1) ?? .welcome
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
            let model = try await OpenRouterOAuthService.shared.connect()
            modelNotice = model == nil ? Self.noFreeModelNotice : nil
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

    /// "Paste your own key" path. Writes the key into .env, points config.yaml
    /// at the provider + its default base URL, and seeds model.default: for
    /// OpenRouter the same live free-model pick as the OAuth path, else the
    /// first model in HermesConfig's list.
    @MainActor
    func saveAdvancedKey(provider: String) async {
        let trimmed = advancedAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isConnecting else { return }

        let cfg = HermesConfig.shared
        cfg.writeAPIKey(provider: provider, key: trimmed)
        cfg.modelProvider = provider
        cfg.setImmediate("model.provider", value: provider)
        if let baseURL = HermesConfig.defaultBaseURL(for: provider) {
            cfg.setImmediate("model.base_url", value: baseURL)
        }
        modelNotice = nil
        if provider == "openrouter" {
            isConnecting = true
            let model = await OpenRouterCatalog.shared.pickFreeToolModel()
            isConnecting = false
            if let model {
                cfg.setImmediate("model.default", value: model)
            } else {
                modelNotice = Self.noFreeModelNotice
            }
        } else if let firstModel = cfg.availableModels.first {
            cfg.setImmediate("model.default", value: firstModel.value)
        }
        advancedAPIKey = ""
        advance()
    }

    private static let noFreeModelNotice =
        "Impossible de lire la liste des modèles gratuits d'OpenRouter. Choisis un modèle dans les Réglages avant d'écrire."

    // MARK: - Hermes installation

    /// Hermes's own installer, the script of `main` (it installs the latest
    /// release on the stable channel). Never a tag's copy: those clone main's tip.
    private static let installScriptURL =
        "https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh"

    /// Same protocol as Hermes Setup (`--stage NAME --json --non-interactive`),
    /// without cua-driver (Settings › Contrôle du Mac installs it) and with the
    /// channel saved as stable. The browser tools stay (H14 D1).
    private static let installerFlags = ["--json", "--non-interactive", "--skip-computer-use", "--channel", "stable"]

    /// Used when `--manifest` can't be read. `setup` and `gateway` need a
    /// terminal: they are skipped (NotchNotch runs `hermes gateway start`).
    private static let fallbackStageNames = ["prerequisites", "repository", "venv", "python-deps", "config", "products", "complete"]

    private static let stageTitles: [String: String] = [
        "prerequisites": "Vérification du Mac",
        "repository": "Téléchargement de Hermes",
        "venv": "Préparation de Python",
        "python-deps": "Installation des composants",
        "config": "Préparation de la configuration",
        "products": "Installation de la commande hermes",
        "complete": "Finalisation",
    ]

    func installHermes() {
        guard !isInstalling else { return }
        isInstalling = true
        installError = nil
        installStages = []
        completedStages = 0
        installStatus = "Vérification…"

        Task { @MainActor in
            // A config.yaml means Hermes is installed: only the gateway is left.
            // Without it (fresh Mac, or an install that stopped half-way) the
            // installer runs: every stage is safe to re-run.
            if !FileManager.default.fileExists(atPath: "\(hermesHome)/config.yaml") {
                guard await ensureDeveloperTools() else {
                    isInstalling = false
                    return
                }
                do {
                    try await runInstaller()
                } catch {
                    installError = error.localizedDescription
                    isInstalling = false
                    return
                }
                guard FileManager.default.fileExists(atPath: "\(hermesHome)/config.yaml") else {
                    installError = "L'installation s'est terminée sans créer la configuration de Hermes (~/.hermes/config.yaml)."
                    isInstalling = false
                    return
                }
            }

            // Auto-start Hermes at login + wait for /health so the chat
            // works on the very first message.
            installStatus = "Démarrage de Hermes…"
            await ensureLaunchAgentAndAwaitHealth()
            completedStages = installStages.count
            installStatus = "Terminé"
            isInstalling = false
            advance()
        }
    }

    /// git comes with Apple's Command Line Tools. `which git` can't tell:
    /// /usr/bin/git is a stub until they are installed, and running it opens
    /// macOS's install dialog. `xcode-select -p` answers without a window, then
    /// `git --version` proves git runs. Missing tools → macOS's dialog, then a
    /// 5-minute wait. Returns false with `installError` set.
    @MainActor
    private func ensureDeveloperTools() async -> Bool {
        if await !Self.developerDirectorySet() {
            needsGitInstall = true
            installStatus = "Installation des outils développeur d'Apple…"
            _ = try? await ShellRunner.run(executable: "/usr/bin/xcode-select", arguments: ["--install"])
            var installed = false
            for _ in 0..<60 {
                try? await Task.sleep(for: .seconds(5))
                if await Self.developerDirectorySet() {
                    installed = true
                    break
                }
            }
            needsGitInstall = false
            guard installed else {
                installError = "Les outils développeur d'Apple ne sont pas encore installés. Termine leur installation dans la fenêtre de macOS, puis réessaie."
                return false
            }
        }
        let git = try? await ShellRunner.run(executable: "/usr/bin/git", arguments: ["--version"])
        guard git?.exitCode == 0 else {
            let detail = lastLines(git?.output ?? "", count: 2)
            installError = "git ne fonctionne pas sur ce Mac, et Hermes en a besoin.\(detail.isEmpty ? "" : "\n\n\(detail)")"
            return false
        }
        return true
    }

    private static func developerDirectorySet() async -> Bool {
        let result = try? await ShellRunner.run(executable: "/usr/bin/xcode-select", arguments: ["-p"])
        return result?.exitCode == 0
    }

    /// Downloads `install.sh`, reads its stage list, then runs one stage at a
    /// time and reads the JSON line each one ends with. A stage that dies
    /// without its JSON line is retried once, then the whole installer runs
    /// in one call (protocol mismatch). Throws a French message.
    @MainActor
    private func runInstaller() async throws {
        let fm = FileManager.default
        let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = caches.appendingPathComponent("notchnotch-installer", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let script = dir.appendingPathComponent("install.sh")
        let logURL = dir.appendingPathComponent("install.log")
        var log = ""
        installLogURL = logURL

        installStatus = "Téléchargement de l'installeur…"
        let download = try? await ShellRunner.run(
            executable: "/usr/bin/curl",
            arguments: ["-fsSL", "--retry", "2", Self.installScriptURL, "-o", script.path]
        )
        guard download?.exitCode == 0 else {
            throw InstallerError("Impossible de télécharger l'installeur de Hermes. Vérifie ta connexion à internet, puis réessaie.")
        }

        let manifest = try? await ShellRunner.run(executable: "/bin/bash", arguments: [script.path, "--manifest"])
        let stages = Self.parseManifest(manifest?.output ?? "")
            ?? Self.fallbackStageNames.map { InstallStage(name: $0, title: Self.stageTitles[$0] ?? $0) }
        installStages = stages

        for (index, stage) in stages.enumerated() {
            completedStages = index
            installStatus = stage.title
            var frame: StageFrame?
            for attempt in 1...2 where frame == nil {
                let result = try? await ShellRunner.run(
                    executable: "/bin/bash",
                    arguments: [script.path, "--stage", stage.name] + Self.installerFlags
                )
                let output = result?.output ?? ""
                log += "==> \(stage.name) (essai \(attempt), code \(result?.exitCode ?? -1))\n\(output)\n"
                try? log.write(to: logURL, atomically: true, encoding: .utf8)
                frame = Self.lastFrame(in: output)
                if frame == nil {
                    os_log("[notchnotch] install stage %{public}@ gave no JSON (attempt %d)", type: .info, stage.name, attempt)
                }
            }

            guard let frame else {
                try await runWholeInstaller(script: script, log: &log, logURL: logURL)
                return
            }
            guard frame.ok else {
                let reason = frame.reason ?? "échec sans raison donnée"
                os_log("[notchnotch] install stage %{public}@ failed: %{public}@", type: .info, stage.name, reason)
                throw InstallerError("L'étape « \(stage.title) » a échoué.\n\n\(reason)")
            }
        }
        completedStages = stages.count
    }

    /// Fallback: the installer in one call (`bash install.sh` without
    /// `--stage`), same flags minus `--json`. No per-stage progress.
    @MainActor
    private func runWholeInstaller(script: URL, log: inout String, logURL: URL) async throws {
        installStatus = "Installation de Hermes…"
        let flags = Self.installerFlags.filter { $0 != "--json" }
        let result = try? await ShellRunner.run(executable: "/bin/bash", arguments: [script.path] + flags)
        let output = result?.output ?? ""
        log += "==> installeur complet (code \(result?.exitCode ?? -1))\n\(output)\n"
        try? log.write(to: logURL, atomically: true, encoding: .utf8)
        guard result?.exitCode == 0 else {
            throw InstallerError("L'installation de Hermes a échoué.\n\n\(lastLines(output, count: 6))")
        }
    }

    private struct InstallerError: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }

    /// `{"ok":…,"stage":…,"skipped":…,"reason":…}`, the last line of a stage
    /// run with `--json`.
    private struct StageFrame: Decodable {
        let ok: Bool
        let stage: String?
        let skipped: Bool?
        let reason: String?
    }

    private static func lastFrame(in output: String) -> StageFrame? {
        for line in output.split(whereSeparator: \.isNewline).reversed() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("{\"ok\""),
                  let frame = try? JSONDecoder().decode(StageFrame.self, from: Data(trimmed.utf8))
            else { continue }
            return frame
        }
        return nil
    }

    /// `{"protocol_version":1,"stages":[{"name","title","category","needs_user_input"}]}`.
    /// Stages that need a terminal are left out. nil = unreadable.
    private static func parseManifest(_ output: String) -> [InstallStage]? {
        struct Manifest: Decodable {
            struct Stage: Decodable {
                let name: String
                let title: String?
                let needs_user_input: Bool?
            }
            let stages: [Stage]
        }
        for line in output.split(whereSeparator: \.isNewline).reversed() {
            guard let manifest = try? JSONDecoder().decode(Manifest.self, from: Data(line.utf8)) else { continue }
            let stages = manifest.stages
                .filter { $0.needs_user_input != true }
                .map { InstallStage(name: $0.name, title: stageTitles[$0.name] ?? $0.title ?? $0.name) }
            return stages.isEmpty ? nil : stages
        }
        return nil
    }

    // MARK: - Complete

    func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "onboardingCompleted")
        UserDefaults.standard.removeObject(forKey: "onboardingStep")
        needsOnboarding = false
        notchVM?.suppressAutoClose = false
    }

    // MARK: - LaunchAgent + health bridge

    /// Writes the API server env, runs `hermes gateway start` (writes and
    /// loads Hermes's own plist) and waits up to 30s for `/health`: a fresh
    /// install's first start runs migrations and syncs skills. Any failure here
    /// is soft — we still advance so the user can keep onboarding; the
    /// actionable "Hermes ne répond pas" toast handles the retry path on the
    /// chat side if we couldn't bring it up here.
    @MainActor
    private func ensureLaunchAgentAndAwaitHealth() async {
        // Without API_SERVER_ENABLED + a 16+ char API_SERVER_KEY Hermes
        // runs cron-only (no port 8642) and NotchNotch can't reach it.
        // The upstream installer sets neither. CORS=* lets the
        // browser-based Clipper extension talk to the local gateway.
        let launcher = HermesGatewayLauncher.shared
        await launcher.ensureApiServerEnv()
        do {
            try await launcher.install()
        } catch {
            // Hermes binary missing or launchctl refused. The chat-side
            // actionable toast covers this case on first unreachable response.
            os_log("[notchnotch] gateway start during onboarding failed: %{public}@", type: .info, error.localizedDescription)
            return
        }
        for _ in 0..<30 {
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

import SwiftUI
import AppKit

struct InstallHermesStep: View {
    @ObservedObject var onboardingVM: OnboardingViewModel

    /// Real progress: one notch per installer stage (`install.sh --stage`),
    /// the bar fills as each stage's JSON line comes back. Stages take very
    /// different times (the download and Python dependencies are the long
    /// ones), so the current stage's name matters more than the bar.
    @State private var elapsedSeconds = 0
    @State private var patienceTimer: Timer?

    private static let patientMessageAfterSeconds = 120

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Text("Installation de ton agent")
                .font(DS.Text.titleSmall)
                .foregroundStyle(DS.Surface.primary)

            if onboardingVM.needsGitInstall {
                gitInstallMessage
            } else if let error = onboardingVM.installError {
                errorView(error)
            } else if onboardingVM.isInstalling {
                installingView
            } else {
                readyToInstallView
            }

            Spacer()
        }
        .onAppear {
            if !onboardingVM.isInstalling && onboardingVM.installError == nil {
                onboardingVM.installHermes()
            }
        }
    }

    private var gitInstallMessage: some View {
        VStack(spacing: 10) {
            Image(systemName: "wrench.and.screwdriver")
                .font(DS.Icon.large)
                .foregroundStyle(AppColors.accent.opacity(0.6))

            Text("macOS doit d'abord installer les outils développeur d'Apple.")
                .font(DS.Text.caption)
                .foregroundStyle(DS.Surface.secondary)
                .multilineTextAlignment(.center)

            Text("Une fenêtre de macOS va s'ouvrir : clique sur Installer et accepte la licence. Compte quelques minutes.")
                .font(DS.Text.micro)
                .foregroundStyle(DS.Surface.tertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            SpinningRing()
                .padding(.top, 6)
        }
    }

    private var progress: Double {
        let total = onboardingVM.installStages.count
        guard total > 0 else { return 0 }
        return Double(onboardingVM.completedStages) / Double(total)
    }

    private var installingView: some View {
        VStack(spacing: 12) {
            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .tint(AppColors.accent)
                .frame(maxWidth: 280)
                .animation(.easeInOut(duration: 0.4), value: progress)

            Text(onboardingVM.installStatus)
                .font(DS.Text.caption)
                .foregroundStyle(DS.Surface.tertiary)
                .animation(.easeInOut(duration: 0.3), value: onboardingVM.installStatus)

            if !onboardingVM.installStages.isEmpty,
               onboardingVM.completedStages < onboardingVM.installStages.count {
                Text("Étape \(onboardingVM.completedStages + 1) sur \(onboardingVM.installStages.count)")
                    .font(DS.Text.micro)
                    .foregroundStyle(DS.Surface.quaternary)
            }

            if elapsedSeconds >= Self.patientMessageAfterSeconds {
                Text("Encore un peu de patience : la première installation télécharge Python et les composants de Hermes.")
                    .font(DS.Text.micro)
                    .foregroundStyle(DS.Surface.quaternary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 24)
                    .transition(.opacity)
            }
        }
        .onAppear { startPatienceTimer() }
        .onDisappear { stopPatienceTimer() }
    }

    private func startPatienceTimer() {
        stopPatienceTimer()
        elapsedSeconds = 0
        let timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in elapsedSeconds += 1 }
        }
        patienceTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopPatienceTimer() {
        patienceTimer?.invalidate()
        patienceTimer = nil
    }

    private func errorView(_ error: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(DS.Icon.primary)
                .foregroundStyle(.red.opacity(0.5))

            Text("L'installation n'a pas abouti")
                .font(DS.Text.labelMedium)
                // TODO(design): 0.6 hors bucket DS.Surface (entre secondary 0.55 et primary 0.85).
                .foregroundStyle(.white.opacity(0.6))

            ScrollView {
                Text(error)
                    .font(DS.Text.nanoMono)
                    .foregroundStyle(DS.Surface.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 80)
            .padding(8)
            // TODO(design): error frame fill 0.03 hors bucket DS.Surface (background subtil très spécifique).
            .background(.white.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    // TODO(design): error frame stroke 0.05 hors bucket DS.Surface.
                    .stroke(.white.opacity(0.05), lineWidth: 0.5)
            )

            HStack(spacing: 14) {
                if let logURL = onboardingVM.installLogURL,
                   FileManager.default.fileExists(atPath: logURL.path) {
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([logURL])
                    } label: {
                        Text("Voir le journal")
                            .font(DS.Text.micro)
                            .foregroundStyle(DS.Surface.secondary)
                    }
                    .buttonStyle(.plain)
                    .pointingHandCursor()
                }

                OnboardingButton("Réessayer") {
                    onboardingVM.installHermes()
                }
            }
        }
    }

    private var readyToInstallView: some View {
        VStack(spacing: 10) {
            Text("Préparation de l'installation…")
                .font(DS.Text.caption)
                .foregroundStyle(DS.Surface.tertiary)
            SpinningRing()
        }
    }
}

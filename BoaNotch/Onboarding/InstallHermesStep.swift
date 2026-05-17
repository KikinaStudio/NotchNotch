import SwiftUI

struct InstallHermesStep: View {
    @ObservedObject var onboardingVM: OnboardingViewModel

    /// Cosmetic-deterministic progress. The upstream installer (curl | bash)
    /// emits a single bulk output buffer at exit (see ShellRunner) so we
    /// can't stream real per-line progress. Five known status milestones
    /// land at 0, 18, 36, 54, 72s; we interpolate between them at 0.5s
    /// granularity. After 90s we cap at 95% so we never lie about 100%
    /// before the subprocess actually finishes; the jump to 100% happens
    /// when `installStatus == "Done!"`.
    @State private var progress: Double = 0
    @State private var elapsedSeconds: Double = 0
    @State private var progressTimer: Timer?

    private static let milestoneInterval: Double = 18
    private static let milestoneCount: Int = 5
    private static let capAfterSeconds: Double = 90
    private static let patientMessageAfterSeconds: Double = 120

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Text("Setting up your AI agent")
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

            Text("macOS needs to install a small developer tool first.")
                .font(DS.Text.caption)
                .foregroundStyle(DS.Surface.secondary)
                .multilineTextAlignment(.center)

            Text("A system popup will appear \u{2014} click Install and wait about 1 minute.")
                .font(DS.Text.micro)
                .foregroundStyle(DS.Surface.tertiary)
                .multilineTextAlignment(.center)

            SpinningRing()
                .padding(.top, 6)
        }
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

            if elapsedSeconds >= Self.patientMessageAfterSeconds {
                Text("Encore un peu de patience, l'installation prend parfois plus de temps sur les premières fois.")
                    .font(DS.Text.micro)
                    .foregroundStyle(DS.Surface.quaternary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 24)
                    .transition(.opacity)
            }
        }
        .onAppear { startProgressTimer() }
        .onDisappear { stopProgressTimer() }
        .onChange(of: onboardingVM.installStatus) { _, newStatus in
            if newStatus == "Done!" {
                progress = 1.0
                stopProgressTimer()
            }
        }
        .onChange(of: onboardingVM.isInstalling) { _, installing in
            if !installing {
                if onboardingVM.installError == nil {
                    progress = 1.0
                }
                stopProgressTimer()
            }
        }
    }

    private func startProgressTimer() {
        stopProgressTimer()
        elapsedSeconds = 0
        progress = 0
        let timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            Task { @MainActor in
                elapsedSeconds += 0.5
                let raw = elapsedSeconds / (Self.milestoneInterval * Double(Self.milestoneCount))
                // Cap at 95% so we never show a fake 100% before the
                // subprocess actually returns. The terminal transition
                // bumps to 1.0 in onChange(installStatus == "Done!").
                progress = min(0.95, raw)
            }
        }
        progressTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    private func errorView(_ error: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(DS.Icon.primary)
                .foregroundStyle(.red.opacity(0.5))

            Text("Installation failed")
                .font(DS.Text.labelMedium)
                // TODO(design): 0.6 hors bucket DS.Surface (entre secondary 0.55 et primary 0.85).
                .foregroundStyle(.white.opacity(0.6))

            ScrollView {
                Text(error)
                    .font(DS.Text.nanoMono)
                    .foregroundStyle(DS.Surface.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
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

            OnboardingButton("Retry") {
                onboardingVM.installError = nil
                onboardingVM.installHermes()
            }
        }
    }

    private var readyToInstallView: some View {
        VStack(spacing: 10) {
            Text("Preparing installation...")
                .font(DS.Text.caption)
                .foregroundStyle(DS.Surface.tertiary)
            SpinningRing()
        }
    }
}

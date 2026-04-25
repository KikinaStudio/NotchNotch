import SwiftUI

struct InstallHermesStep: View {
    @ObservedObject var onboardingVM: OnboardingViewModel

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
        VStack(spacing: 14) {
            SpinningRing()

            Text(onboardingVM.installStatus)
                .font(DS.Text.caption)
                .foregroundStyle(DS.Surface.tertiary)
                .animation(.easeInOut(duration: 0.3), value: onboardingVM.installStatus)
        }
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

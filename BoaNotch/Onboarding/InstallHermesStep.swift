import SwiftUI

struct InstallHermesStep: View {
    @ObservedObject var onboardingVM: OnboardingViewModel

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Text("Setting up your AI agent")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white.opacity(0.88))

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
                .font(.system(size: 22))
                .foregroundStyle(AppColors.accent.opacity(0.6))

            Text("macOS needs to install a small developer tool first.")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)

            Text("A system popup will appear \u{2014} click Install and wait about 1 minute.")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.3))
                .multilineTextAlignment(.center)

            SpinningRing()
                .padding(.top, 6)
        }
    }

    private var installingView: some View {
        VStack(spacing: 14) {
            SpinningRing()

            Text(onboardingVM.installStatus)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.4))
                .animation(.easeInOut(duration: 0.3), value: onboardingVM.installStatus)
        }
    }

    private func errorView(_ error: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 18))
                .foregroundStyle(.red.opacity(0.5))

            Text("Installation failed")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))

            ScrollView {
                Text(error)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.3))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 80)
            .padding(8)
            .background(.white.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
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
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.35))
            SpinningRing()
        }
    }
}

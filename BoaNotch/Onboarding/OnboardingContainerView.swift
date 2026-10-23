import SwiftUI

struct OnboardingContainerView: View {
    @ObservedObject var onboardingVM: OnboardingViewModel

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch onboardingVM.currentStep {
                case .welcome: WelcomeStep(onboardingVM: onboardingVM)
                case .install: InstallHermesStep(onboardingVM: onboardingVM)
                case .connect: ConnectProviderStep(onboardingVM: onboardingVM)
                case .ready: ReadyStep(onboardingVM: onboardingVM)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Navigation — dots on install/connect. « Retour » only on the
            // install step while nothing runs: going back from Connexion would
            // only re-run the (finished) install, which advances on its own.
            if onboardingVM.currentStep == .install || onboardingVM.currentStep == .connect {
                HStack {
                    if onboardingVM.currentStep == .install && !onboardingVM.isInstalling {
                        Button { onboardingVM.goBack() } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "chevron.left")
                                    .font(DS.Icon.chevron)
                                Text("Retour")
                                    .font(DS.Text.micro)
                            }
                            .foregroundStyle(DS.Surface.secondary)
                        }
                        .buttonStyle(.plain)
                        .pointingHandCursor()
                        .frame(width: 56, alignment: .leading)
                    } else {
                        Color.clear.frame(width: 56, height: 1)
                    }

                    Spacer()

                    // Step dots
                    HStack(spacing: 5) {
                        ForEach(OnboardingStep.allCases, id: \.self) { step in
                            Circle()
                                // TODO(design): pas de bucket DS.Surface pour 0.1 (étape inactive); 0.5 ≈ secondary mais ternaire mixte conservé en littéral pour cohérence visuelle.
                                .fill(.white.opacity(step == onboardingVM.currentStep ? 0.5 : 0.1))
                                .frame(width: 4, height: 4)
                        }
                    }

                    Spacer()

                    // Invisible spacer for symmetry
                    Color.clear.frame(width: 56, height: 1)
                }
                .padding(.top, 6)
            }
        }
    }
}

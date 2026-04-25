import SwiftUI

struct OnboardingContainerView: View {
    @ObservedObject var onboardingVM: OnboardingViewModel

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch onboardingVM.currentStep {
                case 0: WelcomeStep(onboardingVM: onboardingVM)
                case 1: PrivacyStep(onboardingVM: onboardingVM)
                case 2: InstallHermesStep(onboardingVM: onboardingVM)
                case 3: ChooseModelStep(onboardingVM: onboardingVM)
                case 4: TelegramStep(onboardingVM: onboardingVM)
                case 5: ReadyStep(onboardingVM: onboardingVM)
                default: ReadyStep(onboardingVM: onboardingVM)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Navigation — back + dots (no back on welcome/ready, no dots on welcome/ready)
            if onboardingVM.currentStep > 0 && onboardingVM.currentStep < 5 {
                HStack {
                    Button { onboardingVM.goBack() } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "chevron.left")
                                .font(DS.Icon.chevron)
                            Text("Back")
                                .font(DS.Text.micro)
                        }
                        .foregroundStyle(DS.Surface.secondary)
                    }
                    .buttonStyle(.plain)
                    .pointingHandCursor()

                    Spacer()

                    // Step dots
                    HStack(spacing: 5) {
                        ForEach(0..<6, id: \.self) { i in
                            Circle()
                                // TODO(design): pas de bucket DS.Surface pour 0.1 (étape inactive); 0.5 ≈ secondary mais ternaire mixte conservé en littéral pour cohérence visuelle.
                                .fill(.white.opacity(i == onboardingVM.currentStep ? 0.5 : 0.1))
                                .frame(width: 4, height: 4)
                        }
                    }

                    Spacer()

                    // Invisible spacer for symmetry
                    Color.clear.frame(width: 44, height: 1)
                }
                .padding(.top, 6)
            }
        }
    }
}

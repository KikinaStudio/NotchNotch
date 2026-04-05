import SwiftUI

struct ReadyStep: View {
    @ObservedObject var onboardingVM: OnboardingViewModel

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "checkmark")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(AppColors.accent.opacity(0.7))

            Text("You're all set")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white.opacity(0.88))
                .padding(.top, 14)

            Text("Your AI agent is ready. Say hello.")
                .font(.system(size: 11))
                .foregroundStyle(AppColors.accent.opacity(0.5))
                .padding(.top, 4)

            Spacer()

            OnboardingButton("Start chatting") {
                onboardingVM.completeOnboarding()
            }

            Spacer().frame(height: 24)
        }
    }
}

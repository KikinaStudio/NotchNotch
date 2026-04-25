import SwiftUI

struct ReadyStep: View {
    @ObservedObject var onboardingVM: OnboardingViewModel

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "checkmark")
                .font(DS.Icon.hero)
                .foregroundStyle(AppColors.accent.opacity(0.7))

            Text("You're all set")
                .font(DS.Text.title)
                .foregroundStyle(DS.Surface.primary)
                .padding(.top, 14)

            Text("Your AI agent is ready. Say hello.")
                .font(DS.Text.caption)
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

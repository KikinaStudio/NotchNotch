import SwiftUI

struct ReadyStep: View {
    @ObservedObject var onboardingVM: OnboardingViewModel

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "checkmark")
                .font(DS.Icon.hero)
                .foregroundStyle(AppColors.accent.opacity(0.7))

            Text("Tout est prêt")
                .font(DS.Text.title)
                .foregroundStyle(DS.Surface.primary)
                .padding(.top, 14)

            Text("Ton agent est prêt. Dis-lui bonjour.")
                .font(DS.Text.caption)
                .foregroundStyle(AppColors.accent.opacity(0.5))
                .padding(.top, 4)

            if let notice = onboardingVM.modelNotice {
                Text(notice)
                    .font(DS.Text.micro)
                    .foregroundStyle(DS.Surface.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 24)
                    .padding(.top, 10)
            }

            Text("Pour que l'agent utilise tes apps : Réglages › Contrôle du Mac.")
                .font(DS.Text.micro)
                .foregroundStyle(DS.Surface.tertiary)
                .multilineTextAlignment(.center)
                .padding(.top, 14)

            Spacer()

            OnboardingButton("Commencer à discuter") {
                onboardingVM.completeOnboarding()
            }

            Spacer().frame(height: 24)
        }
    }
}

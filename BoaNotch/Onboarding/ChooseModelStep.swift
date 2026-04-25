import SwiftUI

struct ChooseModelStep: View {
    @ObservedObject var onboardingVM: OnboardingViewModel

    private var models: [(id: String, name: String, description: String, badge: String?)] {
        switch onboardingVM.selectedProvider {
        case "openai":
            return [
                ("gpt-4o-mini", "GPT-4o mini", "Fast and affordable", nil),
                ("gpt-4o", "GPT-4o", "Great all-around model", nil),
                ("gpt-5", "GPT-5", "Most capable", nil),
            ]
        case "anthropic":
            return [
                ("claude-sonnet-4-6-20250514", "Claude Sonnet 4.6", "Fast, great for most tasks", nil),
                ("claude-opus-4-6-20250514", "Claude Opus 4.6", "Most capable", nil),
            ]
        default:
            return [
                ("xiaomi/mimo-v2-pro", "Mimo v2 Pro", "Fast and capable", "Free"),
                ("nousresearch/hermes-4-70b", "Hermes 4 70B", "Strong all-rounder", "Free"),
                ("nousresearch/deephermes-3-8b", "DeepHermes 3 8B", "Lightweight reasoning", "Free"),
            ]
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Choose your AI model")
                .font(DS.Text.titleSmall)
                .foregroundStyle(DS.Surface.primary)

            Text("You can change this anytime in settings.")
                .font(DS.Text.micro)
                .foregroundStyle(AppColors.accent.opacity(0.45))
                .padding(.top, 3)
                .padding(.bottom, 14)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 4) {
                    ForEach(models, id: \.id) { model in
                        modelCard(model)
                    }
                }
            }

            Text("You can switch models and add your own API keys anytime in settings.")
                .font(DS.Text.nano)
                .foregroundStyle(AppColors.accent.opacity(0.4))
                .padding(.top, 6)

            HStack {
                Spacer()
                OnboardingButton("Continue", disabled: onboardingVM.selectedModel.isEmpty) {
                    onboardingVM.writeModelChoice()
                    onboardingVM.advance()
                }
            }
            .padding(.top, 10)
        }
        .onAppear {
            if onboardingVM.selectedModel.isEmpty, let first = models.first {
                onboardingVM.selectedModel = first.id
            }
        }
    }

    private func modelCard(_ model: (id: String, name: String, description: String, badge: String?)) -> some View {
        let isSelected = onboardingVM.selectedModel == model.id

        return Button {
            withAnimation(.easeOut(duration: 0.12)) {
                onboardingVM.selectedModel = model.id
            }
        } label: {
            HStack(spacing: 10) {
                // Minimal radio dot
                Circle()
                    // TODO(design): radio fill 0.8 hors bucket DS.Surface (entre secondary 0.55 et primary 0.85).
                    .fill(isSelected ? Color.white.opacity(0.8) : Color.clear)
                    .frame(width: 5, height: 5)
                    .padding(4)
                    .overlay(
                        Circle()
                            // TODO(design): radio stroke 0.12 (unselected) hors bucket; ternaire conservé en littéral pour cohérence selected/unselected.
                            .stroke(.white.opacity(isSelected ? 0.3 : 0.12), lineWidth: 0.5)
                    )

                VStack(alignment: .leading, spacing: 1) {
                    Text(model.name)
                        .font(DS.Text.captionMedium)
                        .foregroundStyle(isSelected ? DS.Surface.primary : DS.Surface.secondary)

                    Text(model.description)
                        .font(DS.Text.nano)
                        .foregroundStyle(DS.Surface.tertiary)
                }

                Spacer()

                if let badge = model.badge {
                    Text(badge)
                        .font(DS.Text.badge)
                        .textCase(.uppercase)
                        .tracking(0.5)
                        .foregroundStyle(badge == "Free" ? AnyShapeStyle(Color.green.opacity(0.6)) : DS.Surface.quaternary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    // TODO(design): card fill 0.06/0.02 hors bucket (DS.Stroke.hairline = 0.06 mais 0.02 pas de token); ternaire conservé pour cohérence.
                    .fill(.white.opacity(isSelected ? 0.06 : 0.02))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    // TODO(design): card stroke 0.12/0.04 hors bucket DS.Surface.
                    .stroke(.white.opacity(isSelected ? 0.12 : 0.04), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }
}

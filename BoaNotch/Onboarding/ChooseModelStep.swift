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
                ("google/gemini-3-flash-preview", "Google Gemini Flash", "Fast and free, great for everyday use", "Free"),
                ("meta-llama/llama-4-scout", "Meta Llama 4 Scout", "Open source, strong reasoning", "Free"),
                ("google/gemini-3-pro-preview", "Google Gemini Pro", "Powerful, good at complex tasks", "Free"),
                ("anthropic/claude-sonnet-4.6", "Anthropic Claude Sonnet", "Excellent writing and analysis", "Paid"),
                ("anthropic/claude-opus-4.6", "Anthropic Claude Opus", "Most capable, best for hard problems", "Paid"),
            ]
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Choose your AI model")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white.opacity(0.88))

            Text("You can change this anytime in settings.")
                .font(.system(size: 10))
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
                    .fill(isSelected ? .white.opacity(0.8) : .clear)
                    .frame(width: 5, height: 5)
                    .padding(4)
                    .overlay(
                        Circle()
                            .stroke(.white.opacity(isSelected ? 0.3 : 0.12), lineWidth: 0.5)
                    )

                VStack(alignment: .leading, spacing: 1) {
                    Text(model.name)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(isSelected ? 0.85 : 0.55))

                    Text(model.description)
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.3))
                }

                Spacer()

                if let badge = model.badge {
                    Text(badge)
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .textCase(.uppercase)
                        .tracking(0.5)
                        .foregroundStyle(badge == "Free" ? .green.opacity(0.6) : .white.opacity(0.25))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(.white.opacity(isSelected ? 0.06 : 0.02))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.white.opacity(isSelected ? 0.12 : 0.04), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }
}

import SwiftUI

struct ConnectProviderStep: View {
    @ObservedObject var onboardingVM: OnboardingViewModel
    @State private var showManualKeys = false

    var body: some View {
        VStack(spacing: 0) {
            Text("Connect your AI")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white.opacity(0.88))
                .padding(.bottom, 20)

            Spacer()

            // Primary: OpenRouter OAuth
            VStack(spacing: 8) {
                OnboardingWideButton(
                    label: "Connect with OpenRouter",
                    icon: "bolt.fill",
                    action: { onboardingVM.startOAuth() },
                    disabled: onboardingVM.oauthInProgress
                )

                Text("Free account. No credit card. 20+ free AI models.")
                    .font(.system(size: 9))
                    .foregroundStyle(AppColors.accent.opacity(0.5))
            }

            // OAuth status
            if onboardingVM.oauthInProgress {
                HStack(spacing: 6) {
                    SpinningRing()
                    Text("Waiting for browser...")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.35))
                }
                .padding(.top, 14)
            }

            if let error = onboardingVM.oauthError {
                VStack(spacing: 6) {
                    Text(error)
                        .font(.system(size: 10))
                        .foregroundStyle(.red.opacity(0.7))

                    Button {
                        onboardingVM.oauthError = nil
                        onboardingVM.startOAuth()
                    } label: {
                        Text("Try again")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                    .pointingHandCursor()
                }
                .padding(.top, 10)
            }

            Spacer()

            // Secondary: Manual API key
            VStack(spacing: 0) {
                Button { withAnimation(.easeOut(duration: 0.2)) { showManualKeys.toggle() } } label: {
                    HStack(spacing: 4) {
                        Image(systemName: showManualKeys ? "chevron.down" : "chevron.right")
                            .font(.system(size: 8))
                        Text("I already have an API key")
                            .font(.system(size: 10))
                    }
                    .foregroundStyle(.white.opacity(0.3))
                }
                .buttonStyle(.plain)
                .pointingHandCursor()

                if showManualKeys {
                    VStack(spacing: 8) {
                        apiKeyField(label: "OpenRouter", placeholder: "sk-or-v1-...", text: $onboardingVM.manualOpenRouterKey)
                        apiKeyField(label: "OpenAI", placeholder: "sk-...", text: $onboardingVM.manualOpenAIKey)
                        apiKeyField(label: "Anthropic", placeholder: "sk-ant-...", text: $onboardingVM.manualAnthropicKey)

                        HStack {
                            Spacer()
                            OnboardingButton("Connect", disabled: !onboardingVM.hasManualKey) {
                                onboardingVM.connectManualKey()
                            }
                        }
                        .padding(.top, 2)
                    }
                    .padding(.top, 10)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    private func apiKeyField(label: String, placeholder: String, text: Binding<String>) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.35))
                .frame(width: 65, alignment: .trailing)

            SecureField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.white.opacity(0.7))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(.white.opacity(0.06), lineWidth: 0.5)
                )
        }
    }
}

import SwiftUI
import AppKit

struct TelegramStep: View {
    @ObservedObject var onboardingVM: OnboardingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Chat on the go")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white.opacity(0.88))

            Text("Connect Telegram to continue your conversations from your phone.")
                .font(.system(size: 10))
                .foregroundStyle(AppColors.accent.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 3)

            Text("Takes about 1 minute. You can skip this.")
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.2))
                .padding(.top, 2)
                .padding(.bottom, 14)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    stepRow(number: 1, text: "Open Telegram and search for @BotFather") {
                        Button {
                            NSWorkspace.shared.open(URL(string: "https://t.me/BotFather")!)
                        } label: {
                            Text("Open BotFather")
                                .font(.system(size: 9))
                                .foregroundStyle(.white.opacity(0.4))
                                .underline()
                        }
                        .buttonStyle(.plain)
                        .pointingHandCursor()
                    }

                    stepRow(number: 2, text: "Send /newbot and follow the prompts") {
                        Text("Pick any name, like \"My AI Assistant\"")
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.2))
                    }

                    stepRow(number: 3, text: "Paste the token BotFather gives you:") {
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("123456:ABC-DEF1234ghIkl-zyx57W2v...", text: $onboardingVM.telegramToken)
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

                            if onboardingVM.telegramConnected {
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 9))
                                    Text("Connected")
                                        .font(.system(size: 10))
                                }
                                .foregroundStyle(.green.opacity(0.6))
                            } else {
                                OnboardingButton("Connect Telegram", disabled: onboardingVM.telegramToken.isEmpty) {
                                    onboardingVM.connectTelegram()
                                }
                            }
                        }
                    }
                }
            }

            // Skip + Continue
            HStack {
                Button { onboardingVM.advance() } label: {
                    Text("Skip for now")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.25))
                }
                .buttonStyle(.plain)
                .pointingHandCursor()

                Spacer()

                if onboardingVM.telegramConnected {
                    OnboardingButton("Continue") { onboardingVM.advance() }
                }
            }
            .padding(.top, 8)
        }
    }

    private func stepRow<Content: View>(number: Int, text: String, @ViewBuilder detail: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(AppColors.accent)
                .frame(width: 18, height: 18)
                .background(AppColors.accent.opacity(0.15))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(text)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)

                detail()
            }
        }
    }
}

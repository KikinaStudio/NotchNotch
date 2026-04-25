import SwiftUI
import AppKit

struct TelegramStep: View {
    @ObservedObject var onboardingVM: OnboardingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Chat on the go")
                .font(DS.Text.titleSmall)
                .foregroundStyle(DS.Surface.primary)

            Text("Connect Telegram to continue your conversations from your phone.")
                .font(DS.Text.micro)
                .foregroundStyle(AppColors.accent.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 3)

            Text("Takes about 1 minute. You can skip this.")
                .font(DS.Text.nano)
                .foregroundStyle(DS.Surface.quaternary)
                .padding(.top, 2)
                .padding(.bottom, 14)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    stepRow(number: 1, text: "Open Telegram and search for @BotFather") {
                        Button {
                            NSWorkspace.shared.open(URL(string: "https://t.me/BotFather")!)
                        } label: {
                            Text("Open BotFather")
                                .font(DS.Text.nano)
                                .foregroundStyle(DS.Surface.tertiary)
                                .underline()
                        }
                        .buttonStyle(.plain)
                        .pointingHandCursor()
                    }

                    stepRow(number: 2, text: "Send /newbot and follow the prompts") {
                        Text("Pick any name, like \"My AI Assistant\"")
                            .font(DS.Text.nano)
                            .foregroundStyle(DS.Surface.quaternary)
                    }

                    stepRow(number: 3, text: "Paste the token BotFather gives you:") {
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("123456:ABC-DEF1234ghIkl-zyx57W2v...", text: $onboardingVM.telegramToken)
                                .textFieldStyle(.plain)
                                .font(DS.Text.microMono)
                                // TODO(design): 0.7 hors bucket DS.Surface (entre secondary 0.55 et primary 0.85).
                                .foregroundStyle(.white.opacity(0.7))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                // TODO(design): token field bg 0.04 hors bucket DS.Surface (input field background très spécifique).
                                .background(.white.opacity(0.04))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(DS.Stroke.hairline, lineWidth: 0.5)
                                )

                            if onboardingVM.telegramConnected {
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark")
                                        .font(DS.Icon.mini)
                                    Text("Connected")
                                        .font(DS.Text.micro)
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

            // Skip + Continue (both right-aligned, separated from the Back/dots row below)
            HStack(spacing: 16) {
                Spacer()

                Button { onboardingVM.advance() } label: {
                    Text("Skip for now")
                        .font(DS.Text.micro)
                        .foregroundStyle(DS.Surface.secondary)
                }
                .buttonStyle(.plain)
                .pointingHandCursor()

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
                .font(DS.Text.sectionHead)
                .foregroundStyle(AppColors.accent)
                .frame(width: 18, height: 18)
                .background(AppColors.accent.opacity(0.15))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(text)
                    .font(DS.Text.caption)
                    // TODO(design): 0.6 hors bucket DS.Surface (entre secondary 0.55 et primary 0.85).
                    .foregroundStyle(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)

                detail()
            }
        }
    }
}

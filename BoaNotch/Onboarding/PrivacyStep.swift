import SwiftUI
import AppKit

struct PrivacyStep: View {
    @ObservedObject var onboardingVM: OnboardingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("You're in control")
                .font(DS.Text.titleSmall)
                .foregroundStyle(DS.Surface.primary)
                .padding(.bottom, 14)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 10) {
                    privacyRow(icon: "lock.shield", title: "Everything stays on your Mac.",
                               detail: "notchnotch and Hermes run locally. Your conversations are stored on your disk, not on a server.")

                    privacyRow(icon: "arrow.up.right", title: "Messages go to the AI provider you choose",
                               detail: "(like OpenRouter or OpenAI). This is the same as using ChatGPT in your browser. notchnotch has no server, no backend, no tracking.")

                    privacyRow(icon: "key", title: "Your API key stays local.",
                               detail: "It is stored in a config file on your Mac. You can revoke it anytime from your provider's website.")

                    privacyRow(icon: "terminal", title: "The agent can run commands on your Mac",
                               detail: "if you ask it to (read files, run scripts). You control this in settings. You can restrict it to a sandboxed container or require approval for every command.")

                    privacyRow(icon: "eye", title: "Open source.",
                               detail: "All the code is on GitHub. You can verify everything yourself.")
                }
            }

            Button {
                NSWorkspace.shared.open(URL(string: "https://hermes-agent.nousresearch.com/docs/reference/security/")!)
            } label: {
                Text("Learn more about security")
                    .font(DS.Text.micro)
                    .foregroundStyle(AppColors.accent.opacity(0.7))
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            .padding(.top, 8)

            HStack {
                Spacer()
                OnboardingButton("Continue") { onboardingVM.advance() }
            }
            .padding(.top, 10)
        }
    }

    private func privacyRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(DS.Icon.inline)
                .foregroundStyle(AppColors.accent.opacity(0.7))
                .frame(width: 20, alignment: .center)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DS.Text.captionMedium)
                    // TODO(design): 0.75 hors bucket DS.Surface (entre secondary 0.55 et primary 0.85).
                    .foregroundStyle(.white.opacity(0.75))
                Text(detail)
                    .font(DS.Text.micro)
                    .foregroundStyle(DS.Surface.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

import SwiftUI
import AppKit

/// First screen (H14): logo, tagline, and what happens to the user's data —
/// only what is true (D7): history on the Mac, messages to the chosen
/// provider, privacy settings on the provider's side.
struct WelcomeStep: View {
    @ObservedObject var onboardingVM: OnboardingViewModel

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            // Logo (full wordmark from SVG)
            if let nsImage = loadAppLogo() {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 200)
                    .opacity(0.9)
            }

            Text("Ton agent IA, à portée de notch.")
                .font(DS.Text.caption)
                .foregroundStyle(AppColors.accent.opacity(0.6))
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 6) {
                privacyRow(icon: "internaldrive",
                           title: "L'historique reste sur ton Mac.",
                           detail: "Hermes, l'agent, tourne ici et garde tes conversations sur ton disque.")
                privacyRow(icon: "arrow.up.right",
                           title: "Tes messages partent chez le fournisseur d'IA que tu choisis.",
                           detail: "OpenRouter par exemple. NotchNotch n'a aucun serveur entre toi et lui.")
                privacyRow(icon: "slider.horizontal.3",
                           title: "Sa confidentialité se règle chez lui.",
                           detail: "Conservation et entraînement sur tes données : dans ton compte chez ce fournisseur.")
            }
            .frame(maxWidth: 480, alignment: .leading)
            .padding(.top, 14)

            Spacer(minLength: 0)

            OnboardingButton("Commencer") { onboardingVM.advance() }

            Spacer().frame(height: 12)
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
                    .foregroundStyle(DS.Surface.primary)
                Text(detail)
                    .font(DS.Text.micro)
                    .foregroundStyle(DS.Surface.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Shared button styles

/// Primary glass button — white text on frosted surface
struct OnboardingButton: View {
    let label: String
    let action: () -> Void
    var disabled: Bool = false

    init(_ label: String, disabled: Bool = false, action: @escaping () -> Void) {
        self.label = label
        self.disabled = disabled
        self.action = action
    }

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(DS.Text.labelMedium)
                .foregroundStyle(disabled ? DS.Surface.quaternary : DS.Surface.primary)
                .padding(.horizontal, 28)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        // TODO(design): button fill 0.10/0.18 hors bucket DS.Surface (fills très spécifiques composant CTA).
                        .fill(.white.opacity(isHovered && !disabled ? 0.18 : 0.10))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        // TODO(design): button stroke 0.05/0.18 hors bucket DS.Surface (stroke composant CTA).
                        .stroke(.white.opacity(disabled ? 0.05 : 0.18), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .onHover { h in
            if !disabled { isHovered = h }
            if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}


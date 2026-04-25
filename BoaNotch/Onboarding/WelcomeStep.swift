import SwiftUI
import AppKit

struct WelcomeStep: View {
    @ObservedObject var onboardingVM: OnboardingViewModel

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Logo (full wordmark from SVG)
            if let nsImage = loadAppLogo() {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 340)
                    .opacity(0.9)
            }

            Text("Your AI agent, one knock away.")
                .font(DS.Text.caption)
                .foregroundStyle(AppColors.accent.opacity(0.6))
                .padding(.top, 4)

            Spacer()

            OnboardingButton("Get started") { onboardingVM.advance() }

            Spacer().frame(height: 24)
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

/// Wide glass button with icon
struct OnboardingWideButton: View {
    let label: String
    let icon: String
    let action: () -> Void
    var disabled: Bool = false

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(DS.Icon.glyph)
                Text(label)
                    .font(DS.Text.labelMedium)
            }
            .foregroundStyle(disabled ? DS.Surface.quaternary : DS.Surface.primary)
            .frame(maxWidth: 280)
            .padding(.vertical, 10)
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

import SwiftUI
import AppKit

struct WelcomeStep: View {
    @ObservedObject var onboardingVM: OnboardingViewModel

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Logo (full wordmark from SVG)
            if let nsImage = loadLogo() {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 340)
                    .opacity(0.9)
            }

            Text("Your AI agent, one knock away.")
                .font(.system(size: 11))
                .foregroundStyle(AppColors.accent.opacity(0.6))
                .padding(.top, 4)

            Spacer()

            OnboardingButton("Get started") { onboardingVM.advance() }

            Spacer().frame(height: 24)
        }
    }

    private func loadLogo() -> NSImage? {
        // SPM resource bundle
        if let url = Bundle.module.url(forResource: "logo-white", withExtension: "png", subdirectory: "Resources"),
           let img = NSImage(contentsOf: url) { return img }
        // Fallbacks for .app bundle
        if let url = Bundle.main.resourceURL?.appendingPathComponent("logo-white.png"),
           let img = NSImage(contentsOf: url) { return img }
        if let execURL = Bundle.main.executableURL?.deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Resources/logo-white.png"),
           let img = NSImage(contentsOf: execURL) { return img }
        return nil
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
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(disabled ? 0.25 : 0.85))
                .padding(.horizontal, 28)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.white.opacity(isHovered && !disabled ? 0.18 : 0.10))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
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
                    .font(.system(size: 12))
                Text(label)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(.white.opacity(disabled ? 0.25 : 0.85))
            .frame(maxWidth: 280)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(.white.opacity(isHovered && !disabled ? 0.18 : 0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
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

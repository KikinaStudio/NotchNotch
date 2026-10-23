import SwiftUI
import AppKit

/// Connexion step (3rd of 4, H14). Sign-in with OpenRouter via OAuth (one tap,
/// no key to copy/paste) — or, second, the "ta propre clé" row for users who
/// already have a key with OpenRouter / OpenAI / Anthropic / MiniMax.
///
/// The Choose-Model step was retired alongside this rewrite — the model is
/// auto-picked from OpenRouter's live free list (tool-capable) in the OAuth
/// flow and the pasted OpenRouter key, or seeded from
/// `HermesConfig.availableModels` for the other providers.
struct ConnectProviderStep: View {
    @ObservedObject var onboardingVM: OnboardingViewModel

    private static let advancedProviders: [(id: String, label: String)] = [
        ("openrouter", "OpenRouter"),
        ("openai",     "OpenAI"),
        ("anthropic",  "Anthropic"),
        ("minimax",    "MiniMax"),
    ]

    var body: some View {
        VStack(alignment: .center, spacing: 0) {
            Text("Connecte-toi à OpenRouter")
                .font(DS.Text.titleSmall)
                .foregroundStyle(DS.Surface.primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("Gratuit, une dizaine de secondes, sans carte bancaire.")
                .font(DS.Text.micro)
                .foregroundStyle(AppColors.accent.opacity(0.6))
                .padding(.top, 3)
                .padding(.bottom, 22)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Big primary CTA — OAuth flow
            signInButton

            if let err = onboardingVM.connectError {
                connectErrorBanner(err)
                    .padding(.top, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // "or use your own provider" separator
            HStack(spacing: 8) {
                Rectangle()
                    .fill(DS.Stroke.hairline)
                    .frame(height: 1)
                Text("ou utilise ta propre clé")
                    .font(DS.Text.nano)
                    .foregroundStyle(DS.Surface.tertiary)
                    .fixedSize()
                Rectangle()
                    .fill(DS.Stroke.hairline)
                    .frame(height: 1)
            }
            .padding(.vertical, 22)

            // Segmented row of providers — picking one reveals the API-key field
            HStack(spacing: 6) {
                ForEach(Self.advancedProviders, id: \.id) { entry in
                    providerSegment(id: entry.id, label: entry.label)
                }
            }

            if let provider = onboardingVM.advancedProvider {
                advancedKeyForm(provider: provider)
                    .padding(.top, 12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .animation(.easeInOut(duration: 0.18), value: onboardingVM.advancedProvider)
    }

    // MARK: - Sign-in CTA

    @ViewBuilder
    private var signInButton: some View {
        if onboardingVM.isConnecting {
            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.8)
                    Text("En attente de la connexion…")
                        .font(DS.Text.labelMedium)
                        .foregroundStyle(DS.Surface.secondary)
                }
                .frame(maxWidth: 280)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        // TODO(design): button fill 0.10 hors bucket DS.Surface (CTA spec OnboardingButton).
                        .fill(.white.opacity(0.10))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        // TODO(design): button stroke 0.18 hors bucket DS.Surface (CTA spec OnboardingButton).
                        .stroke(.white.opacity(0.18), lineWidth: 0.5)
                )

                Button {
                    onboardingVM.cancelOpenRouterOAuth()
                } label: {
                    Text("Annuler")
                        .font(DS.Text.micro)
                        .foregroundStyle(DS.Surface.secondary)
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
            }
        } else {
            openRouterSignInButton
        }
    }

    /// Wide CTA mirroring `OnboardingWideButton` but with OpenRouter's brand
    /// glyph (`ProviderIcon`) instead of an SF Symbol — the icon is rendered
    /// via the bundled `provider_openrouter.svg` so the user can tell at a
    /// glance which provider this signs them into.
    private var openRouterSignInButton: some View {
        SignInWithOpenRouterButton {
            Task { await onboardingVM.connectOpenRouter() }
        }
    }

    private func connectErrorBanner(_ message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(DS.Text.micro)
                .foregroundStyle(.red)
            Text(message)
                .font(DS.Text.micro)
                .foregroundStyle(.red)
                .lineLimit(3)
            Spacer()
            Button {
                onboardingVM.connectError = nil
            } label: {
                Image(systemName: "xmark")
                    .font(DS.Text.micro)
                    .foregroundStyle(DS.Surface.secondary)
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
        }
    }

    // MARK: - Advanced segmented row

    private func providerSegment(id: String, label: String) -> some View {
        let isSelected = onboardingVM.advancedProvider == id
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        return Button {
            if isSelected {
                onboardingVM.advancedProvider = nil
                onboardingVM.advancedAPIKey = ""
            } else {
                onboardingVM.advancedProvider = id
            }
        } label: {
            HStack(spacing: 5) {
                ProviderIcon(providerID: id, size: 11)
                Text(label)
                    // TODO(design): poids conditionnel actif=semibold/inactif=medium pour affordance d'état segmenté.
                    .font(DS.Text.caption.weight(isSelected ? .semibold : .medium))
            }
            .foregroundStyle(isSelected
                             ? AnyShapeStyle(Color.black.opacity(0.85))
                             : AnyShapeStyle(.secondary))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
                if isSelected { shape.fill(AppColors.accent) }
                else { shape.stroke(Color.gray.opacity(0.45), lineWidth: 1) }
            }
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }

    // MARK: - Advanced key form

    @ViewBuilder
    private func advancedKeyForm(provider: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                SecureField(apiKeyPlaceholder(for: provider), text: $onboardingVM.advancedAPIKey)
                    .textFieldStyle(.plain)
                    .font(DS.Text.caption)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary))
                    .onSubmit { Task { await onboardingVM.saveAdvancedKey(provider: provider) } }

                Button {
                    Task { await onboardingVM.saveAdvancedKey(provider: provider) }
                } label: {
                    Text("Enregistrer")
                        .font(DS.Text.caption.weight(.semibold))
                        .foregroundStyle(onboardingVM.advancedAPIKey.isEmpty
                                         ? AnyShapeStyle(.tertiary)
                                         : AnyShapeStyle(Color.black.opacity(0.85)))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background {
                            let saveShape = RoundedRectangle(cornerRadius: 8, style: .continuous)
                            if onboardingVM.advancedAPIKey.isEmpty {
                                saveShape.fill(.clear)
                            } else {
                                saveShape.fill(AppColors.accent)
                            }
                        }
                }
                .buttonStyle(.plain)
                .disabled(onboardingVM.advancedAPIKey.isEmpty)
                .pointingHandCursor()
            }

            if let urlString = OnboardingViewModel.providerKeyURLs[provider],
               let url = URL(string: urlString) {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Text("Obtenir une clé sur \(url.host ?? urlString)")
                        .font(DS.Text.nano)
                        .foregroundStyle(AppColors.accent.opacity(0.55))
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
            }
        }
    }

    private func apiKeyPlaceholder(for provider: String) -> String {
        switch provider {
        case "openrouter": return "sk-or-v1-..."
        case "openai":     return "sk-..."
        case "anthropic":  return "sk-ant-..."
        case "minimax":    return "sk-..."
        default:           return "Clé API"
        }
    }
}

// MARK: - Sign-in CTA primitive

/// Wide CTA mirroring the visual language of `OnboardingButton` but with the
/// OpenRouter brand glyph in the leading slot. Local hover state for the
/// glass-fill animation.
private struct SignInWithOpenRouterButton: View {
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                ProviderIcon(providerID: "openrouter", size: 14)
                    .foregroundStyle(DS.Surface.primary)
                Text("Se connecter avec OpenRouter")
                    .font(DS.Text.labelMedium)
                    .foregroundStyle(DS.Surface.primary)
            }
            .frame(maxWidth: 280)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    // TODO(design): button fill 0.10/0.18 hors bucket DS.Surface (composant CTA spec OnboardingButton).
                    .fill(.white.opacity(isHovered ? 0.18 : 0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    // TODO(design): button stroke 0.18 hors bucket DS.Surface (composant CTA spec OnboardingButton).
                    .stroke(.white.opacity(0.18), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .onHover { h in
            isHovered = h
            if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}

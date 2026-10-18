import SwiftUI

/// Inline picker + API-key entry for Hermes memory providers.
/// Mirrors the SettingsView.googleWorkspaceSection state-machine pattern (no modal sheet).
struct MemoryProviderSection: View {
    @StateObject private var memConfig = HermesMemoryConfig.shared
    @State private var apiKey: String = ""
    @State private var pendingProvider: MemoryProviderInfo?
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text("Fournisseur de mémoire")
                .font(DS.Text.caption)
                .foregroundStyle(.secondary)

            FlowLayout(spacing: DS.Spacing.xs) {
                ForEach(memConfig.availableProviders) { provider in
                    Button(provider.displayName) { tap(provider) }
                        .buttonStyle(SegmentedButtonStyle(isSelected: memConfig.currentProvider == provider.id))
                        .pointingHandCursor()
                }
            }

            if let line = currentProviderLine {
                Text(line)
                    .font(DS.Text.micro)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let pending = pendingProvider, let envKey = pending.requiresEnv.first {
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Text("\(envKey) : clé à copier depuis ton compte \(pending.displayName)")
                        .font(DS.Text.micro)
                        .foregroundStyle(.tertiary)
                    HStack(spacing: DS.Spacing.sm) {
                        SecureField("Colle ta clé…", text: $apiKey)
                            .textFieldStyle(.plain)
                            .font(DS.Text.caption)
                            .foregroundStyle(.primary)
                            .padding(.horizontal, DS.Padding.inputH)
                            .padding(.vertical, DS.Padding.inputV)
                            .background(RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous).fill(.quaternary))

                        Button("Enregistrer et activer") {
                            HermesConfig.shared.writeRawEnv(key: envKey, value: apiKey)
                            apiKey = ""
                            memConfig.switchTo(pending.id)
                            pendingProvider = nil
                            errorMessage = nil
                        }
                        .buttonStyle(PrimaryButtonStyleSubtle(enabled: !apiKey.isEmpty))
                        .disabled(apiKey.isEmpty)
                    }
                }
            }

            if let info = memConfig.info(for: memConfig.currentProvider), !info.isLocal, !info.isMissing {
                HStack(spacing: DS.Spacing.xs) {
                    Image(systemName: "info.circle")
                        .font(DS.Text.micro)
                    (Text("Si les réponses échouent sur une ImportError, lance une fois ")
                        .font(DS.Text.micro)
                     + Text("hermes memory setup")
                        .font(DS.Text.captionMono)
                     + Text(" dans le Terminal pour installer ses dépendances.")
                        .font(DS.Text.micro))
                    Spacer()
                }
                .foregroundStyle(.tertiary)
            }

            if let err = errorMessage {
                Text(err)
                    .font(DS.Text.micro)
                    .foregroundStyle(DS.Status.failure)
            }

            Button {
                NSWorkspace.shared.open(memConfig.info(for: memConfig.currentProvider)?.docURL
                                        ?? HermesMemoryConfig.builtIn.docURL)
            } label: {
                HStack(spacing: DS.Spacing.xs) {
                    Image(systemName: "arrow.up.right.square")
                    Text("Voir tous les fournisseurs")
                }
                .font(DS.Text.micro)
                .foregroundStyle(DS.Surface.link)
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
        }
        .onAppear {
            // Plugins and memory.provider can change outside NotchNotch (catalog install, CLI, chat).
            memConfig.loadCurrentProvider()
            memConfig.scanInstalledPlugins()
        }
        .onChange(of: memConfig.currentProvider) { _, _ in
            pendingProvider = nil
            apiKey = ""
        }
    }

    /// Tagline of the selected provider, or why Hermes isn't using it. A provider that resolves
    /// nowhere leaves Hermes on the built-in store (`agent_init.py`: no memory manager; a catalog
    /// provider may be fetched once at agent start, `recover_at_startup`).
    private var currentProviderLine: String? {
        guard let info = memConfig.info(for: memConfig.currentProvider) else { return nil }
        if info.isMissing {
            return "Introuvable sur ce Mac : tant qu'il n'est pas installé, Hermes n'utilise que la mémoire intégrée."
        }
        return info.tagline
    }

    private func tap(_ provider: MemoryProviderInfo) {
        errorMessage = nil
        guard provider.id != memConfig.currentProvider else { return }
        if provider.id.isEmpty {
            memConfig.switchTo("")
            pendingProvider = nil
            return
        }
        if provider.requiresEnv.isEmpty || memConfig.hasRequiredEnv(for: provider.id) {
            memConfig.switchTo(provider.id)
            pendingProvider = nil
        } else {
            pendingProvider = provider
        }
    }
}

/// Minimal flow layout for wrapping pill buttons (uses the SwiftUI Layout protocol,
/// available on macOS 13+). Used by both MemoryProviderSection and the SettingsView
/// AI Provider grid.
struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        for sv in subviews {
            let size = sv.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: maxWidth.isFinite ? maxWidth : x, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0
        for sv in subviews {
            let size = sv.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += lineHeight + spacing
                lineHeight = 0
            }
            sv.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

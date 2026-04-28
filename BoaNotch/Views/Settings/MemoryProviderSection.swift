import SwiftUI

/// Inline picker + API-key entry for Hermes memory providers.
/// Mirrors the SettingsView.googleWorkspaceSection state-machine pattern (no modal sheet).
struct MemoryProviderSection: View {
    @StateObject private var memConfig = HermesMemoryConfig.shared
    @State private var apiKey: String = ""
    @State private var pendingProvider: MemoryProviderInfo?
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Memory provider")
                .font(DS.Text.caption)
                .foregroundStyle(.secondary)

            FlowLayout(spacing: 4) {
                ForEach(memConfig.availableProviders) { provider in
                    pillButton(provider: provider)
                }
            }

            if let info = memConfig.info(for: memConfig.currentProvider) {
                Text(info.tagline)
                    .font(DS.Text.micro)
                    .foregroundStyle(.tertiary)
            }

            if let pending = pendingProvider, let envKey = pending.requiresEnv.first {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(envKey) (paste from \(pending.displayName) dashboard)")
                        .font(DS.Text.micro)
                        .foregroundStyle(.tertiary)
                    HStack(spacing: 6) {
                        SecureField("Paste your key…", text: $apiKey)
                            .textFieldStyle(.plain)
                            .font(DS.Text.caption)
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary))

                        Button {
                            HermesConfig.shared.writeRawEnv(key: envKey, value: apiKey)
                            apiKey = ""
                            memConfig.switchTo(pending.id)
                            pendingProvider = nil
                            errorMessage = nil
                        } label: {
                            Text("Save & activate")
                                .font(DS.Text.caption.weight(.semibold))
                                .foregroundStyle(apiKey.isEmpty ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background {
                                    let saveShape = RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    if apiKey.isEmpty {
                                        saveShape.fill(.clear)
                                    } else {
                                        saveShape.fill(AppColors.accent.opacity(0.35))
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .disabled(apiKey.isEmpty)
                        .pointingHandCursor()
                    }
                }
            }

            if !memConfig.currentProvider.isEmpty,
               let info = memConfig.info(for: memConfig.currentProvider),
               !info.isLocal {
                HStack(spacing: 4) {
                    Image(systemName: "info.circle")
                        .font(DS.Text.micro)
                    (Text("If responses fail with ImportError, run ")
                        .font(DS.Text.micro)
                     + Text("hermes memory setup")
                        .font(DS.Text.captionMono)
                     + Text(" once in Terminal to install pip deps.")
                        .font(DS.Text.micro))
                    Spacer()
                }
                .foregroundStyle(.tertiary)
            }

            if let err = errorMessage {
                Text(err)
                    .font(DS.Text.micro)
                    .foregroundStyle(.red)
            }

            Button {
                NSWorkspace.shared.open(
                    URL(string: "https://hermes-agent.nousresearch.com/docs/user-guide/features/memory-providers")!
                )
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.right.square")
                    Text("Browse all providers")
                }
                .font(DS.Text.micro)
                .foregroundStyle(AppColors.accent.opacity(0.7))
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
        }
        .onChange(of: memConfig.currentProvider) { _, _ in
            pendingProvider = nil
            apiKey = ""
        }
    }

    @ViewBuilder
    private func pillButton(provider: MemoryProviderInfo) -> some View {
        let isSelected = memConfig.currentProvider == provider.id
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        Button {
            tap(provider)
        } label: {
            Text(provider.displayName)
                .font(DS.Text.caption.weight(isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected
                                 ? AnyShapeStyle(Color.black.opacity(0.85))
                                 : AnyShapeStyle(.secondary))
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background {
                    if isSelected { shape.fill(AppColors.accent) }
                    else { shape.stroke(Color.gray.opacity(0.45), lineWidth: 1) }
                }
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }

    private func tap(_ provider: MemoryProviderInfo) {
        errorMessage = nil
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

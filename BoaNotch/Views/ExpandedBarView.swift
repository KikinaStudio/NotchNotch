import SwiftUI

struct ExpandedBarView: View {
    @ObservedObject var config: HermesConfig
    @ObservedObject var notchVM: NotchViewModel
    @ObservedObject var chatVM: ChatViewModel

    var body: some View {
        HStack(spacing: 12) {
            // Profile badge
            Menu {
                ForEach(config.availableProfiles, id: \.self) { profile in
                    Button {
                        config.activeProfile = profile
                    } label: {
                        HStack {
                            Text(profile)
                            if profile == config.activeProfile {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "person.fill")
                        .font(.caption2)
                    Text(config.activeProfile)
                        .font(.caption2.weight(.medium))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(.quaternary))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            // Model picker
            Menu {
                ForEach(config.availableModels, id: \.value) { model in
                    Button {
                        config.switchModel(model)
                    } label: {
                        HStack {
                            Text(model.label)
                            if model.value == config.modelDefault {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    ProviderIcon(providerID: config.modelProvider, size: 6)
                    Text(config.modelDisplayName)
                        .font(.caption2.weight(.medium))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(.quaternary))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            // Reasoning effort
            Menu {
                ForEach(["none", "minimal", "low", "medium", "high", "xhigh"], id: \.self) { level in
                    Button {
                        config.reasoningEffort = level
                        config.setImmediate("agent.reasoning_effort", value: level)
                    } label: {
                        HStack {
                            Text(shortLabel(level))
                            if level == config.reasoningEffort {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "brain")
                        .font(.caption2)
                    Text(shortLabel(config.reasoningEffort))
                        .font(.caption2.weight(.medium))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(.quaternary))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            // Incognito toggle
            Button {
                config.skipMemory.toggle()
                config.setImmediate("skip_memory", value: config.skipMemory)
            } label: {
                Image(systemName: config.skipMemory ? "eye.slash.fill" : "eye.slash")
                    .font(.footnote)
                    .foregroundStyle(config.skipMemory ? AnyShapeStyle(AppColors.accent) : AnyShapeStyle(.tertiary))
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            .help(config.skipMemory ? "Incognito" : "Incognito")

            Spacer()

            // Context window usage gauge
            let rawRatio = min(Double(chatVM.lastInputTokens) / Double(contextWindowLimit), 1.0)
            let color: Color = rawRatio >= 0.90 ? .red : (rawRatio >= 0.70 ? .orange : AppColors.accent)
            let pct = Int(rawRatio * 100)
            let trackWidth: CGFloat = 120
            let innerWidth = trackWidth - 4
            let visibleRatio = chatVM.lastInputTokens > 0 ? max(rawRatio, 0.05) : 0
            HStack(spacing: 6) {
                Text("Contexte")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Capsule()
                    .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
                    .frame(width: trackWidth, height: 8)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(color)
                            .frame(width: innerWidth * visibleRatio, height: 4)
                            .padding(.leading, 2)
                    }
            }
            .help("\(chatVM.lastInputTokens) tokens · \(pct)% du contexte")
            .accessibilityLabel("Contexte utilisé : \(pct) pour cent")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 6).fill(.quinary))
    }

    private var contextWindowLimit: Int {
        let m = config.modelDefault.lowercased()
        if m.contains("claude") { return 200_000 }
        if m.contains("gpt-4o") || m.contains("gpt-4.1") { return 128_000 }
        if m.contains("gpt-5") || m.contains("o1") || m.contains("o3") { return 200_000 }
        if m.contains("gemini") { return 1_000_000 }
        if m.contains("kimi") { return 200_000 }
        if m.contains("glm") { return 128_000 }
        if m.contains("mimo") { return 128_000 }
        if m.contains("nemotron") || m.contains("llama") { return 128_000 }
        if m.contains("minimax") { return 200_000 }
        if m.contains("deepseek") { return 128_000 }
        if m.contains("qwen") { return 128_000 }
        if m.contains("mistral") { return 128_000 }
        return 128_000
    }

    private func shortLabel(_ level: String) -> String {
        switch level {
        case "none": return "off"
        case "minimal": return "min"
        case "low": return "low"
        case "medium": return "med"
        case "high": return "high"
        case "xhigh": return "xhi"
        default: return level
        }
    }
}

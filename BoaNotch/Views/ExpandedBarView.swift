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
                HStack(spacing: 3) {
                    Image(systemName: "cpu")
                        .font(.caption2)
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

            // Context window usage
            if chatVM.lastInputTokens > 0 {
                Text(formatTokenCount(chatVM.lastInputTokens))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 6).fill(.quinary))
    }

    private func formatTokenCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fk", Double(count) / 1_000)
        }
        return "\(count)"
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

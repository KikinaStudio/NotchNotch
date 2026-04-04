import SwiftUI

struct ExpandedBarView: View {
    @ObservedObject var config: HermesConfig
    @ObservedObject var notchVM: NotchViewModel

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
                        .font(.system(size: 9))
                    Text(config.activeProfile)
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(.white.opacity(0.5))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.white.opacity(0.06))
                .clipShape(Capsule())
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            // Model picker
            Menu {
                ForEach(config.availableModels, id: \.value) { model in
                    Button {
                        config.modelDefault = model.value
                        config.setImmediate("model.default", value: model.value)
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
                        .font(.system(size: 9))
                    Text(config.modelDisplayName)
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(.white.opacity(0.5))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.white.opacity(0.06))
                .clipShape(Capsule())
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            // Reasoning effort segmented
            HStack(spacing: 0) {
                ForEach(["low", "medium", "high", "xhigh"], id: \.self) { level in
                    Button {
                        config.reasoningEffort = level
                        config.setImmediate("agent.reasoning_effort", value: level)
                    } label: {
                        Text(shortLabel(level))
                            .font(.system(size: 9, weight: config.reasoningEffort == level ? .bold : .regular))
                            .foregroundStyle(config.reasoningEffort == level ? .white : .white.opacity(0.35))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(config.reasoningEffort == level ? AppColors.accent.opacity(0.3) : .clear)
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(.white.opacity(0.06))
            .clipShape(Capsule())

            // Incognito toggle
            Button {
                config.skipMemory.toggle()
                config.setImmediate("skip_memory", value: config.skipMemory)
            } label: {
                Image(systemName: config.skipMemory ? "eye.slash.fill" : "eye.slash")
                    .font(.system(size: 11))
                    .foregroundStyle(config.skipMemory ? AppColors.accent : .white.opacity(0.25))
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            .help(config.skipMemory ? "Incognito" : "Incognito")

            Spacer()

            // Iteration counter + cost (read-only)
            HStack(spacing: 8) {
                Text("\(config.currentIteration)/\(config.effectiveMaxIterations)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(iterationColor)

                if config.sessionCost > 0 {
                    Text(String(format: "$%.2f", config.sessionCost))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.35))
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .overlay(alignment: .bottom) {
            // Thin iteration progress bar
            GeometryReader { geo in
                let pct = config.iterationPercentage
                RoundedRectangle(cornerRadius: 1)
                    .fill(iterationColor)
                    .frame(width: geo.size.width * min(pct, 1.0), height: 2)
                    .animation(.easeOut(duration: 0.3), value: pct)
            }
            .frame(height: 2)
        }
        .background(.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var iterationColor: Color {
        let pct = config.iterationPercentage
        if pct >= 0.95 { return .red }
        if pct >= 0.80 { return .orange }
        return .white.opacity(0.4)
    }

    private func shortLabel(_ level: String) -> String {
        switch level {
        case "low": return "low"
        case "medium": return "med"
        case "high": return "high"
        case "xhigh": return "xhi"
        default: return level
        }
    }
}

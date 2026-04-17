import SwiftUI

struct BrainOnboardingView: View {
    @ObservedObject var chatVM: ChatViewModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("hasCompletedBrainOnboarding") private var hasCompleted = false

    @State private var enableWiki = true
    @State private var enableAutoIngest = true
    @State private var enableWeeklyLint = true
    @State private var isRunning = false
    @State private var stepText = ""
    @State private var errorText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Active ton cerveau NotchNotch")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white.opacity(0.95))
                .padding(.bottom, 4)

            Text("Transforme ce que tu lis en une base de connaissance vivante.")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.55))
                .padding(.bottom, 16)

            VStack(alignment: .leading, spacing: 10) {
                toggleRow(
                    isOn: $enableWiki,
                    title: "Active le wiki intelligent",
                    subtitle: "NotchNotch compile ce que tu lis en une base de connaissance vivante."
                )
                toggleRow(
                    isOn: $enableAutoIngest,
                    title: "Ingestion automatique toutes les 2h",
                    subtitle: "Les articles clippés deviennent des fiches consultables."
                )
                toggleRow(
                    isOn: $enableWeeklyLint,
                    title: "Maintenance hebdomadaire (dimanche 9h)",
                    subtitle: "Détecte les contradictions et nettoie."
                )
            }
            .disabled(isRunning)
            .opacity(isRunning ? 0.5 : 1)

            Spacer(minLength: 14)

            if isRunning {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(AppColors.accent)
                    Text(stepText)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.65))
                }
                .padding(.bottom, 8)
            } else if let errorText {
                Text(errorText)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(red: 0.95, green: 0.45, blue: 0.45))
                    .lineLimit(2)
                    .padding(.bottom, 8)
            }

            HStack(spacing: 10) {
                Button {
                    hasCompleted = true
                    dismiss()
                } label: {
                    Text("Pas maintenant")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .disabled(isRunning)
                .pointingHandCursor()

                Button {
                    activate()
                } label: {
                    Text(errorText == nil ? "Activer" : "Réessayer")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.black.opacity(0.85))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(AppColors.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .disabled(isRunning || !anyEnabled)
                .opacity(anyEnabled ? 1 : 0.4)
                .pointingHandCursor()
            }
        }
        .padding(22)
        .frame(width: 400, height: 320)
        .background(Color.black)
    }

    private var anyEnabled: Bool {
        enableWiki || enableAutoIngest || enableWeeklyLint
    }

    private func toggleRow(isOn: Binding<Bool>, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .tint(AppColors.accent)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                Text(subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private func activate() {
        guard anyEnabled else { return }
        errorText = nil
        isRunning = true
        stepText = "Démarrage…"
        let options = BrainSetupOptions(
            enableWiki: enableWiki,
            enableAutoIngest: enableAutoIngest,
            enableWeeklyLint: enableWeeklyLint
        )
        Task { @MainActor in
            do {
                try await chatVM.setupBrainPipeline(options: options) { current, total, label in
                    stepText = "\(current)/\(total) : \(label)"
                }
                isRunning = false
                hasCompleted = true
                dismiss()
            } catch {
                isRunning = false
                errorText = "Échec : \(error.localizedDescription)"
            }
        }
    }
}

import SwiftUI

struct CustomModelSheet: View {
    let provider: String
    let onAdd: (String, String?) -> Void

    @State private var modelID = ""
    @State private var label = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Custom model for \(provider)")
                .font(DS.Text.titleSmall)

            TextField("Model ID (e.g. anthropic/claude-haiku-4-5)", text: $modelID)
                .textFieldStyle(.roundedBorder)
            TextField("Display label (optional)", text: $label)
                .textFieldStyle(.roundedBorder)

            Text("This ID is sent verbatim to the provider's API.")
                .font(DS.Text.micro)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Add") {
                    onAdd(modelID, label.isEmpty ? nil : label)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(modelID.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}

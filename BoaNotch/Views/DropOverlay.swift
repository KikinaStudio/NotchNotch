import SwiftUI

struct DropOverlay: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(
                    style: StrokeStyle(lineWidth: 2, dash: [6, 4])
                )
                .foregroundStyle(.blue.opacity(0.8))

            VStack(spacing: 4) {
                Image(systemName: "arrow.down.doc.fill")
                    .font(.system(size: 16))
                Text("Drop to attach")
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(.blue)
        }
        .background(.blue.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

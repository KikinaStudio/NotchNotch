import SwiftUI

struct DropOverlay: View {
    var body: some View {
        ZStack {
            Color(red: 0.45, green: 0.2, blue: 0.8).opacity(0.85)

            VStack(spacing: 8) {
                Image(systemName: "arrow.down.doc.fill")
                    .font(.system(size: 32, weight: .medium))
                Text("Drop to attach")
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(.white)
        }
    }
}

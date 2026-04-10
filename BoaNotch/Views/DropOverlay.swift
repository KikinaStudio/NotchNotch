import SwiftUI

struct DropOverlay: View {
    let activeZone: DropZone

    var body: some View {
        ZStack {
            Color.black

            HStack(spacing: 0) {
                zoneView(
                    icon: "paperclip",
                    title: "Attach",
                    subtitle: "Add to chat",
                    isActive: activeZone == .left
                )

                // Vertical divider
                Rectangle()
                    .fill(.white.opacity(0.15))
                    .frame(width: 1)
                    .padding(.vertical, 24)

                zoneView(
                    icon: "brain.head.profile",
                    title: "Remember",
                    subtitle: "Save to brain",
                    isActive: activeZone == .right
                )
            }
        }
    }

    private func zoneView(icon: String, title: String, subtitle: String, isActive: Bool) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .medium))
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            Text(subtitle)
                .font(.system(size: 10))
                .opacity(0.6)
        }
        .foregroundStyle(.white.opacity(isActive ? 0.9 : 0.25))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeOut(duration: 0.15), value: isActive)
    }
}

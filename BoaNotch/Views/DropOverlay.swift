import SwiftUI

struct DropOverlay: View {
    let activeZone: DropZone

    var body: some View {
        HStack(spacing: 0) {
            zoneView(
                icon: "paperclip",
                label: "Attach to chat",
                color: AppColors.dropOverlay,
                isActive: activeZone == .left
            )
            zoneView(
                icon: "brain.head.profile",
                label: "Save to brain",
                color: Color.blue.opacity(0.85),
                isActive: activeZone == .right
            )
        }
    }

    private func zoneView(icon: String, label: String, color: Color, isActive: Bool) -> some View {
        ZStack {
            color.opacity(isActive ? 0.9 : 0.55)
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: isActive ? 34 : 28, weight: .medium))
                Text(label)
                    .font(.system(size: isActive ? 16 : 14, weight: .semibold))
            }
            .foregroundStyle(.white.opacity(isActive ? 1.0 : 0.5))
            .scaleEffect(isActive ? 1.05 : 0.95)
        }
        .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.7), value: isActive)
    }
}

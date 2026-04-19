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

                Rectangle()
                    .fill(.separator)
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
                .font(.title3.weight(.medium))
            Text(title)
                .font(.callout.weight(.semibold))
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(isActive ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeOut(duration: 0.15), value: isActive)
    }
}

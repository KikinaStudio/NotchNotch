import SwiftUI

// Liquid Glass (macOS Tahoe 26+) with a graceful fallback for older systems.
// Reserve for floating/navigation chrome that sits over the desktop —
// never apply to content rows. See skills/liquid-glass-design.

extension View {
    @ViewBuilder
    func nnGlass(interactive: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            if interactive {
                self.glassEffect(.regular.interactive())
            } else {
                self.glassEffect(.regular)
            }
        } else {
            self.background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(Capsule().stroke(.white.opacity(0.15), lineWidth: 0.5))
            )
        }
    }

    @ViewBuilder
    func nnGlass<S: Shape>(in shape: S, interactive: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            if interactive {
                self.glassEffect(.regular.interactive(), in: shape)
            } else {
                self.glassEffect(.regular, in: shape)
            }
        } else {
            self.background(
                shape
                    .fill(.ultraThinMaterial)
                    .overlay(shape.stroke(.white.opacity(0.15), lineWidth: 0.5))
            )
        }
    }
}

struct NNGlassContainer<Content: View>: View {
    let spacing: CGFloat
    let content: Content

    init(spacing: CGFloat = 10, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

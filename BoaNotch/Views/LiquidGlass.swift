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
                    // TODO(design): glass material stroke (0.15), not a generic UI hairline — kept literal intentionally.
                    .overlay(Capsule().stroke(.white.opacity(0.15), lineWidth: DS.Hairline.standard))
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
                    // TODO(design): glass material stroke (0.15), not a generic UI hairline — kept literal intentionally.
                    .overlay(shape.stroke(.white.opacity(0.15), lineWidth: DS.Hairline.standard))
            )
        }
    }
}

/// Toggle visuel type "radio button" — remplace les `Toggle` SwiftUI partout
/// où on veut une affordance plus discrète. Anneau gris toujours visible,
/// pastille bleue centrée quand `on`, jaune en cas d'erreur, vide quand `off`.
///
/// `Button` interne pour propager correctement les taps vers les parents :
/// quand le parent est aussi un Button (ex: la card de routine), SwiftUI
/// route la tap à la Button la plus interne et le parent ne voit rien.
/// Avec un `.onTapGesture` parent ça ne marchait pas (les deux gestes
/// se déclenchent en cascade sur macOS).
struct StatusDotButton: View {
    enum DotState {
        case off, on, error
    }

    let state: DotState
    var dotSize: CGFloat = 7
    var ringSize: CGFloat = 18
    var hitSize: CGFloat = 24
    let action: () -> Void

    /// Convenience init for binary on/off call sites (Settings toggles).
    init(isOn: Bool, dotSize: CGFloat = 7, ringSize: CGFloat = 18, hitSize: CGFloat = 24, action: @escaping () -> Void) {
        self.state = isOn ? .on : .off
        self.dotSize = dotSize
        self.ringSize = ringSize
        self.hitSize = hitSize
        self.action = action
    }

    /// Full init with state enum (for routine cards that may show an error tint).
    init(state: DotState, dotSize: CGFloat = 7, ringSize: CGFloat = 18, hitSize: CGFloat = 24, action: @escaping () -> Void) {
        self.state = state
        self.dotSize = dotSize
        self.ringSize = ringSize
        self.hitSize = hitSize
        self.action = action
    }

    private var innerFill: Color {
        switch state {
        case .off:   return .clear
        case .on:    return AppColors.accent
        case .error: return .yellow
        }
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                Color.clear.frame(width: hitSize, height: hitSize)
                Circle()
                    .stroke(Color.gray.opacity(0.45), lineWidth: 1.2)
                    .frame(width: ringSize, height: ringSize)
                Circle()
                    .fill(innerFill)
                    .frame(width: dotSize, height: dotSize)
            }
            .contentShape(Circle())
            .animation(.easeInOut(duration: 0.18), value: state)
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
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

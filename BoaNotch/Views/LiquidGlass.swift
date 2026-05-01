import SwiftUI

// Liquid Glass (macOS Tahoe 26+) with a graceful fallback for older systems.
// Reserve for floating/navigation chrome that sits over the desktop —
// never apply to content rows. See skills/liquid-glass-design.

/// Plays SF Symbols 7 "draw on" animation when the icon's view transitions
/// in or out of the SwiftUI hierarchy (e.g. burger deploys / collapses).
/// Fires only when the parent inserts/removes the view via a conditional
/// inside an `.animation(...)` context — always-visible icons get no
/// animation, which is intentional.
/// macOS 14/15/25 → no-op, the icon appears instantly.
struct DrawOnAppearModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.transition(.symbolEffect(.drawOn))
        } else {
            content
        }
    }
}

/// Background for the notch panel: solid black when closed (camouflages the
/// hardware notch), top-down gradient from black to Liquid Glass when open
/// on macOS 26+, solid black fallback on older systems. When `inSection` is
/// true (Settings / Brain / History panel open), the gradient bottom darkens
/// to ~70% black so the surface signals "I'm in a content section" — replaces
/// the old `.quinary` rectangle-in-rectangle pattern.
struct NotchPanelBackgroundModifier: ViewModifier {
    let topCornerRadius: CGFloat
    let bottomCornerRadius: CGFloat
    let isOpen: Bool
    let inSection: Bool

    func body(content: Content) -> some View {
        if isOpen, #available(macOS 26.0, *) {
            // Bottom stop opacity: 0 = full glass bleed (chat/closed), 0.7 =
            // mostly black with a hint of glass refraction (in a section).
            let bottomOpacity: Double = inSection ? 0.7 : 0.0
            content
                .background {
                    ZStack {
                        Color.clear
                            .glassEffect(.regular, in: NotchShape(
                                topCornerRadius: topCornerRadius,
                                bottomCornerRadius: bottomCornerRadius
                            ))
                        NotchShape(
                            topCornerRadius: topCornerRadius,
                            bottomCornerRadius: bottomCornerRadius
                        )
                        .fill(LinearGradient(
                            stops: [
                                .init(color: .black, location: 0.0),
                                .init(color: .black, location: 0.45),
                                .init(color: .black.opacity(bottomOpacity), location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ))
                    }
                }
        } else {
            content
                .background {
                    NotchShape(
                        topCornerRadius: topCornerRadius,
                        bottomCornerRadius: bottomCornerRadius
                    )
                    .fill(Color.black)
                }
        }
    }
}

extension View {
    /// Applique l'effet "draw on" SF Symbols 7 à l'apparition du symbole.
    /// macOS 14/15/25 : no-op (l'icône apparaît instantanément).
    func drawOnAppear() -> some View {
        modifier(DrawOnAppearModifier())
    }

    /// Habille le panneau du notch : noir solide quand fermé, gradient
    /// noir → Liquid Glass quand ouvert sur macOS 26+ (fallback noir solide
    /// avant). Quand `inSection` est vrai, le bas du gradient s'assombrit
    /// (~70% noir) pour signaler qu'on est dans un panneau de section
    /// (Settings / Brain / History). Le clipping à la silhouette NotchShape
    /// doit être appliqué séparément par le call site.
    func notchPanelBackground(top: CGFloat, bottom: CGFloat, isOpen: Bool, inSection: Bool = false) -> some View {
        modifier(NotchPanelBackgroundModifier(
            topCornerRadius: top,
            bottomCornerRadius: bottom,
            isOpen: isOpen,
            inSection: inSection
        ))
    }

    @ViewBuilder
    func nnGlass(interactive: Bool = false, tint: Color? = nil) -> some View {
        if #available(macOS 26.0, *) {
            // Tint goes through .glassEffect(.regular.tint(...)) so it integrates
            // with refraction instead of blocking translucency (Apple's pattern).
            switch (interactive, tint) {
            case (true, let t?):  self.glassEffect(.regular.tint(t).interactive())
            case (true, nil):     self.glassEffect(.regular.interactive())
            case (false, let t?): self.glassEffect(.regular.tint(t))
            case (false, nil):    self.glassEffect(.regular)
            }
        } else {
            // Fallback: contrast layer + material on top. Tint preserves contrast
            // on bright wallpapers where .ultraThinMaterial alone would wash out.
            self.background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    // TODO(design): glass material stroke (0.15), not a generic UI hairline — kept literal intentionally.
                    .overlay(Capsule().stroke(.white.opacity(0.15), lineWidth: DS.Hairline.standard))
            )
            .background(tint.map { Capsule().fill($0) })
        }
    }

    @ViewBuilder
    func nnGlass<S: Shape>(in shape: S, interactive: Bool = false, tint: Color? = nil) -> some View {
        if #available(macOS 26.0, *) {
            switch (interactive, tint) {
            case (true, let t?):  self.glassEffect(.regular.tint(t).interactive(), in: shape)
            case (true, nil):     self.glassEffect(.regular.interactive(), in: shape)
            case (false, let t?): self.glassEffect(.regular.tint(t), in: shape)
            case (false, nil):    self.glassEffect(.regular, in: shape)
            }
        } else {
            self.background(
                shape
                    .fill(.ultraThinMaterial)
                    // TODO(design): glass material stroke (0.15), not a generic UI hairline — kept literal intentionally.
                    .overlay(shape.stroke(.white.opacity(0.15), lineWidth: DS.Hairline.standard))
            )
            .background(tint.map { shape.fill($0) })
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

import SwiftUI

/// Drop-in replacement for `ScrollView` with a soft bottom fade.
///
/// Top is intentionally NOT faded — fading content at scroll position 0 makes
/// no visual sense (there's nothing above to hide).
///
/// The fade tint matches the notch panel surface (`#0C0C0C`, calibrated 2026-04-25)
/// so the overlay is invisible where there's no content underneath, and only
/// visible where scrolling content reaches the bottom 24pt of the viewport.
/// No scroll-offset measurement needed — the panel-color tint does the work.
///
/// Usage:
/// ```
/// FadingScrollView {
///     LazyVStack { ... }
/// }
/// ```
struct FadingScrollView<Content: View>: View {
    var axes: Axis.Set = .vertical
    var fadeHeight: CGFloat = 24
    var tint: Color = FadingScrollView.panelTint
    @ViewBuilder var content: () -> Content

    /// Couleur cible du fade. `#0C0C0C` correspond au noir perçu du panneau
    /// notch après rendering macOS. Calibré 2026-04-25.
    static var panelTint: Color {
        Color(red: 0x0C / 255.0, green: 0x0C / 255.0, blue: 0x0C / 255.0)
    }

    var body: some View {
        ZStack {
            ScrollView(axes, showsIndicators: false) {
                // Padding bas = fadeHeight pour que le dernier élément
                // puisse défiler intégralement au-dessus du fade plutôt que
                // d'être coupé visuellement par le gradient.
                content()
                    .padding(.bottom, fadeHeight)
            }

            VStack(spacing: 0) {
                Spacer(minLength: 0)
                LinearGradient(
                    stops: [
                        .init(color: tint.opacity(0), location: 0),
                        .init(color: tint.opacity(0.7), location: 0.45),
                        .init(color: tint, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: fadeHeight)
            }
            .allowsHitTesting(false)
        }
    }
}

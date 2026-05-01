import SwiftUI

/// Drop-in replacement for `ScrollView` with a soft bottom fade.
///
/// Uses a SwiftUI `.mask(...)` rather than overlaying a colored gradient —
/// the content's own opacity fades to transparent at the bottom edge, so
/// whatever sits behind (solid black or Liquid Glass) shows through cleanly.
/// No background-color matching, no `#available` branching.
///
/// Top is intentionally NOT faded — fading content at scroll position 0 makes
/// no visual sense (there's nothing above to hide).
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
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView(axes, showsIndicators: false) {
            // Padding bas = fadeHeight pour que le dernier élément puisse
            // défiler intégralement au-delà de la zone de fade plutôt que
            // d'être coupé visuellement.
            content()
                .padding(.bottom, fadeHeight)
        }
        .mask(
            VStack(spacing: 0) {
                Rectangle().fill(.black)
                LinearGradient(
                    colors: [.black, .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: fadeHeight)
            }
        )
    }
}

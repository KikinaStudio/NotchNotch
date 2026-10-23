import SwiftUI

// MARK: - nnTooltip
//
// Infobulle dessinée dans le panneau, à la place de `.help()`. Les infobulles
// natives ne s'affichent jamais dans le notch (panneau `.nonactivatingPanel`
// au niveau `.mainMenu + 3` : vérifié le 2026-10-23, même avec
// `allowsToolTipsWhenApplicationIsInactive`).
//
// Survol → apparaît après `delay`, collée au-dessus (`edge: .top`) ou
// au-dessous (`.bottom`) de la vue, centrée. Ne capte pas la souris.
// Le texte part aussi en `accessibilityHint` pour VoiceOver.

extension View {
    func nnTooltip(_ text: String, edge: VerticalEdge = .bottom, delay: Duration = .milliseconds(500)) -> some View {
        modifier(NNTooltipModifier(text: text, edge: edge, delay: delay))
    }
}

private struct NNTooltipModifier: ViewModifier {
    let text: String
    let edge: VerticalEdge
    let delay: Duration

    @State private var isVisible = false
    @State private var showTask: Task<Void, Never>?

    private let gap = DS.Spacing.xs

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                showTask?.cancel()
                if hovering {
                    showTask = Task { @MainActor in
                        try? await Task.sleep(for: delay)
                        guard !Task.isCancelled else { return }
                        withAnimation(.easeOut(duration: 0.12)) { isVisible = true }
                    }
                } else {
                    withAnimation(.easeOut(duration: 0.08)) { isVisible = false }
                }
            }
            .overlay(alignment: edge == .top ? .top : .bottom) {
                if isVisible {
                    label
                        .alignmentGuide(edge == .top ? .top : .bottom) { d in
                            edge == .top ? d[.bottom] + gap : d[.top] - gap
                        }
                        .transition(.opacity)
                }
            }
            .zIndex(isVisible ? 1 : 0)
            .accessibilityHint(text)
    }

    private var label: some View {
        Text(text)
            .font(DS.Text.caption)
            .foregroundStyle(DS.Surface.primary)
            .multilineTextAlignment(.center)
            .fixedSize()
            .padding(.horizontal, DS.Padding.tooltipH)
            .padding(.vertical, DS.Padding.tooltipV)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                    .fill(DS.Surface.tooltipFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                    .strokeBorder(DS.Stroke.paletteBorder, lineWidth: DS.Stroke.lineWidth)
            )
            .allowsHitTesting(false)
    }
}

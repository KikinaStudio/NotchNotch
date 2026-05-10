import SwiftUI

// MARK: - PrimaryButtonStyle
//
// CTA primaire — fond accent plein, texte noir 0.85, opacité 0.85→1.0
// au hover/press. Pattern hover via vue interne (un ButtonStyle ne peut
// pas porter de @State directement).
//
// Doctrine : règle "Selected button text color" — jamais blanc sur accent.

struct PrimaryButtonStyle: ButtonStyle {
    let font: Font

    init(font: Font = DS.Text.caption.weight(.semibold)) {
        self.font = font
    }

    func makeBody(configuration: Configuration) -> some View {
        BodyView(configuration: configuration, font: font)
    }

    struct BodyView: View {
        let configuration: ButtonStyleConfiguration
        let font: Font
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .font(font)
                .foregroundStyle(Color.black.opacity(0.85))
                .padding(.horizontal, DS.Padding.buttonH)
                .padding(.vertical, DS.Padding.buttonV)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous)
                        .fill(AppColors.accent)
                )
                .opacity(configuration.isPressed || isHovered ? 1.0 : 0.85)
                .onHover { isHovered = $0 }
                .pointingHandCursor()
        }
    }
}

// MARK: - PrimaryButtonStyleSubtle
//
// CTA discret — fond accent.opacity(0.35), texte noir 0.85 (enabled)
// ou tertiary (disabled, fond transparent). Utilisé pour actions
// secondaires affirmatives (Save API key, Generate quand requis remplis).

struct PrimaryButtonStyleSubtle: ButtonStyle {
    let font: Font
    let enabled: Bool

    init(font: Font = DS.Text.caption.weight(.semibold), enabled: Bool = true) {
        self.font = font
        self.enabled = enabled
    }

    func makeBody(configuration: Configuration) -> some View {
        BodyView(configuration: configuration, font: font, enabled: enabled)
    }

    struct BodyView: View {
        let configuration: ButtonStyleConfiguration
        let font: Font
        let enabled: Bool
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .font(font)
                .foregroundStyle(
                    enabled
                        ? AnyShapeStyle(Color.black.opacity(0.85))
                        : AnyShapeStyle(.tertiary)
                )
                .padding(.horizontal, DS.Padding.buttonH)
                .padding(.vertical, DS.Padding.buttonV)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous)
                        .fill(enabled ? AppColors.accent.opacity(0.35) : Color.clear)
                )
                .opacity(configuration.isPressed || isHovered ? 1.0 : (enabled ? 0.85 : 0.6))
                .onHover { if enabled { isHovered = $0 } }
                .pointingHandCursor()
        }
    }
}

// MARK: - SegmentedButtonStyle
//
// Pill segmenté — fond accent + texte noir quand sélectionné, stroke
// gray 1pt + texte secondary sinon. Plus serré qu'un bouton standard
// (segmentH/V) pour densité d'un groupe.

struct SegmentedButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DS.Text.caption.weight(isSelected ? .semibold : .medium))
            .foregroundStyle(
                isSelected
                    ? AnyShapeStyle(Color.black.opacity(0.85))
                    : AnyShapeStyle(.secondary)
            )
            .padding(.horizontal, DS.Padding.segmentH)
            .padding(.vertical, DS.Padding.segmentV)
            .background {
                let shape = RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous)
                if isSelected {
                    shape.fill(AppColors.accent)
                } else {
                    shape.stroke(Color.gray.opacity(0.45), lineWidth: 1)
                }
            }
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.85 : 1.0)
    }
}

// MARK: - Preview

#Preview("Primitive Buttons") {
    VStack(spacing: 20) {
        VStack(alignment: .leading, spacing: 10) {
            Text("PrimaryButtonStyle")
                .font(DS.Text.sectionHead)
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
            HStack(spacing: 10) {
                Button("Activer") {}
                    .buttonStyle(PrimaryButtonStyle())
                Button("Réessayer") {}
                    .buttonStyle(PrimaryButtonStyle())
            }
        }

        VStack(alignment: .leading, spacing: 10) {
            Text("PrimaryButtonStyleSubtle")
                .font(DS.Text.sectionHead)
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
            HStack(spacing: 10) {
                Button("Save") {}
                    .buttonStyle(PrimaryButtonStyleSubtle(enabled: true))
                Button("Save") {}
                    .buttonStyle(PrimaryButtonStyleSubtle(enabled: false))
            }
        }

        VStack(alignment: .leading, spacing: 10) {
            Text("SegmentedButtonStyle")
                .font(DS.Text.sectionHead)
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
            HStack(spacing: 4) {
                Button("Quick") {}
                    .buttonStyle(SegmentedButtonStyle(isSelected: false))
                Button("Normal") {}
                    .buttonStyle(SegmentedButtonStyle(isSelected: true))
                Button("Deep") {}
                    .buttonStyle(SegmentedButtonStyle(isSelected: false))
            }
        }
    }
    .padding(40)
    .frame(width: 480)
    .background(Color.black)
    .preferredColorScheme(.dark)
}

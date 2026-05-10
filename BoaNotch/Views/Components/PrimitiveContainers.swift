import SwiftUI

// MARK: - PanelSection
//
// Section structurée d'un panel : header monospace UPPERCASE +
// optionnel count à droite + contenu. Doctrine "Section headers"
// CLAUDE.md : 9pt mono bold (DS.Text.sectionHead) tracking 1.5,
// jamais accent.

struct PanelSection<Content: View>: View {
    let title: String
    let count: Int?
    @ViewBuilder let content: () -> Content

    init(_ title: String, count: Int? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.count = count
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text(title)
                    .font(DS.Text.sectionHead)
                    .tracking(1.5)
                    .textCase(.uppercase)
                    // TODO(design): tokeniser DS.Surface.headerLow (white 0.28)
                    .foregroundStyle(Color.white.opacity(0.28))
                if let count = count, count > 0 {
                    Text("\(count)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.bottom, DS.Spacing.sm)

            content()
        }
    }
}

// MARK: - CardCompact
//
// Card compacte 10pt radius, padding 14×12, fond .quaternary 0.5.
// Pas de hover state intégré — le call-site gère son propre hover si besoin.

struct CardCompact<Content: View>: View {
    @ViewBuilder let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        content()
            .padding(.horizontal, DS.Padding.cardCompactH)
            .padding(.vertical, DS.Padding.cardCompactV)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.cardCompact, style: .continuous)
                    .fill(.quaternary.opacity(0.5))
            )
    }
}

// MARK: - CardProminent
//
// Card prominente 12pt radius, padding 14×16, fond .quaternary 0.6.
// Pour contenu primaire (memoryCardCompact, templateCard, MissionsActivityBanner).

struct CardProminent<Content: View>: View {
    @ViewBuilder let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        content()
            .padding(.horizontal, DS.Padding.cardProminentH)
            .padding(.vertical, DS.Padding.cardProminentV)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .fill(.quaternary.opacity(0.6))
            )
    }
}

// MARK: - ListRow
//
// Row dense de liste : padding 14×6, hauteur min 32pt. Pas de divider
// intégrée, pas de fond — le call-site est responsable d'intercaler
// des Hairline entre les rows si besoin.

struct ListRow<Content: View>: View {
    @ViewBuilder let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        content()
            .padding(.horizontal, DS.Padding.rowH)
            .padding(.vertical, DS.Padding.rowV)
            .frame(minHeight: DS.Layout.rowMinHeight)
    }
}

// MARK: - Hairline

struct Hairline: View {
    var body: some View {
        Rectangle()
            .fill(DS.Stroke.hairline)
            .frame(height: DS.Hairline.standard)
    }
}

// MARK: - notchPanelInsets

enum NotchPanelVariant {
    case standard
    case chat
}

extension View {
    /// Applique les insets standardisés des panels NotchView (top/horizontal/bottom).
    /// `.standard` pour Settings/Brain/History, `.chat` pour ChatView (top plus serré,
    /// bottom plus large pour l'input bar).
    func notchPanelInsets(variant: NotchPanelVariant) -> some View {
        modifier(NotchPanelInsetsModifier(variant: variant))
    }
}

private struct NotchPanelInsetsModifier: ViewModifier {
    let variant: NotchPanelVariant

    func body(content: Content) -> some View {
        switch variant {
        case .standard:
            content
                .padding(.top, DS.Layout.panelTopInset)
                .padding(.horizontal, DS.Layout.panelHorizontalInset)
                .padding(.bottom, DS.Layout.panelBottomInset)
        case .chat:
            content
                .padding(.top, DS.Layout.chatTopInset)
                .padding(.horizontal, DS.Layout.panelHorizontalInset)
                .padding(.bottom, DS.Layout.chatBottomInset)
        }
    }
}

// MARK: - Preview

#Preview("Primitive Containers") {
    ScrollView {
        VStack(alignment: .leading, spacing: 24) {
            PanelSection("À propos de toi", count: 7) {
                VStack(alignment: .leading, spacing: 8) {
                    CardProminent {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Préférences").font(DS.Text.bodyMedium)
                            Text("Aime les briefs courts").font(DS.Text.caption).foregroundStyle(.secondary)
                        }
                    }
                    CardProminent {
                        Text("Travaille à Paris")
                            .font(DS.Text.body)
                    }
                }
            }

            Hairline()

            PanelSection("Compétences", count: 12) {
                VStack(spacing: 0) {
                    ListRow {
                        HStack {
                            Image(systemName: "globe").font(DS.Icon.caption)
                            Text("web_search").font(DS.Text.bodySmall)
                            Spacer()
                            Text("officiel").font(DS.Text.badge).foregroundStyle(.secondary)
                        }
                    }
                    Hairline()
                    ListRow {
                        HStack {
                            Image(systemName: "terminal").font(DS.Icon.caption)
                            Text("terminal").font(DS.Text.bodySmall)
                            Spacer()
                            Text("officiel").font(DS.Text.badge).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            CardCompact {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles").font(DS.Icon.large)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Card compacte").font(DS.Text.bodyMedium)
                        Text("14×12 padding · radius 10").font(DS.Text.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .notchPanelInsets(variant: .standard)
    }
    .frame(width: 680, height: 540)
    .background(Color.black)
    .preferredColorScheme(.dark)
}

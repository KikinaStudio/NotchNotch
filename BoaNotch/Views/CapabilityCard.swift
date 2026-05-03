import SwiftUI

/// Single source of visual truth for a capability row, used by:
///   - `BrainView.toolsTab` Section 2 (installed capacities, grouped by category)
///   - `SkillsHubView` Écran 1 (catalogue of available capacities)
///
/// Visual language : 10pt rounded rect with `.quaternary.opacity(0.5)` fill,
/// 14H × 12V padding, SF Symbol icon left, name + optional badge top-right of
/// the text block, 2-line description below, hover-revealed chevron right.
/// 8pt vertical gap between adjacent cards is owned by the parent's `LazyVStack`
/// spacing — the card itself has no outer margin.
struct CapabilityCard: View {

    /// Provenance pill rendered next to the title. `OFFICIEL` for capacities
    /// from the Hermes-curated repo (`source == "official"` or
    /// `trust_level == "builtin"`). `COMMUNAUTÉ` for the rest (skills.sh and
    /// other community sources). Absent for un-decorated rows (technical
    /// skills not present in `~/.hermes/skills/.hub/lock.json`).
    enum BadgeKind: Equatable {
        case officiel
        case communaute
    }

    let icon: String
    let title: String
    let description: String
    var badge: BadgeKind? = nil
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, alignment: .center)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(DS.Text.bodyMedium)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        if let badge {
                            badgeView(badge)
                        }
                    }
                    if !description.isEmpty {
                        Text(description)
                            .font(DS.Text.nano)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .truncationMode(.tail)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                Image(systemName: "chevron.right")
                    .font(DS.Icon.chevron)
                    .foregroundStyle(.tertiary)
                    .opacity(isHovered ? 1 : 0)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(shape)
            .background(shape.fill(.quaternary.opacity(0.5)))
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.12), value: isHovered)
    }

    @ViewBuilder
    private func badgeView(_ kind: BadgeKind) -> some View {
        // Tinted-fill tag style — text in accent (or muted white for
        // community), background in a lighter opacity of the same color, no
        // stroke. Same visual rule as `BrainView.appOfficialBadge`.
        let (label, fg, bg): (String, Color, Color) = {
            switch kind {
            case .officiel:
                return ("Officiel",
                        AppColors.accent,
                        AppColors.accent.opacity(0.18))
            case .communaute:
                return ("Communauté",
                        Color.white.opacity(0.55),
                        Color.white.opacity(0.08))
            }
        }()
        Text(label)
            .font(.system(size: 8, weight: .medium))
            .foregroundStyle(fg)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(bg))
            .layoutPriority(1)
    }
}

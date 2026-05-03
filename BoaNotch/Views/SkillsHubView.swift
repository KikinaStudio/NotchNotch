import SwiftUI

/// Plein-panneau overlay rendered above BrainView's content. Exposes the
/// Hermes Skills Hub catalogue to non-technical users via a 3-screen drill-down
/// (catalogue → preview → confirmation). All copy is French; never uses the
/// words "skill", "hub", "scan", "install" — see CLAUDE.md "Curated Skills
/// connect rule" for the same UX doctrine that drives Zone 2.
struct SkillsHubView: View {
    @ObservedObject var hub: SkillsHubViewModel
    let onClose: () -> Void

    var body: some View {
        ZStack {
            // Solid backdrop covers BrainView and absorbs any pass-through
            // hits — there's no transparent moment because we never want the
            // user to interact with the underlying tab while the catalogue is
            // foregrounded.
            Color.black

            VStack(spacing: 0) {
                header
                    .padding(.bottom, 12)

                Group {
                    switch hub.screen {
                    case .catalog:
                        catalogScreen
                    case .preview(let skill):
                        previewScreen(for: skill)
                    case .installing(let skill):
                        installingScreen(skill: skill)
                    case .installed(let skill):
                        installedScreen(skill: skill)
                    case .installError(let skill, let msg):
                        errorScreen(skill: skill, message: msg)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .task {
            // Re-fetch each time the overlay appears so freshly-published
            // catalogue items show without restarting the app.
            await hub.loadCatalog()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text(headerTitle)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(1)
            Spacer(minLength: 8)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(DS.Icon.topBar)
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            .help("Fermer")
        }
    }

    private var headerTitle: String {
        switch hub.screen {
        case .catalog: return "Catalogue de capacités"
        case .preview: return "Détails"
        case .installing: return "Ajout en cours…"
        case .installed: return "Capacité ajoutée"
        case .installError: return "L'ajout a échoué"
        }
    }

    // MARK: - Screen 1 — Catalog

    private var catalogScreen: some View {
        VStack(alignment: .leading, spacing: 12) {
            searchField

            switch hub.phase {
            case .loading:
                loadingPlaceholder("Recherche en cours…")
            case .error(let msg):
                errorBanner(msg)
            case .ready:
                if hub.visibleSkills.isEmpty {
                    emptyState(message: hub.query.isEmpty
                               ? "Aucune capacité disponible pour le moment."
                               : "Aucune capacité ne correspond à ta recherche.")
                } else {
                    catalogList
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(DS.Icon.glyph)
                .foregroundStyle(.tertiary)
            TextField("Cherche une capacité…", text: Binding(
                get: { hub.query },
                set: { hub.updateQuery($0) }
            ))
            .textFieldStyle(.plain)
            .font(DS.Text.bodySmall)
            .foregroundStyle(.primary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.quaternary.opacity(0.4))
        )
    }

    private var catalogList: some View {
        FadingScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(hub.visibleSkills) { skill in
                    catalogRow(skill)
                }
            }
        }
    }

    /// Renders a hub catalogue row via the shared `CapabilityCard` component
    /// — same visual as Section 2 in `BrainView.toolsTab`. Single source of
    /// truth for capacity rows across the app.
    private func catalogRow(_ skill: HubSkill) -> some View {
        CapabilityCard(
            icon: iconForRow(skill),
            title: humanName(skill.name),
            description: skill.description,
            badge: badgeFor(skill),
            onTap: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    hub.openPreview(skill)
                }
            }
        )
    }

    /// Maps the hub source/trust pair to the shared badge enum. `OFFICIEL`
    /// covers `source == "official"` and `trust == "builtin"` (the helper
    /// stamps every official entry with `builtin`). Everything else is
    /// `COMMUNAUTÉ` (skills.sh + any non-curated source).
    private func badgeFor(_ skill: HubSkill) -> CapabilityCard.BadgeKind {
        if skill.source == "official" || skill.trust == "builtin" {
            return .officiel
        }
        return .communaute
    }

    // MARK: - Screen 2 — Preview

    private func previewScreen(for skill: HubSkill) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            backButton {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    hub.backToCatalog()
                }
            }
            .padding(.bottom, 12)

            if hub.detailLoading && hub.detail == nil {
                loadingPlaceholder("Chargement…")
            } else if let err = hub.detailError {
                VStack(spacing: 12) {
                    errorBanner(err)
                    Button {
                        Task { await hub.loadCatalog() }
                        hub.backToCatalog()
                    } label: {
                        Text("Retour au catalogue")
                            .font(DS.Text.caption.weight(.semibold))
                            .foregroundStyle(Color.black.opacity(0.85))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(AppColors.accent)
                            )
                    }
                    .buttonStyle(.plain)
                    .pointingHandCursor()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let detail = hub.detail {
                FadingScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(humanName(detail.name))
                                .font(DS.Text.title)
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                            provenancePill(skill: skill, detail: detail)
                        }

                        Text(detail.description)
                            .font(DS.Text.bodySmall)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if !detail.requiresEnv.isEmpty {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "key.fill")
                                    .font(DS.Icon.glyph)
                                    .foregroundStyle(.tertiary)
                                Text("Cette capacité pourrait te demander une clé API au premier usage.")
                                    .font(DS.Text.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(.quaternary.opacity(0.3))
                            )
                        }

                        if !detail.skillMdPreview.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Aperçu")
                                    .font(DS.Text.sectionHead)
                                    .tracking(1.5)
                                    .textCase(.uppercase)
                                    .foregroundStyle(Color.white.opacity(0.28))
                                ScrollView {
                                    Text(detail.skillMdPreview)
                                        .font(DS.Text.captionMono)
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.leading)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(10)
                                        .textSelection(.enabled)
                                }
                                .frame(maxHeight: 220)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(.quaternary.opacity(0.4))
                                )
                            }
                        }
                    }
                }

                addButton
                    .padding(.top, 8)
            } else {
                loadingPlaceholder("Chargement…")
            }
        }
    }

    private func provenancePill(skill: HubSkill, detail: HubSkillDetail) -> some View {
        let (label, tint): (String, Color) = {
            // `source == "official"` OR `trust == "builtin"` → official Hermes
            // (green pastille). The browse helper marks every official entry
            // with `trust == "builtin"`, so this catches both signals.
            let isOfficial = (detail.source == "official") || (skill.source == "official") || (skill.trust == "builtin")
            if isOfficial {
                return ("Officiel Hermes", Color.green.opacity(0.85))
            }
            // skills.sh items default to `trust == "trusted"` per the helper —
            // we map to lime. Community entries (other sources, or explicit
            // `community` trust) get yellow.
            switch skill.trust {
            case "trusted":
                return ("Source de confiance", Color(red: 0.74, green: 0.93, blue: 0.42))
            case "community":
                return ("Communauté", Color(red: 0.97, green: 0.83, blue: 0.30))
            default:
                return ("Communauté", Color(red: 0.97, green: 0.83, blue: 0.30))
            }
        }()
        return HStack(spacing: 6) {
            Circle().fill(tint).frame(width: 7, height: 7)
            Text(label)
                .font(DS.Text.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var addButton: some View {
        Button {
            hub.install()
        } label: {
            Text("Ajouter à mon agent")
                .font(DS.Text.caption.weight(.semibold))
                .foregroundStyle(Color.black.opacity(0.85))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(AppColors.accent)
                )
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }

    // MARK: - Screen 3 — Install lifecycle

    private func installingScreen(skill: HubSkill) -> some View {
        VStack(spacing: 18) {
            Spacer()
            BrailleSpinner(size: 22)
            Text("Ajout de \(humanName(skill.name))…")
                .font(DS.Text.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text("Ça peut prendre une minute si la capacité doit être téléchargée.")
                .font(DS.Text.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func installedScreen(skill: HubSkill) -> some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(Color.green.opacity(0.85))
            Text("\(humanName(skill.name)) ajoutée")
                .font(DS.Text.title)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
            Text("Tu peux la retrouver dans Outils.")
                .font(DS.Text.caption)
                .foregroundStyle(.secondary)
            Button {
                onClose()
            } label: {
                Text("Voir dans Outils")
                    .font(DS.Text.caption.weight(.semibold))
                    .foregroundStyle(Color.black.opacity(0.85))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(AppColors.accent)
                    )
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            .padding(.top, 6)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorScreen(skill: HubSkill, message: String) -> some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(Color.red.opacity(0.75))
            Text("L'ajout n'a pas abouti")
                .font(DS.Text.title)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
            Text(message)
                .font(DS.Text.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        hub.dismissInstallResult()
                    }
                } label: {
                    Text("Retour au catalogue")
                        .font(DS.Text.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.white.opacity(0.18), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
            }
            .padding(.top, 6)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func backButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                    .font(.caption.weight(.semibold))
                Text("Catalogue")
                    .font(.footnote.weight(.medium))
                    .lineLimit(1)
            }
            .foregroundStyle(AppColors.accent)
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }

    private func loadingPlaceholder(_ message: String) -> some View {
        VStack(spacing: 12) {
            BrailleSpinner(size: 14)
            Text(message)
                .font(DS.Text.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorBanner(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(DS.Icon.large)
                .foregroundStyle(Color.red.opacity(0.7))
            Text(message)
                .font(DS.Text.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func emptyState(message: String) -> some View {
        Text(message)
            .font(DS.Text.caption)
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Best-effort SF Symbol for the catalogue row's leading icon. Falls back
    /// to puzzlepiece for anything unfamiliar so the row reads as "an
    /// extension piece my agent can pick up".
    private func iconForRow(_ skill: HubSkill) -> String {
        let lower = skill.name.lowercased()
        if lower.contains("password") || lower.contains("auth") || lower.contains("vault") { return "lock.fill" }
        if lower.contains("git") || lower.contains("repo") { return "chevron.left.forwardslash.chevron.right" }
        if lower.contains("note") || lower.contains("memo") { return "note.text" }
        if lower.contains("calendar") || lower.contains("agenda") { return "calendar" }
        if lower.contains("mail") || lower.contains("email") || lower.contains("inbox") { return "envelope.fill" }
        if lower.contains("music") || lower.contains("song") || lower.contains("track") { return "music.note" }
        if lower.contains("doc") || lower.contains("file") || lower.contains("folder") { return "doc.fill" }
        if lower.contains("image") || lower.contains("photo") || lower.contains("picture") { return "photo.fill" }
        if lower.contains("video") || lower.contains("youtube") { return "video.fill" }
        if lower.contains("chart") || lower.contains("data") || lower.contains("plot") { return "chart.bar.fill" }
        if lower.contains("draw") || lower.contains("design") { return "paintbrush.fill" }
        if lower.contains("brain") || lower.contains("memory") || lower.contains("wiki") { return "brain" }
        if lower.contains("search") || lower.contains("find") { return "magnifyingglass.circle.fill" }
        if lower.contains("flight") || lower.contains("travel") { return "airplane" }
        if lower.contains("weather") { return "cloud.sun.fill" }
        if lower.contains("home") || lower.contains("hue") { return "house.fill" }
        if lower.contains("game") { return "gamecontroller.fill" }
        if lower.contains("shop") || lower.contains("buy") { return "bag.fill" }
        return "puzzlepiece.fill"
    }

    /// `google-workspace` → `Google Workspace`. `1password` → `1Password`.
    private func humanName(_ name: String) -> String {
        let parts = name.split(separator: "-")
        return parts.map { token -> String in
            let s = String(token)
            if s.first?.isNumber == true {
                // Digit-led (e.g. "1password") — capitalize from second char.
                guard s.count > 1 else { return s }
                let first = s.first!
                let rest = s.dropFirst().capitalized
                return String(first) + rest
            }
            return s.capitalized
        }.joined(separator: " ")
    }
}

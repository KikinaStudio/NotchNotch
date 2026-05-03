import SwiftUI
import AppKit

enum BrainTab: String, CaseIterable {
    case brain = "Memory"
    case tools = "Tools"
    case tasks = "Missions"
}

struct BrainView: View {
    @ObservedObject var brainVM: BrainViewModel
    @ObservedObject var chatVM: ChatViewModel
    @ObservedObject var notchVM: NotchViewModel
    /// Cron job state for the Missions tab activity banner. Sourced from
    /// `~/.hermes/cron/jobs.json` via `CronStore`'s file watcher — updates
    /// on every cron tick, no polling.
    @ObservedObject var cronStore: CronStore
    /// Auto-send callback — used by wiki "Ask" buttons. Sets chatVM.draft and
    /// fires send().
    var onSendToChat: ((String) -> Void)?
    /// Pre-fill callback — used by curated skill prompt examples. Sets
    /// chatVM.draft and focuses the composer, but does NOT send. Lets the
    /// user edit before triggering the request.
    var onPrefillChat: ((String) -> Void)?
    /// Embedded view for the Tasks tab (RoutinesView wired by NotchView so we
    /// don't need to pass cronStore/CronJob types into BrainView).
    var tasksContent: () -> AnyView = { AnyView(EmptyView()) }
    @StateObject private var googleConnection = GoogleConnectionState()
    /// Owns the catalogue overlay state (lazy fetch + screen drill-down).
    /// Recreated each time BrainView mounts (i.e. each time the user opens
    /// the Brain panel from a closed state) — fits the "fermer Brain ferme
    /// aussi le catalogue" cascade described in CLAUDE.md.
    @StateObject private var skillsHub = SkillsHubViewModel()
    @State private var selectedSkill: SkillInfo?
    @State private var selectedCuratedSkill: CuratedSkill?
    @State private var selectedMemoryBlock: MemoryBlock?
    @State private var hoveredMemoryId: String?
    @State private var hoveredCuratedId: String?
    @State private var capabilitiesSearchQuery: String = ""
    @State private var browseButtonHovered: Bool = false
    @State private var syncPulseScale: CGFloat = 1.0

    /// Categories of `technicalSkillCategories` whose row list is collapsed.
    /// "Installées" (synthetic group) is expanded by default on first load;
    /// other categories collapsed. Initialized lazily by
    /// `initializeZone3CollapseIfNeeded()`.
    @State private var collapsedTechnicalCategories: Set<String> = []
    @State private var didInitializeZone3Collapse = false

    private let lightMetricsTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            // Content (tabs now live in NotchView's top bar)
            ZStack {
                contentForTab
                    .opacity((selectedSkill == nil && selectedMemoryBlock == nil && selectedCuratedSkill == nil) ? 1 : 0)
                    .allowsHitTesting(!notchVM.isSkillsHubOpen)

                if let skill = selectedSkill {
                    skillDetailView(skill: skill) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            selectedSkill = nil
                        }
                    }
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing),
                        removal: .move(edge: .trailing)
                    ))
                }

                if let curated = selectedCuratedSkill {
                    CuratedSkillDetailView(
                        skill: curated,
                        state: brainVM.curatedSkillStates[curated.id] ?? .available,
                        googleConnection: googleConnection,
                        onBack: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                selectedCuratedSkill = nil
                            }
                        },
                        onAskExample: { prompt in
                            onPrefillChat?(prompt)
                        },
                        onStateRefresh: {
                            brainVM.refreshLightMetrics()
                        }
                    )
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing),
                        removal: .move(edge: .trailing)
                    ))
                }

                if let block = selectedMemoryBlock {
                    memoryBlockDetail(block: block)
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing),
                            removal: .move(edge: .trailing)
                        ))
                }
            }
        }
        .overlay {
            // Catalogue de capacités (cf CLAUDE.md "Documented exception —
            // Skills Hub"). Couvre toute la surface BrainView. Indépendant
            // des autres panneaux : son flag `isSkillsHubOpen` n'est pas
            // dans `closeAllPanels`. Fermer Brain depuis le X global ferme
            // ce panel par cascade naturelle (le @StateObject est détruit
            // avec BrainView, et NotchView reset le flag dans son onChange).
            if notchVM.isSkillsHubOpen {
                SkillsHubView(hub: skillsHub) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        notchVM.isSkillsHubOpen = false
                    }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing),
                    removal: .opacity
                ))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: notchVM.isSkillsHubOpen)
        .onAppear {
            brainVM.refreshLightMetrics()
            googleConnection.refresh()
            // Wire the catalogue overlay's "already installed" filter and
            // its post-install refresh hook. Re-armed on every BrainView
            // mount because the StateObject is recreated each time.
            skillsHub.installedNames = Set(brainVM.skills.map { $0.name.lowercased() })
            skillsHub.onInstalled = { [weak brainVM] in
                brainVM?.reload()
            }
        }
        .onReceive(lightMetricsTimer) { _ in
            brainVM.refreshLightMetrics()
            googleConnection.refresh()
        }
        .onChange(of: brainVM.allMemoryBlocks.map(\.id)) { _, ids in
            if let sel = selectedMemoryBlock, !ids.contains(sel.id) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    selectedMemoryBlock = nil
                }
            }
        }
        .onChange(of: brainVM.skills.count) { _, _ in
            skillsHub.installedNames = Set(brainVM.skills.map { $0.name.lowercased() })
        }
    }

    // MARK: - Tab content

    @ViewBuilder
    private var contentForTab: some View {
        switch brainVM.activeTab {
        case .brain: brainTab
        case .tools: toolsTab
        case .tasks: tasksTab
        }
    }

    // MARK: - Brain tab (Memory + optional Wiki, merged in one scroll)

    private var brainTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            tabIntro("Ce qu'Hermes sait, sur toi et sur le monde.")

            FadingScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    memorySection

                    if brainVM.hasWiki {
                        Rectangle()
                            .fill(DS.Stroke.hairline)
                            .frame(height: 1)
                            .padding(.vertical, 20)
                        wikiSection
                    }
                }
                .padding(.bottom, 8)
            }
        }
    }

    private var memorySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("À propos de toi", count: brainVM.allMemoryBlocks.count)

            if brainVM.allMemoryBlocks.isEmpty {
                emptyState("Hermes n'a encore rien appris.\nCommence à discuter, il retiendra ce qui compte.")
                    .padding(.vertical, 16)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(brainVM.allMemoryBlocks) { block in
                        memoryCardCompact(block)
                    }
                }
            }
        }
    }

    private var wikiSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("À propos du monde", count: brainVM.wikiArticles.count)

            if brainVM.wikiArticles.isEmpty {
                wikiEmptyState
                    .padding(.vertical, 16)
            } else {
                // Dashboard caption
                HStack(spacing: 6) {
                    Text(topicsCopy(brainVM.wikiArticles.count))
                    if let lastUpdate = brainVM.wikiLastUpdated {
                        Text("· Dernière intégration il y a \(shortFrenchRelative(from: lastUpdate))")
                    }
                    syncButton
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 6)

                // Article list
                VStack(spacing: 2) {
                    ForEach(brainVM.wikiArticles) { article in
                        Button {
                            askAboutArticle(article)
                        } label: {
                            HStack {
                                if article.isIndex {
                                    Image(systemName: "pin.fill")
                                        .font(.caption2)
                                        .foregroundStyle(AppColors.accent.opacity(0.55))
                                }
                                Text(article.title)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                Spacer()
                                Text("Ask")
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(AppColors.accent.opacity(0.6))
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 8)
                        }
                        .buttonStyle(.plain)
                        .pointingHandCursor()
                    }
                }
            }
        }
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(DS.Text.sectionHead)
                .tracking(1.5)
                .textCase(.uppercase)
                .foregroundStyle(Color.white.opacity(0.28))
            if count > 0 {
                Text("\(count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.bottom, 8)
    }

    private func memoryCardCompact(_ block: MemoryBlock) -> some View {
        let cardShape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: iconForCategory(block.category))
                    .font(DS.Icon.caption)
                    .foregroundStyle(AppColors.accent)
                    .frame(width: 14, alignment: .leading)
                Text(memoryTitleAttributed(block))
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Text(memoryPreview(block))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardShape.fill(.quaternary.opacity(0.6)))
        .overlay(
            cardShape
                .fill(hoveredMemoryId == block.id ? AnyShapeStyle(DS.Stroke.hairline) : AnyShapeStyle(Color.clear))
                .allowsHitTesting(false)
        )
        .contentShape(Rectangle())
        .onHover { over in hoveredMemoryId = over ? block.id : nil }
        .onTapGesture {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                selectedMemoryBlock = block
            }
        }
        .pointingHandCursor()
        .animation(.easeInOut(duration: 0.15), value: hoveredMemoryId == block.id)
    }

    private func memoryBlockDetail(block: MemoryBlock) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    selectedMemoryBlock = nil
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.caption.weight(.semibold))
                    Text(block.category)
                        .font(.footnote.weight(.medium))
                        .lineLimit(1)
                }
                .foregroundStyle(AppColors.accent)
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            .padding(.bottom, 10)

            FadingScrollView {
                MemoryCard(
                    block: block,
                    onUpdate: { newContent in
                        chatVM.updateMemory(oldContent: block.content, newContent: newContent)
                        scheduleBrainReload()
                    },
                    onDelete: {
                        chatVM.deleteMemory(content: block.content)
                        scheduleBrainReload()
                    }
                )
            }
        }
    }

    private func memoryTitleAttributed(_ block: MemoryBlock) -> AttributedString {
        (try? AttributedString(
            markdown: block.title,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(block.title)
    }

    private func memoryPreview(_ block: MemoryBlock) -> String {
        let trimmed = block.content
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed
    }

    /// Heuristic mapping from a memory category label to an SF Symbol.
    /// Matches keywords case-insensitively in FR + EN; falls back to a generic
    /// tag glyph for unknown categories.
    private func iconForCategory(_ raw: String) -> String {
        let lower = raw.lowercased()
        if lower.contains("perso") || lower.contains("user") || lower.contains("profil") || lower.contains("identi") {
            return "person.fill"
        }
        if lower.contains("famille") || lower.contains("family") || lower.contains("friend") || lower.contains("ami") {
            return "person.2.fill"
        }
        if lower.contains("work") || lower.contains("travail") || lower.contains("project") || lower.contains("projet") || lower.contains("kikina") || lower.contains("boulot") {
            return "briefcase.fill"
        }
        if lower.contains("travel") || lower.contains("voyage") || lower.contains("trip") {
            return "airplane"
        }
        if lower.contains("health") || lower.contains("santé") || lower.contains("sante") || lower.contains("medic") {
            return "heart.fill"
        }
        if lower.contains("finance") || lower.contains("money") || lower.contains("argent") || lower.contains("budget") || lower.contains("bank") {
            return "dollarsign.circle.fill"
        }
        if lower.contains("food") || lower.contains("nourriture") || lower.contains("recipe") || lower.contains("cuisine") || lower.contains("restau") {
            return "fork.knife"
        }
        if lower.contains("hermes") || lower.contains("agent") || lower.contains("assistant") || lower.contains("ai") {
            return "sparkles"
        }
        if lower.contains("note") || lower.contains("journal") || lower.contains("idée") || lower.contains("idea") {
            return "note.text"
        }
        if lower.contains("tech") || lower.contains("dev") || lower.contains("code") || lower.contains("programm") {
            return "chevron.left.forwardslash.chevron.right"
        }
        if lower.contains("home") || lower.contains("maison") || lower.contains("appart") {
            return "house.fill"
        }
        if lower.contains("learn") || lower.contains("study") || lower.contains("étud") || lower.contains("etude") || lower.contains("school") {
            return "book.fill"
        }
        if lower.contains("music") || lower.contains("musique") || lower.contains("song") {
            return "music.note"
        }
        if lower.contains("event") || lower.contains("événement") || lower.contains("evenement") || lower.contains("calendar") || lower.contains("agenda") {
            return "calendar"
        }
        return "tag.fill"
    }

    private func tabIntro(_ text: String) -> some View {
        Text(text)
            .font(DS.Text.caption)
            .foregroundStyle(AppColors.accent)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, 12)
    }

    private var blockDivider: some View {
        Divider().padding(.leading, 14)
    }

    // MARK: - Tools tab (2 sections : Apps + Capacités)

    private var toolsTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            tabIntro("Ce que ton agent peut faire pour toi.")

            FadingScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    appsSection
                    capabilitiesSection
                        .padding(.top, 24)
                }
                .padding(.bottom, 8)
            }
        }
        .onAppear {
            initializeZone3CollapseIfNeeded()
        }
        .onChange(of: brainVM.technicalSkills.count) { _, _ in
            initializeZone3CollapseIfNeeded()
        }
        .onChange(of: brainVM.hubInstalled.count) { old, new in
            // After a fresh install, ensure "Installées" is expanded so the
            // newly-added capacity is visible (even if the user had collapsed
            // it manually).
            if new > old {
                collapsedTechnicalCategories.remove(SkillCategoryGroup.installedViaHubID)
            }
        }
    }

    /// On first non-empty load, expand "Installées" if it exists, else expand
    /// the first category. Subsequent calls only prune stale ids without
    /// auto-expanding new ones (the user's collapse choices win).
    private func initializeZone3CollapseIfNeeded() {
        let categories = technicalSkillCategories
        guard !categories.isEmpty else { return }
        let allIds = Set(categories.map(\.id))
        if !didInitializeZone3Collapse {
            let installedID = SkillCategoryGroup.installedViaHubID
            let expandedId = allIds.contains(installedID) ? installedID : categories.first?.id
            collapsedTechnicalCategories = allIds.subtracting([expandedId].compactMap { $0 })
            didInitializeZone3Collapse = true
        } else {
            collapsedTechnicalCategories = collapsedTechnicalCategories.intersection(allIds)
        }
    }

    /// Section header shared by Section 1 (Apps) and Section 2 (Capacités).
    /// Distinct from category sub-headers inside Section 2 which use the
    /// uppercase mono `DS.Text.sectionHead`.
    private func zoneHeader(icon: String, label: String, count: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.callout.weight(.medium))
                .foregroundStyle(.tertiary)
            Text(label)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.primary)
            Spacer(minLength: 8)
            Text("\(count)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: Section 1 — Apps (curated capabilities, 3-column card grid)

    private var appsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            zoneHeader(icon: "app.badge",
                       label: "Apps",
                       count: CuratedSkillCatalog.all.count)

            // 3-column fixed grid : avec 6 Apps curées on a 2 lignes pile.
            // `.flexible()` partage la largeur dispo en parts égales — le
            // panel `.standard` donne ~180pt par card, `.large` ~250pt.
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ],
                alignment: .leading,
                spacing: 10
            ) {
                ForEach(CuratedSkillCatalog.all) { skill in
                    appCard(skill)
                }
            }
        }
    }

    /// Card 3-par-ligne pour une App curée. Layout 2 lignes : icône + badge
    /// "Officiel" en haut, nom en bas. **L'état connecté/non-connecté est
    /// porté par la card elle-même** (Liquid Glass : couches translucides +
    /// hairline neutre), pas par un label texte explicite. L'accent
    /// (`AppColors.accent`) est réservé au hover — au repos, le contraste se
    /// joue sur la matière (fill + hairline neutre).
    ///
    ///   • Connectée : fill `.quaternary.opacity(0.50)`, hairline blanche
    ///     `0.10` 1pt — la card a du poids, l'icône brand color signe le lien.
    ///   • Non-connectée : fill `.quaternary.opacity(0.20)` (ghostée), hairline
    ///     blanche `0.04` (presque invisible) — la card s'efface.
    ///   • Hover : stroke accent (plus vibrant sur connectée, plus doux sur
    ///     non-connectée qui invite à la connexion).
    ///
    /// L'icône reste désaturée à `.primary.opacity(0.35)` quand `.available`,
    /// le nom passe `.primary` → `.secondary` — ces 2 signaux de typographie
    /// s'ajoutent au traitement de la card.
    private func appCard(_ skill: CuratedSkill) -> some View {
        let state = brainVM.curatedSkillStates[skill.id] ?? .available
        let isConnected: Bool = {
            if case .connected = state { return true }
            return false
        }()
        let isHovered = hoveredCuratedId == skill.id
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)

        let fillOpacity: Double = isConnected ? 0.50 : 0.20
        let strokeColor: Color = {
            if isHovered {
                return AppColors.accent.opacity(isConnected ? 0.55 : 0.35)
            }
            // Neutral hairline at rest — accent reserved for hover.
            return isConnected
                ? Color.white.opacity(0.10)
                : Color.white.opacity(0.04)
        }()

        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                selectedCuratedSkill = skill
            }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 0) {
                    BrandIconView(kind: skill.icon, size: 28, desaturated: !isConnected)
                    Spacer(minLength: 4)
                    appOfficialBadge
                }

                Text(skill.displayName)
                    .font(DS.Text.bodyMedium)
                    .foregroundStyle(isConnected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(shape)
            .background(shape.fill(.quaternary.opacity(fillOpacity)))
            .overlay(shape.stroke(strokeColor, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .onHover { over in hoveredCuratedId = over ? skill.id : nil }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: isConnected)
    }

    /// Tinted-fill tag style (inspired by the user-supplied "Medium" pill
    /// reference — text in accent blue, background in a lighter opacity of
    /// the same accent, no stroke). Smaller and more discreet than the
    /// previous outlined variant. Same shape used by `CapabilityCard.badgeView`
    /// for consistency.
    private var appOfficialBadge: some View {
        Text("Officiel")
            .font(.system(size: 8, weight: .medium))
            .foregroundStyle(AppColors.accent)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(AppColors.accent.opacity(0.18)))
    }

    // MARK: Section 2 — Capacités (technical skills, card-style, grouped)

    private var capabilitiesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            capabilitiesHeader

            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(filteredTechnicalSkillCategories) { group in
                    technicalCategoryBlock(group)
                }
            }
        }
    }

    /// Header de Section 2 spécifique : titre + count à gauche, search field
    /// in-line au milieu, bouton "+ Parcourir" en accent à droite. Le
    /// `zoneHeader(...)` partagé (Section 1) ne convient pas ici parce qu'on
    /// veut une recherche locale et un CTA de navigation.
    private var capabilitiesHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "wrench.adjustable")
                .font(.callout.weight(.medium))
                .foregroundStyle(.tertiary)
            Text("Capacités")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.primary)
            Text("\(brainVM.technicalSkills.count)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)

            Spacer(minLength: 8)

            capabilitiesSearchField
                .frame(maxWidth: 220)

            browseButton
        }
    }

    private var capabilitiesSearchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.caption)
                .foregroundStyle(.tertiary)
            TextField("Filtrer…", text: $capabilitiesSearchQuery)
                .textFieldStyle(.plain)
                .font(DS.Text.caption)
                .foregroundStyle(.primary)
            if !capabilitiesSearchQuery.isEmpty {
                Button {
                    capabilitiesSearchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.quaternary.opacity(0.4))
        )
    }

    /// Bouton accent ouvrant le catalogue overlay. **Unique point d'entrée
    /// vers le catalogue** — la card d'invitation dashed précédente a été
    /// retirée le 2026-05-04 au profit d'un CTA inline dans le header de
    /// section, plus dense et cohérent avec le pattern Routines `[+ New]`.
    private var browseButton: some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                notchVM.isSkillsHubOpen = true
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.caption.weight(.semibold))
                Text("Parcourir")
                    .font(DS.Text.caption.weight(.semibold))
            }
            .foregroundStyle(Color.black.opacity(0.85))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(AppColors.accent.opacity(browseButtonHovered ? 1.0 : 0.85))
            )
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .help("Parcourir le catalogue de capacités")
        .onHover { browseButtonHovered = $0 }
        .animation(.easeInOut(duration: 0.15), value: browseButtonHovered)
    }

    private func technicalCategoryBlock(_ group: SkillCategoryGroup) -> some View {
        // When the user is searching, force every visible category open so
        // matches aren't hidden behind a closed disclosure. The underlying
        // `collapsedTechnicalCategories` set is preserved; clearing the
        // search query restores the user's manual collapse state.
        let isExpanded = isSearchActive || !collapsedTechnicalCategories.contains(group.id)
        let header = headerInfo(for: group)
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    if isExpanded {
                        collapsedTechnicalCategories.insert(group.id)
                    } else {
                        collapsedTechnicalCategories.remove(group.id)
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: header.icon)
                        .font(DS.Text.sectionHead)
                        .foregroundStyle(Color.white.opacity(0.28))
                    Text(header.label)
                        .font(DS.Text.sectionHead)
                        .tracking(1.5)
                        .textCase(.uppercase)
                        .foregroundStyle(Color.white.opacity(0.28))
                    Spacer(minLength: 8)
                    Text("\(group.skills.count)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                    Image(systemName: "chevron.right")
                        .font(DS.Icon.chevronBold)
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointingHandCursor()

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(group.skills) { skill in
                        CapabilityCard(
                            icon: SkillIconCatalog.icon(for: skill, fallback: iconForSkillCategory),
                            title: skill.name,
                            description: skill.description,
                            badge: badgeFor(skill),
                            onTap: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                    selectedSkill = skill
                                }
                            }
                        )
                    }
                }
                .padding(.top, 4)
                .padding(.bottom, 8)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .top)),
                    removal: .opacity
                ))
            }
        }
    }

    /// Sub-header icon + French label per group. The synthetic
    /// `installedViaHub` group gets `sparkles` + "Installées" — we picked
    /// `sparkles` over `square.and.arrow.down.fill` because it reads as
    /// "fraîchement ajouté par toi" rather than "downloads folder".
    private func headerInfo(for group: SkillCategoryGroup) -> (icon: String, label: String) {
        switch group.kind {
        case .installedViaHub:
            return ("sparkles", "Installées")
        case .category(let name):
            return (iconForSkillCategory(name), labelForSkillCategory(name))
        }
    }

    /// Maps a hub-installed skill to its provenance badge. Skills not present
    /// in `hubInstalled` (i.e. bundled or local) receive no badge.
    private func badgeFor(_ skill: SkillInfo) -> CapabilityCard.BadgeKind? {
        guard let meta = brainVM.hubInstalled[skill.name] else { return nil }
        if meta.source == "official" || meta.trustLevel == "builtin" {
            return .officiel
        }
        return .communaute
    }

    // MARK: - Tasks tab (RoutinesView embedded)

    private var tasksTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            MissionsActivityBanner(
                cost: brainVM.costThisMonth,
                forecast: brainVM.costForecastMonth,
                dailyCounts: brainVM.dailySessionCounts,
                failures: cronFailures7Days,
                healthyJobs: cronJobsHealthy7Days
            )

            // Intro is rendered inside RoutinesView's own header so it can sit
            // on the same row as the [+ New] button (saves vertical space).
            tasksContent()
        }
    }

    // MARK: - Missions tab — cron health derivation

    /// ISO8601 with microsecond fractional seconds, matching the format
    /// Hermes writes to `jobs.json` (e.g. `2026-05-03T09:01:03.751106+02:00`).
    /// `ISO8601DateFormatter` only accepts 3-digit fractions, so we use
    /// `DateFormatter` with explicit `SSSSSS`. Fallback for jobs whose
    /// `last_run_at` lacks fractional seconds.
    private static let cronTimestampFull: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSXXXXX"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static let cronTimestampNoFrac: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXXXX"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static func parseCronTimestamp(_ s: String) -> Date? {
        cronTimestampFull.date(from: s) ?? cronTimestampNoFrac.date(from: s)
    }

    private var cronFailures7Days: Int {
        let cutoff = Date().addingTimeInterval(-7 * 86_400)
        return cronStore.jobs.reduce(into: 0) { count, job in
            guard job.last_status == "error",
                  let lastRunStr = job.last_run_at,
                  let date = Self.parseCronTimestamp(lastRunStr),
                  date >= cutoff else { return }
            count += 1
        }
    }

    private var cronJobsHealthy7Days: Int {
        let cutoff = Date().addingTimeInterval(-7 * 86_400)
        return cronStore.jobs.reduce(into: 0) { count, job in
            guard job.last_status == "ok",
                  let lastRunStr = job.last_run_at,
                  let date = Self.parseCronTimestamp(lastRunStr),
                  date >= cutoff else { return }
            count += 1
        }
    }

    /// French label for a Hermes skill category — replaces raw English keys
    /// (e.g. `software-development`, `mlops`) with neophyte-friendly text.
    /// Unknown categories fall back to a Title-cased version of the raw key.
    private func labelForSkillCategory(_ category: String) -> String {
        switch category.lowercased() {
        case "media": return "Médias"
        case "productivity": return "Productivité"
        case "creative": return "Création"
        case "devops": return "DevOps & Serveurs"
        case "note-taking": return "Prise de notes"
        case "research": return "Recherche"
        case "social-media": return "Réseaux sociaux"
        case "email": return "E-mail"
        case "github": return "Code & GitHub"
        case "data-science": return "Données"
        case "diagramming": return "Schémas"
        case "domain": return "Noms de domaine"
        case "leisure": return "Loisirs"
        case "music-creation": return "Création musicale"
        case "smart-home": return "Maison connectée"
        case "software-development": return "Développement logiciel"
        case "feeds": return "Flux RSS"
        case "gaming": return "Jeu vidéo"
        case "gifs": return "GIFs"
        case "mlops": return "Machine learning"
        case "red-teaming": return "Sécurité offensive"
        case "apple": return "Apple"
        case "dogfood": return "Dogfood"
        case "inference-sh": return "Inference.sh"
        case "mcp": return "MCP"
        case "autonomous-ai-agents": return "Agents IA"
        default:
            return category
                .replacingOccurrences(of: "-", with: " ")
                .replacingOccurrences(of: "_", with: " ")
                .capitalized
        }
    }

    /// SF Symbol picker for a Hermes skill category. Falls back to a generic
    /// tag glyph for unknown categories. Adding a category here is fire-and-
    /// forget — Hermes can ship new skills under new categories anytime.
    private func iconForSkillCategory(_ category: String) -> String {
        switch category.lowercased() {
        case "media": return "music.note"
        case "productivity": return "briefcase.fill"
        case "creative": return "paintbrush.fill"
        case "devops": return "server.rack"
        case "note-taking": return "note.text"
        case "research": return "magnifyingglass.circle.fill"
        case "social-media": return "person.2.fill"
        case "email": return "envelope.fill"
        case "github": return "chevron.left.forwardslash.chevron.right"
        case "data-science": return "chart.bar.fill"
        case "diagramming": return "rectangle.connected.to.line.below"
        case "domain": return "globe"
        case "leisure": return "sparkles"
        case "music-creation": return "music.mic"
        case "smart-home": return "house.fill"
        case "software-development": return "hammer.fill"
        case "feeds": return "antenna.radiowaves.left.and.right"
        case "gaming": return "gamecontroller.fill"
        case "gifs": return "photo.stack"
        case "mlops": return "cpu"
        case "red-teaming": return "shield.lefthalf.filled"
        case "apple": return "applelogo"
        case "dogfood": return "pawprint.fill"
        case "inference-sh": return "bolt.fill"
        case "mcp": return "puzzlepiece.fill"
        case "autonomous-ai-agents": return "brain"
        default: return "tag.fill"
        }
    }

    private struct SkillCategoryGroup: Identifiable {
        enum Kind: Equatable {
            /// Pseudo-category for capacities installed via the catalogue.
            /// Sourced from `~/.hermes/skills/.hub/lock.json`. Always rendered
            /// at the top of the list with the "Installées" label.
            case installedViaHub
            /// Real on-disk category from `skill.category` (e.g. "productivity",
            /// "media", etc.).
            case category(String)
        }

        static let installedViaHubID = "_hub_installed_"

        let kind: Kind
        let skills: [SkillInfo]

        var id: String {
            switch kind {
            case .installedViaHub: return Self.installedViaHubID
            case .category(let name): return name
            }
        }
    }

    /// Returns `technicalSkillCategories` filtered by `capabilitiesSearchQuery`
    /// (case-insensitive on `name + description`). Empty groups are dropped so
    /// only categories with matches remain visible. When the query is empty,
    /// returns the full list unchanged.
    private var filteredTechnicalSkillCategories: [SkillCategoryGroup] {
        let q = capabilitiesSearchQuery
            .lowercased()
            .trimmingCharacters(in: .whitespaces)
        let all = technicalSkillCategories
        guard !q.isEmpty else { return all }
        return all.compactMap { group in
            let filtered = group.skills.filter {
                $0.name.lowercased().contains(q)
                    || $0.description.lowercased().contains(q)
            }
            guard !filtered.isEmpty else { return nil }
            return SkillCategoryGroup(kind: group.kind, skills: filtered)
        }
    }

    private var isSearchActive: Bool {
        !capabilitiesSearchQuery.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Partitions `brainVM.technicalSkills` into:
    ///   1. A synthetic `installedViaHub` group (skills present in
    ///      `~/.hermes/skills/.hub/lock.json`) at the top.
    ///   2. Remaining skills grouped by their real on-disk category, sorted
    ///      alphabetically.
    /// A hub-installed skill is removed from its native category to avoid
    /// double-listing.
    private var technicalSkillCategories: [SkillCategoryGroup] {
        let hubNames = Set(brainVM.hubInstalled.keys)
        let installedViaHub = brainVM.technicalSkills.filter { hubNames.contains($0.name) }
        let rest = brainVM.technicalSkills.filter { !hubNames.contains($0.name) }
        var result: [SkillCategoryGroup] = []
        if !installedViaHub.isEmpty {
            let sortedInstalled = installedViaHub.sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
            result.append(SkillCategoryGroup(kind: .installedViaHub, skills: sortedInstalled))
        }
        let grouped = Dictionary(grouping: rest, by: \.category)
        let sorted = grouped
            .map { SkillCategoryGroup(kind: .category($0.key), skills: $0.value) }
            .sorted { a, b in
                switch (a.kind, b.kind) {
                case (.category(let na), .category(let nb)):
                    return na.localizedStandardCompare(nb) == .orderedAscending
                default:
                    return false
                }
            }
        result.append(contentsOf: sorted)
        return result
    }

    // MARK: - Wiki empty state (used by `wikiSection` inside `brainTab`)

    private var wikiEmptyState: some View {
        Text(
            (try? AttributedString(
                markdown: "Ton cerveau est vide. Installe [l'extension NotchNotch-Clipper](https://github.com/KikinaStudio/NotchNotch-Clipper) et clippe ton premier article."
            )) ?? AttributedString("Ton cerveau est vide.")
        )
        .font(.callout)
        .foregroundStyle(.tertiary)
        .multilineTextAlignment(.center)
        .tint(AppColors.accent.opacity(0.7))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 16)
    }

    // MARK: - Sync button

    private var syncButton: some View {
        Button {
            triggerIngestion()
        } label: {
            Group {
                if brainVM.isIngesting {
                    ProgressView()
                        .controlSize(.mini)
                        .scaleEffect(0.6)
                        .frame(width: 11, height: 11)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.footnote)
                        .foregroundStyle(brainVM.pendingRawCount > 0 ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                        .scaleEffect(brainVM.pendingRawCount > 0 ? syncPulseScale : 1.0)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(brainVM.pendingRawCount == 0 || brainVM.isIngesting)
        .pointingHandCursor()
        .help(syncTooltip)
        .onAppear {
            if brainVM.pendingRawCount > 0 { startSyncPulse() }
        }
        .onChange(of: brainVM.pendingRawCount) { _, newValue in
            if newValue > 0 {
                startSyncPulse()
            } else {
                withAnimation(.easeInOut(duration: 0.3)) { syncPulseScale = 1.0 }
            }
        }
    }

    private var syncTooltip: String {
        if brainVM.pendingRawCount > 0 {
            return "Intégrer maintenant (\(brainVM.pendingRawCount) en attente)"
        }
        return "Cerveau à jour"
    }

    private func startSyncPulse() {
        syncPulseScale = 1.0
        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
            syncPulseScale = 0.95
        }
    }

    private func triggerIngestion() {
        guard brainVM.pendingRawCount > 0, !brainVM.isIngesting else { return }
        brainVM.isIngesting = true
        onSendToChat?("Utilise le skill llm-wiki pour ingérer le contenu en attente dans ~/.hermes/brain/raw/")
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak brainVM] in
            brainVM?.isIngesting = false
        }
    }

    // MARK: - French copy helpers

    private func topicsCopy(_ count: Int) -> String {
        count == 1 ? "Ton cerveau connaît 1 sujet" : "Ton cerveau connaît \(count) sujets"
    }

    private func shortFrenchRelative(from date: Date) -> String {
        let seconds = max(0, Date().timeIntervalSince(date))
        if seconds < 3600 {
            let minutes = max(1, Int(seconds / 60))
            return "\(minutes) min"
        } else if seconds < 86400 {
            return "\(Int(seconds / 3600))h"
        } else {
            return "\(Int(seconds / 86400))j"
        }
    }

    /// Reload the brain panel a few seconds after a memory edit/delete so the
    /// fresh MEMORY.md / USER.md state (rewritten by Hermes) flows back into
    /// the UI. Hermes may take longer than 5s for complex edits; users can hit
    /// the refresh button if the change hasn't landed yet.
    private func scheduleBrainReload() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak brainVM] in
            brainVM?.reload()
        }
    }

    private func askAboutArticle(_ article: WikiArticle) {
        if article.isIndex {
            onSendToChat?("Résume-moi ton wiki")
        } else {
            onSendToChat?("Qu'est-ce que tu sais sur \(article.title) ?")
        }
    }

    // MARK: - Skill detail view

    /// Drill-down rendered when a CapabilityCard in Section 2 is tapped. Uses
    /// `SkillMarkdownView` for block-aware markdown (headings, lists, code
    /// blocks, quotes) instead of the previous flat `AttributedString` —
    /// otherwise raw `##` and `**` markers leaked to the user. Footer carries
    /// a single CTA "Voir dans le Finder" that reveals the skill's `SKILL.md`
    /// in Finder so power users can inspect the source.
    private func skillDetailView(skill: SkillInfo, onBack: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onBack) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.caption.weight(.semibold))
                    Text(skill.name)
                        .font(.footnote.weight(.medium))
                        .lineLimit(1)
                }
                .foregroundStyle(AppColors.accent)
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            .padding(.bottom, 10)

            FadingScrollView {
                SkillMarkdownView(content: skill.content)
                    .padding(.bottom, 4)
            }

            HStack {
                Spacer()
                Button {
                    revealSkillInFinder(skill)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "folder")
                            .font(.caption.weight(.semibold))
                        Text("Voir dans le Finder")
                            .font(DS.Text.caption.weight(.semibold))
                    }
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
                .help("Ouvrir le dossier de la capacité")
            }
            .padding(.top, 8)
        }
    }

    /// Reveals `~/.hermes/skills/<category>/<name>/SKILL.md` in Finder via
    /// `NSWorkspace.activateFileViewerSelecting`. `SkillInfo.id` is already
    /// the `<category>/<name>` path-fragment used by `loadSkills()` — no
    /// extra resolution needed.
    private func revealSkillInFinder(_ skill: SkillInfo) {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let skillMd = homeDir
            .appendingPathComponent(".hermes/skills")
            .appendingPathComponent(skill.id)
            .appendingPathComponent("SKILL.md")
        if FileManager.default.fileExists(atPath: skillMd.path) {
            NSWorkspace.shared.activateFileViewerSelecting([skillMd])
        } else {
            // Fall back to the skill folder if SKILL.md is missing for any
            // reason — at least the user lands somewhere useful.
            let folder = homeDir
                .appendingPathComponent(".hermes/skills")
                .appendingPathComponent(skill.id)
            NSWorkspace.shared.activateFileViewerSelecting([folder])
        }
    }

    // MARK: - Shared components

    private func emptyState(_ message: String) -> some View {
        Text(message)
            .font(.callout)
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Memory card

struct MemoryCard: View {
    let block: MemoryBlock
    var onUpdate: ((String) -> Void)?
    var onDelete: (() -> Void)?

    @EnvironmentObject var appearanceSettings: AppearanceSettings
    @State private var isEditing = false
    @State private var isHovering = false
    @State private var confirmingDelete = false
    @State private var draft: String = ""
    @FocusState private var editorFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("§")
                    .font(DS.Text.serifMark)
                    .foregroundStyle(AppColors.accent.opacity(0.6))
                Text(titleAttributed)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 6)

                if !isEditing {
                    actionButtons
                        .opacity(isHovering || confirmingDelete ? 1 : 0)
                        .animation(.easeInOut(duration: 0.12), value: isHovering)
                        .animation(.easeInOut(duration: 0.12), value: confirmingDelete)
                }
            }

            if isEditing {
                editor
                    .padding(.leading, 14)
            } else {
                Text(markdownContent)
                    // TODO(design): textSize.scale dynamique (medium=1.0/large=1.25), pas tokenisable.
                    .font(.system(size: 11 * appearanceSettings.textSize.scale))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .padding(.leading, 14)
            }
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }

    // MARK: - Action buttons (hover reveal)

    private var actionButtons: some View {
        HStack(spacing: 10) {
            if confirmingDelete {
                Text("Supprimer ?")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                Button("Oui") {
                    confirmingDelete = false
                    onDelete?()
                }
                .buttonStyle(.plain)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.red.opacity(0.85))
                .pointingHandCursor()
                Button("Annuler") {
                    confirmingDelete = false
                }
                .buttonStyle(.plain)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .pointingHandCursor()
            } else {
                Button {
                    draft = block.content
                    isEditing = true
                    DispatchQueue.main.async { editorFocused = true }
                } label: {
                    Image(systemName: "pencil")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
                .help("Modifier")

                Button {
                    confirmingDelete = true
                } label: {
                    Image(systemName: "trash")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
                .help("Supprimer")
            }
        }
    }

    // MARK: - Inline editor

    private var editor: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextEditor(text: $draft)
                // TODO(design): textSize.scale dynamique (medium=1.0/large=1.25), pas tokenisable.
                .font(.system(size: 11 * appearanceSettings.textSize.scale))
                .scrollContentBackground(.hidden)
                .background(DS.Stroke.hairline)
                .foregroundStyle(.primary)
                .frame(minHeight: 80, maxHeight: 220)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(DS.Stroke.hairline, lineWidth: 1)
                )
                .cornerRadius(6)
                .focused($editorFocused)

            HStack(spacing: 10) {
                Spacer()
                Button("Annuler") {
                    isEditing = false
                    draft = ""
                }
                .buttonStyle(.plain)
                .font(.caption.weight(.medium))
                .foregroundStyle(.tertiary)
                .pointingHandCursor()

                Button("Enregistrer") {
                    let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty, trimmed != block.content.trimmingCharacters(in: .whitespacesAndNewlines) else {
                        isEditing = false
                        return
                    }
                    onUpdate?(trimmed)
                    isEditing = false
                }
                .buttonStyle(.plain)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppColors.accent)
                .pointingHandCursor()
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
    }

    private var titleAttributed: AttributedString {
        (try? AttributedString(
            markdown: block.title,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(block.title)
    }

    private var markdownContent: AttributedString {
        (try? AttributedString(
            markdown: block.content,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(block.content)
    }
}

// MARK: - Curated skill drill-down

/// Detail view for a curated capability. Surfaces the connect/disconnect
/// action as a structured button (OAuth, API key form, external link) rather
/// than a chat-mediated request — see CLAUDE.md "Curated Skills connect rule".
struct CuratedSkillDetailView: View {
    let skill: CuratedSkill
    let state: CuratedSkillState
    @ObservedObject var googleConnection: GoogleConnectionState
    let onBack: () -> Void
    let onAskExample: (String) -> Void
    let onStateRefresh: () -> Void

    @State private var apiKeyDraft: String = ""
    @State private var showingApiKeyForm: Bool = false
    @State private var localError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onBack) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.caption.weight(.semibold))
                    Text(skill.displayName)
                        .font(.footnote.weight(.medium))
                        .lineLimit(1)
                }
                .foregroundStyle(AppColors.accent)
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            .padding(.bottom, 14)

            FadingScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    hero
                    statusLine
                    Text(skill.descriptionFR)
                        .font(DS.Text.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    promptExamplesSection

                    actionSection
                        .padding(.top, 4)

                    if let err = localError {
                        Text(err)
                            .font(DS.Text.caption)
                            .foregroundStyle(.red)
                    }
                }
                .padding(.bottom, 12)
            }
        }
    }

    // MARK: - Hero + status

    private var hero: some View {
        HStack(alignment: .center, spacing: 12) {
            BrandIconView(kind: skill.icon, size: 40)
                .frame(width: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(skill.displayName)
                    .font(DS.Text.title)
                    .foregroundStyle(.primary)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        switch state {
        case .connected(let detail):
            HStack(spacing: 6) {
                Circle().fill(Color.green.opacity(0.85)).frame(width: 7, height: 7)
                if let detail, !detail.isEmpty {
                    Text("Connecté · \(detail)")
                        .font(DS.Text.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Connecté")
                        .font(DS.Text.caption)
                        .foregroundStyle(.secondary)
                }
            }
        case .available:
            EmptyView()
        }
    }

    // MARK: - Prompt examples

    private var promptExamplesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(promptExamplesHeader)
                .font(DS.Text.sectionHead)
                .tracking(1.5)
                .textCase(.uppercase)
                .foregroundStyle(Color.white.opacity(0.28))
                .padding(.bottom, 2)

            ForEach(skill.promptExamplesFR, id: \.self) { example in
                Button {
                    if isInteractive { onAskExample(example) }
                } label: {
                    HStack(spacing: 8) {
                        Text(example)
                            .font(DS.Text.bodySmall)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if isInteractive {
                            Image(systemName: "arrow.up.right")
                                .font(DS.Icon.chevron)
                                .foregroundStyle(AppColors.accent.opacity(0.55))
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                            .fill(.quaternary.opacity(0.4))
                    )
                }
                .buttonStyle(.plain)
                .disabled(!isInteractive)
                .pointingHandCursor()
            }
        }
    }

    private var promptExamplesHeader: String {
        switch state {
        case .connected: return "Tu peux dire à ton agent"
        case .available: return "Avec ton agent, tu pourras"
        }
    }

    private var isInteractive: Bool {
        switch state {
        case .connected: return true
        case .available: return false
        }
    }

    // MARK: - Action section (connect / disconnect / external)

    @ViewBuilder
    private var actionSection: some View {
        switch (state, skill.connectAction) {
        case (_, .none):
            EmptyView()

        case (.connected, .oauth(.google)):
            disconnectButton(label: "Déconnecter Google") {
                googleConnection.disconnect()
                onStateRefresh()
            }

        case (.available, .oauth(.google)):
            connectGoogleButton

        case (.connected, .apiKeyInput(let envName, _, _)):
            disconnectButton(label: "Supprimer la clé") {
                HermesConfig.shared.writeRawEnv(key: envName, value: "")
                onStateRefresh()
            }

        case (.available, .apiKeyInput(let envName, let helpText, let helpURL)):
            apiKeyForm(envName: envName, helpText: helpText, helpURL: helpURL)

        case (.connected, .external(let url)),
             (.available, .external(let url)):
            externalLinkButton(url: url)
        }
    }

    private var connectGoogleButton: some View {
        Button {
            Task {
                await googleConnection.connect()
                onStateRefresh()
            }
        } label: {
            HStack(spacing: 6) {
                if googleConnection.isConnecting {
                    ProgressView().controlSize(.mini).scaleEffect(0.7)
                } else {
                    Image(systemName: "link")
                        .font(DS.Icon.chevron)
                }
                Text(googleConnection.isConnecting ? "Connexion…" : "Connecter Google")
                    .font(DS.Text.caption.weight(.semibold))
            }
            .foregroundStyle(Color.black.opacity(0.85))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(AppColors.accent)
            )
        }
        .buttonStyle(.plain)
        .disabled(googleConnection.isConnecting)
        .pointingHandCursor()
    }

    private func apiKeyForm(envName: String, helpText: String, helpURL: URL?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !showingApiKeyForm {
                Button {
                    showingApiKeyForm = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "key.fill").font(DS.Icon.chevron)
                        Text("Saisir ma clé API")
                            .font(DS.Text.caption.weight(.semibold))
                    }
                    .foregroundStyle(Color.black.opacity(0.85))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(AppColors.accent)
                    )
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text(helpText)
                        .font(DS.Text.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let helpURL {
                        Button {
                            NSWorkspace.shared.open(helpURL)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.up.right.square")
                                Text("Ouvrir le tableau de bord")
                            }
                            .font(DS.Text.caption)
                            .foregroundStyle(AppColors.accent.opacity(0.8))
                        }
                        .buttonStyle(.plain)
                        .pointingHandCursor()
                    }

                    Text(envName)
                        .font(DS.Text.captionMono)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 2)

                    HStack(spacing: 6) {
                        SecureField("Colle ta clé…", text: $apiKeyDraft)
                            .textFieldStyle(.plain)
                            .font(DS.Text.caption)
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 6).fill(.quaternary)
                            )

                        Button {
                            let trimmed = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty else { return }
                            HermesConfig.shared.writeRawEnv(key: envName, value: trimmed)
                            apiKeyDraft = ""
                            showingApiKeyForm = false
                            localError = nil
                            onStateRefresh()
                        } label: {
                            Text("Enregistrer")
                                .font(DS.Text.caption.weight(.semibold))
                                .foregroundStyle(apiKeyDraft.isEmpty
                                                 ? AnyShapeStyle(.tertiary)
                                                 : AnyShapeStyle(Color.black.opacity(0.85)))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(apiKeyDraft.isEmpty
                                              ? AnyShapeStyle(Color.clear)
                                              : AnyShapeStyle(AppColors.accent))
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(apiKeyDraft.isEmpty)
                        .pointingHandCursor()
                    }

                    Button("Annuler") {
                        apiKeyDraft = ""
                        showingApiKeyForm = false
                    }
                    .buttonStyle(.plain)
                    .font(DS.Text.caption)
                    .foregroundStyle(.tertiary)
                    .pointingHandCursor()
                    .padding(.top, 4)
                }
            }
        }
    }

    private func externalLinkButton(url: URL) -> some View {
        Button {
            NSWorkspace.shared.open(url)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.right.square").font(DS.Icon.chevron)
                Text("Voir le guide de configuration")
                    .font(DS.Text.caption.weight(.semibold))
            }
            .foregroundStyle(Color.black.opacity(0.85))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(AppColors.accent)
            )
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }

    private func disconnectButton(label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "xmark.circle").font(DS.Icon.chevron)
                Text(label)
                    .font(DS.Text.caption.weight(.medium))
            }
            .foregroundStyle(Color.red.opacity(0.75))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.red.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }
}

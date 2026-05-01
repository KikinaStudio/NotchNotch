import SwiftUI

enum BrainTab: String, CaseIterable {
    case brain = "Memory"
    case tools = "Tools"
    case tasks = "Tasks"
}

struct BrainView: View {
    @ObservedObject var brainVM: BrainViewModel
    @ObservedObject var chatVM: ChatViewModel
    @ObservedObject var notchVM: NotchViewModel
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
    @State private var selectedSkill: SkillInfo?
    @State private var selectedCuratedSkill: CuratedSkill?
    @State private var selectedMemoryBlock: MemoryBlock?
    @State private var hoveredMemoryId: String?
    @State private var hoveredSkillId: String?
    @State private var hoveredCuratedId: String?
    @State private var syncPulseScale: CGFloat = 1.0

    private let cardWidth: CGFloat = 220

    private let lightMetricsTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            // Content (tabs now live in NotchView's top bar)
            ZStack {
                contentForTab
                    .opacity((selectedSkill == nil && selectedMemoryBlock == nil && selectedCuratedSkill == nil) ? 1 : 0)

                if let skill = selectedSkill {
                    detailView(title: skill.name, content: skill.content) {
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
        .onAppear {
            brainVM.refreshLightMetrics()
            googleConnection.refresh()
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

    // MARK: - Tools tab (Apps carousel + technical skills carousels)

    private var toolsTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            tabIntro("Ce que ton agent peut faire pour toi.")

            FadingScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    appsCarouselSection

                    ForEach(technicalSkillCategories, id: \.name) { group in
                        skillCategorySection(group)
                    }
                }
                .padding(.bottom, 8)
            }
        }
    }

    private var appsCarouselSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "square.grid.2x2.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.tertiary)
                Text("Apps")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)
                Text("\(CuratedSkillCatalog.all.count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 8) {
                    ForEach(CuratedSkillCatalog.all) { curated in
                        curatedSkillCard(curated)
                            .frame(width: cardWidth, height: 130)
                    }
                }
            }
            .scrollClipDisabled()
        }
    }

    private func curatedSkillCard(_ skill: CuratedSkill) -> some View {
        let state = brainVM.curatedSkillStates[skill.id] ?? .available
        let cardShape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                selectedCuratedSkill = skill
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    BrandIconView(kind: skill.icon, size: 24)
                    Spacer()
                    stateIndicator(for: state)
                }

                Text(skill.displayName)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if !skill.descriptionFR.isEmpty {
                    Text(skill.descriptionFR)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardShape.fill(.quaternary.opacity(0.6)))
            .overlay(
                cardShape
                    .fill(hoveredCuratedId == skill.id ? AnyShapeStyle(DS.Stroke.hairline) : AnyShapeStyle(Color.clear))
                    .allowsHitTesting(false)
            )
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .onHover { over in hoveredCuratedId = over ? skill.id : nil }
        .animation(.easeInOut(duration: 0.15), value: hoveredCuratedId == skill.id)
    }

    @ViewBuilder
    private func stateIndicator(for state: CuratedSkillState) -> some View {
        switch state {
        case .connected:
            Circle()
                .fill(Color.green.opacity(0.85))
                .frame(width: 7, height: 7)
        case .available:
            Image(systemName: "chevron.right")
                .font(DS.Icon.chevron)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Tasks tab (RoutinesView embedded)

    private var tasksTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Intro is rendered inside RoutinesView's own header so it can sit
            // on the same row as the [+ New] button (saves vertical space).
            tasksContent()
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

    private struct SkillCategoryGroup {
        let name: String
        let skills: [SkillInfo]
    }

    private var technicalSkillCategories: [SkillCategoryGroup] {
        let grouped = Dictionary(grouping: brainVM.technicalSkills, by: \.category)
        return grouped
            .map { SkillCategoryGroup(name: $0.key, skills: $0.value) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func skillCategorySection(_ group: SkillCategoryGroup) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: iconForSkillCategory(group.name))
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.tertiary)
                Text(labelForSkillCategory(group.name))
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)
                Text("\(group.skills.count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 8) {
                    ForEach(group.skills) { skill in
                        skillCardCompact(skill)
                            .frame(width: cardWidth, height: 130)
                    }
                }
            }
            .scrollClipDisabled()
        }
    }

    private func skillCardCompact(_ skill: SkillInfo) -> some View {
        let cardShape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return VStack(alignment: .leading, spacing: 6) {
            Text(skill.name)
                .font(.callout.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)

            if !skill.description.isEmpty {
                Text(skill.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardShape.fill(.quaternary.opacity(0.6)))
        .overlay(
            cardShape
                .fill(hoveredSkillId == skill.id ? AnyShapeStyle(DS.Stroke.hairline) : AnyShapeStyle(Color.clear))
                .allowsHitTesting(false)
        )
        .contentShape(Rectangle())
        .onHover { over in hoveredSkillId = over ? skill.id : nil }
        .onTapGesture {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                selectedSkill = skill
            }
        }
        .pointingHandCursor()
        .animation(.easeInOut(duration: 0.15), value: hoveredSkillId == skill.id)
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

    private func detailView(title: String, content: String, onBack: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onBack) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.caption.weight(.semibold))
                    Text(title)
                        .font(.footnote.weight(.medium))
                        .lineLimit(1)
                }
                .foregroundStyle(AppColors.accent)
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            .padding(.bottom, 10)

            FadingScrollView {
                markdownText(content)
            }
        }
    }

    // MARK: - Shared components

    private func markdownText(_ text: String) -> some View {
        let rendered = (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
        return Text(rendered)
            .font(.callout)
            .foregroundStyle(.primary)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

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

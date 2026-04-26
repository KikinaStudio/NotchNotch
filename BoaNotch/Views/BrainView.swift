import SwiftUI

enum BrainTab: String, CaseIterable {
    case memory = "Memory"
    case skills = "Skills"
    case wiki = "Wiki"
}

struct BrainView: View {
    @ObservedObject var brainVM: BrainViewModel
    @ObservedObject var chatVM: ChatViewModel
    @ObservedObject var notchVM: NotchViewModel
    var onSendToChat: ((String) -> Void)?
    @State private var selectedSkill: SkillInfo?
    @State private var selectedMemoryBlock: MemoryBlock?
    @State private var hoveredMemoryId: String?
    @State private var hoveredSkillId: String?
    @State private var syncPulseScale: CGFloat = 1.0

    private let cardWidth: CGFloat = 220

    private let lightMetricsTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            // Content (tabs now live in NotchView's top bar)
            ZStack {
                contentForTab
                    .opacity((selectedSkill == nil && selectedMemoryBlock == nil) ? 1 : 0)

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

                if let block = selectedMemoryBlock {
                    memoryBlockDetail(block: block)
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing),
                            removal: .move(edge: .trailing)
                        ))
                }
            }
        }
        .onAppear { brainVM.refreshLightMetrics() }
        .onReceive(lightMetricsTimer) { _ in brainVM.refreshLightMetrics() }
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
        case .memory: memoryTab
        case .skills: skillsTab
        case .wiki: wikiTab
        }
    }

    // MARK: - Memory tab (flat full-width cards)

    private var memoryTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            tabIntro("Ce qu'Hermes retient de toi.")

            if brainVM.allMemoryBlocks.isEmpty {
                emptyState("Hermes hasn't learned anything yet.\nStart chatting and it will remember what matters.")
            } else {
                FadingScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(brainVM.allMemoryBlocks) { block in
                            memoryCardCompact(block)
                        }
                    }
                    .padding(.bottom, 8)
                }
            }
        }
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

    // MARK: - Skills tab (Netflix-style)

    private var skillsTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            tabIntro("Les savoir-faire qu'Hermes peut mobiliser. Chacun lui apprend à faire quelque chose de précis.")

            if brainVM.skills.isEmpty {
                emptyState("No skills installed yet.")
            } else {
                FadingScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(skillCategories, id: \.name) { group in
                            skillCategorySection(group)
                        }

                        Text("Type /skill-name in chat to use a skill")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 6)
                    }
                    .padding(.bottom, 8)
                }
            }
        }
    }

    private struct SkillCategoryGroup {
        let name: String
        let skills: [SkillInfo]
    }

    private var skillCategories: [SkillCategoryGroup] {
        let grouped = Dictionary(grouping: brainVM.skills, by: \.category)
        return grouped
            .map { SkillCategoryGroup(name: $0.key, skills: $0.value) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func skillCategorySection(_ group: SkillCategoryGroup) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(group.name.capitalized)
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
                            .frame(width: cardWidth)
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

    // MARK: - Wiki tab (dashboard + ask)

    private var wikiTab: some View {
        Group {
            if brainVM.wikiArticles.isEmpty {
                wikiEmptyState
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    tabIntro("Ta base de connaissances personnelle. Hermes la compile à partir de ce que tu lui partages.")

                    // Dashboard header
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(topicsCopy(brainVM.wikiArticles.count))
                            if let lastUpdate = brainVM.wikiLastUpdated {
                                Text("· Dernière intégration il y a \(shortFrenchRelative(from: lastUpdate))")
                            }
                            syncButton
                        }
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 8)

                    // Article list
                    FadingScrollView {
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
        }
    }

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

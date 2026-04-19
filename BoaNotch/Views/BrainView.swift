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
    @State private var activeTab: BrainTab = .memory
    @State private var selectedSkill: SkillInfo?
    @State private var selectedMemoryCategory: String?
    @State private var syncPulseScale: CGFloat = 1.0

    private let lightMetricsTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            HStack(spacing: 16) {
                tabButton(.memory)
                tabButton(.skills)
                if brainVM.hasWiki {
                    tabButton(.wiki)
                }
                Spacer()
                Button { brainVM.reload() } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
            }
            .padding(.bottom, 12)

            // Content
            ZStack {
                contentForTab
                    .opacity((selectedSkill == nil && selectedMemoryCategory == nil) ? 1 : 0)

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

                if let category = selectedMemoryCategory,
                   let group = brainVM.memoryCategories.first(where: { $0.name == category }) {
                    memoryCategoryDetail(group: group)
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing),
                            removal: .move(edge: .trailing)
                        ))
                }
            }
        }
        .onAppear { brainVM.refreshLightMetrics() }
        .onReceive(lightMetricsTimer) { _ in brainVM.refreshLightMetrics() }
        .onChange(of: brainVM.allMemoryBlocks.map(\.id)) { _, _ in
            if let sel = selectedMemoryCategory,
               !brainVM.memoryCategories.contains(where: { $0.name == sel }) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    selectedMemoryCategory = nil
                }
            }
        }
    }

    // MARK: - Tab button

    private func tabButton(_ tab: BrainTab) -> some View {
        Button {
            activeTab = tab
            selectedSkill = nil
            selectedMemoryCategory = nil
        } label: {
            Text(tab.rawValue)
                .font(.callout.weight(activeTab == tab ? .semibold : .medium))
                .foregroundStyle(activeTab == tab ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }

    // MARK: - Tab content

    @ViewBuilder
    private var contentForTab: some View {
        switch activeTab {
        case .memory: memoryTab
        case .skills: skillsTab
        case .wiki: wikiTab
        }
    }

    // MARK: - Memory tab

    private var memoryTab: some View {
        Group {
            if brainVM.allMemoryBlocks.isEmpty {
                emptyState("Hermes hasn't learned anything yet.\nStart chatting and it will remember what matters.")
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        tabIntro("Ce qu'Hermes retient de toi, rangé par sujet.")

                        Text(categoryCountCaption(brainVM.memoryCategories.count))
                            .font(.caption2.weight(.bold).monospaced())
                            .foregroundStyle(.tertiary)
                            .tracking(1.5)
                            .padding(.bottom, 6)

                        LazyVStack(spacing: 0) {
                            ForEach(Array(brainVM.memoryCategories.enumerated()), id: \.element.id) { index, group in
                                if index > 0 { blockDivider }
                                categoryRow(group)
                            }
                        }
                    }
                }
            }
        }
    }

    private func categoryRow(_ group: MemoryCategoryGroup) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                selectedMemoryCategory = group.name
            }
        } label: {
            HStack(spacing: 10) {
                Text(group.name)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer()

                Text("\(group.count)")
                    .font(.caption2.weight(.medium).monospaced())
                    .foregroundStyle(.tertiary)

                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }

    private func memoryCategoryDetail(group: MemoryCategoryGroup) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    selectedMemoryCategory = nil
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.caption.weight(.semibold))
                    Text(group.name)
                        .font(.footnote.weight(.medium))
                        .lineLimit(1)
                }
                .foregroundStyle(AppColors.accent)
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            .padding(.bottom, 10)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(group.blocks.enumerated()), id: \.element.id) { index, block in
                        if index > 0 { blockDivider }
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
        }
    }

    private func categoryCountCaption(_ count: Int) -> String {
        count == 1 ? "1 CATÉGORIE" : "\(count) CATÉGORIES"
    }

    private func tabIntro(_ text: String) -> some View {
        Text(text)
            .font(.footnote.italic())
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, 12)
    }

    private var blockDivider: some View {
        Divider().padding(.leading, 14)
    }

    // MARK: - Skills tab

    private var skillsTab: some View {
        Group {
            if brainVM.skills.isEmpty {
                emptyState("No skills installed yet.")
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        tabIntro("Les savoir-faire qu'Hermes peut mobiliser. Chacun lui apprend à faire quelque chose de précis.")

                        Text("\(brainVM.skills.count) SKILLS AVAILABLE")
                            .font(.caption2.weight(.bold).monospaced())
                            .foregroundStyle(.tertiary)
                            .tracking(1.5)
                            .padding(.bottom, 6)

                        LazyVStack(spacing: 0) {
                            ForEach(Array(brainVM.skills.enumerated()), id: \.element.id) { index, skill in
                                if index > 0 { blockDivider }
                                skillRow(skill)
                            }
                        }

                        Text("Type /skill-name in chat to use a skill")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 14)
                    }
                }
            }
        }
    }

    private func skillRow(_ skill: SkillInfo) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                selectedSkill = skill
            }
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(skill.category.uppercased())
                            .font(.caption2.weight(.bold).monospaced())
                            .foregroundStyle(AppColors.accent.opacity(0.6))
                            .tracking(1.2)
                        Text(skill.name)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.primary)
                    }
                    if !skill.description.isEmpty {
                        Text(skill.description)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
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
                    ScrollView(.vertical, showsIndicators: false) {
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

            ScrollView(.vertical, showsIndicators: false) {
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
                    .font(.system(size: 13, weight: .regular, design: .serif))
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
                .font(.system(size: 11 * appearanceSettings.textSize.scale))
                .scrollContentBackground(.hidden)
                .background(Color.white.opacity(0.05))
                .foregroundStyle(.primary)
                .frame(minHeight: 80, maxHeight: 220)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
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

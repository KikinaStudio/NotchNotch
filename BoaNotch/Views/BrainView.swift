import SwiftUI

enum BrainTab: String, CaseIterable {
    case memory = "Memory"
    case skills = "Skills"
    case wiki = "Wiki"
}

struct BrainView: View {
    @ObservedObject var brainVM: BrainViewModel
    var onSendToChat: ((String) -> Void)?
    @State private var activeTab: BrainTab = .memory
    @State private var selectedSkill: SkillInfo?
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
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.35))
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
            }
            .padding(.bottom, 12)

            // Content
            ZStack {
                contentForTab
                    .opacity(selectedSkill == nil ? 1 : 0)

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
            }
        }
        .onAppear { brainVM.refreshLightMetrics() }
        .onReceive(lightMetricsTimer) { _ in brainVM.refreshLightMetrics() }
    }

    // MARK: - Tab button

    private func tabButton(_ tab: BrainTab) -> some View {
        Button {
            activeTab = tab
            selectedSkill = nil
        } label: {
            Text(tab.rawValue)
                .font(.system(size: 12, weight: activeTab == tab ? .semibold : .medium))
                .foregroundStyle(activeTab == tab ? .white : .white.opacity(0.32))
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
            if brainVM.userBlocks.isEmpty && brainVM.memoryBlocks.isEmpty {
                emptyState("Hermes hasn't learned anything yet.\nStart chatting and it will remember what matters.")
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        tabIntro("Ce qu'Hermes retient de toi et de tes conversations.")

                        if !brainVM.userBlocks.isEmpty {
                            memorySectionHeader("ABOUT YOU")
                            ForEach(Array(brainVM.userBlocks.enumerated()), id: \.element.id) { index, block in
                                if index > 0 { blockDivider }
                                MemoryCard(block: block)
                            }
                        }

                        if !brainVM.memoryBlocks.isEmpty {
                            memorySectionHeader("LEARNED FACTS")
                                .padding(.top, !brainVM.userBlocks.isEmpty ? 14 : 0)
                            ForEach(Array(brainVM.memoryBlocks.enumerated()), id: \.element.id) { index, block in
                                if index > 0 { blockDivider }
                                MemoryCard(block: block)
                            }
                        }
                    }
                }
            }
        }
    }

    private func tabIntro(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5))
            .italic()
            .foregroundStyle(.white.opacity(0.45))
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, 12)
    }

    private func memorySectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(.white.opacity(0.28))
            .tracking(1.5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 6)
    }

    private var blockDivider: some View {
        Rectangle()
            .fill(.white.opacity(0.06))
            .frame(height: 1)
            .padding(.leading, 14)
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
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.28))
                            .tracking(1.5)
                            .padding(.bottom, 6)

                        LazyVStack(spacing: 0) {
                            ForEach(Array(brainVM.skills.enumerated()), id: \.element.id) { index, skill in
                                if index > 0 { blockDivider }
                                skillRow(skill)
                            }
                        }

                        Text("Type /skill-name in chat to use a skill")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.25))
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
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundStyle(AppColors.accent.opacity(0.55))
                            .tracking(1.2)
                        Text(skill.name)
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.92))
                    }
                    if !skill.description.isEmpty {
                        Text(skill.description)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.white.opacity(0.5))
                            .lineLimit(1)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.2))
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
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.3))
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
                                                .font(.system(size: 8))
                                                .foregroundStyle(AppColors.accent.opacity(0.5))
                                        }
                                        Text(article.title)
                                            .font(.system(size: 11))
                                            .foregroundStyle(.white.opacity(0.7))
                                            .lineLimit(1)
                                        Spacer()
                                        Text("Ask")
                                            .font(.system(size: 9, weight: .medium))
                                            .foregroundStyle(AppColors.accent.opacity(0.5))
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
        .font(.system(size: 12))
        .foregroundStyle(.white.opacity(0.3))
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
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(brainVM.pendingRawCount > 0 ? 1.0 : 0.3))
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
                        .font(.system(size: 10, weight: .semibold))
                    Text(title)
                        .font(.system(size: 11, weight: .medium))
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
            .font(.system(size: 12))
            .foregroundStyle(.white.opacity(0.82))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func emptyState(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 12))
            .foregroundStyle(.white.opacity(0.3))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Memory card

struct MemoryCard: View {
    let block: MemoryBlock

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("§")
                    .font(.system(size: 12, weight: .regular, design: .serif))
                    .foregroundStyle(AppColors.accent.opacity(0.55))
                Text(titleAttributed)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
            }

            Text(markdownContent)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.55))
                .textSelection(.enabled)
                .padding(.leading, 14)
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
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

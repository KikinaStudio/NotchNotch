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

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            HStack(spacing: 8) {
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
            .padding(.bottom, 10)

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
    }

    // MARK: - Tab button

    private func tabButton(_ tab: BrainTab) -> some View {
        Button {
            activeTab = tab
            selectedSkill = nil
        } label: {
            Text(tab.rawValue)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(activeTab == tab ? .white : .white.opacity(0.5))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(activeTab == tab ? AppColors.accent.opacity(0.3) : .white.opacity(0.06))
                .clipShape(Capsule())
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
                    VStack(alignment: .leading, spacing: 8) {
                        if !brainVM.userBlocks.isEmpty {
                            memorySectionHeader("ABOUT YOU")
                            ForEach(brainVM.userBlocks) { block in
                                MemoryCard(block: block)
                            }
                        }

                        if !brainVM.memoryBlocks.isEmpty {
                            memorySectionHeader("LEARNED FACTS")
                                .padding(.top, !brainVM.userBlocks.isEmpty ? 8 : 0)
                            ForEach(brainVM.memoryBlocks) { block in
                                MemoryCard(block: block)
                            }
                        }
                    }
                }
            }
        }
    }

    private func memorySectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(AppColors.accent.opacity(0.5))
            .tracking(1.2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Skills tab

    private var skillsTab: some View {
        Group {
            if brainVM.skills.isEmpty {
                emptyState("No skills installed yet.")
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(brainVM.skills.count) skills available")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.25))
                            .tracking(1.5)
                            .padding(.bottom, 8)

                        LazyVStack(spacing: 4) {
                            ForEach(brainVM.skills) { skill in
                                skillRow(skill)
                            }
                        }

                        Text("Type /skill-name in chat to use a skill")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.25))
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 12)
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
            HStack(spacing: 8) {
                Text(skill.category)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.white.opacity(0.08))
                    .clipShape(Capsule())

                VStack(alignment: .leading, spacing: 2) {
                    Text(skill.name)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.82))
                    if !skill.description.isEmpty {
                        Text(skill.description)
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.4))
                            .lineLimit(1)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.15))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }

    // MARK: - Wiki tab (dashboard + ask)

    private var wikiTab: some View {
        Group {
            if brainVM.wikiArticles.isEmpty {
                emptyState("No wiki articles found.")
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    // Dashboard header
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Brain Wiki")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.7))

                        HStack(spacing: 4) {
                            Text("\(brainVM.wikiArticles.count) articles")
                            if let lastUpdate = brainVM.wikiLastUpdated {
                                Text("—")
                                Text(lastUpdate, style: .relative)
                                Text("ago")
                            }
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
        VStack(alignment: .leading, spacing: 4) {
            Text(block.title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppColors.accent.opacity(0.7))

            Text(markdownContent)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.6))
                .textSelection(.enabled)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var markdownContent: AttributedString {
        (try? AttributedString(
            markdown: block.content,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(block.content)
    }
}

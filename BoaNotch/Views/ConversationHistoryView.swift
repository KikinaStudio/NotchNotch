import SwiftUI

struct ConversationHistoryView: View {
    @ObservedObject var chatVM: ChatViewModel
    @ObservedObject var sessionStore: SessionStore
    @ObservedObject var notchVM: NotchViewModel
    @ObservedObject var titleStore: TitleStore

    @State private var query: String = ""

    private let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    /// Sessions filtered by the current search query (matches resolved title
    /// or first user message, case-insensitive).
    private var filteredSessions: [SessionSummary] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return sessionStore.recentSessions }
        return sessionStore.recentSessions.filter { session in
            if displayTitle(for: session).lowercased().contains(q) { return true }
            if let msg = session.firstUserMessage?.lowercased(), msg.contains(q) { return true }
            return false
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header (title shown in top bar; this row keeps search + new)
            HStack(spacing: 12) {
                searchField

                Button {
                    chatVM.startNewConversation()
                    notchVM.isHistoryOpen = false
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.footnote.weight(.semibold))
                        Text("New")
                            .font(.callout.weight(.medium))
                    }
                    .foregroundStyle(AppColors.accent)
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
            }
            .padding(.bottom, 12)

            if sessionStore.recentSessions.isEmpty {
                Spacer()
                Text("No conversations yet")
                    .font(.body)
                    .foregroundStyle(.tertiary)
                Spacer()
            } else if filteredSessions.isEmpty {
                Spacer()
                Text("No matches")
                    .font(.body)
                    .foregroundStyle(.tertiary)
                Spacer()
            } else {
                FadingScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(filteredSessions) { session in
                            sessionRow(session)
                        }
                    }
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.footnote)
                .foregroundStyle(.tertiary)
            TextField("Search conversations", text: $query)
                .textFieldStyle(.plain)
                .font(.callout)
                .foregroundStyle(.primary)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.quaternary.opacity(0.6))
        )
        .frame(maxWidth: .infinity)
    }

    private func sessionRow(_ session: SessionSummary) -> some View {
        let isActive = chatVM.sessionId == session.id

        return Button {
            loadSession(session)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: session.sourceIcon)
                    .font(.footnote)
                    .foregroundStyle(iconColor(for: session.source))
                    .frame(width: 16)

                Text(displayTitle(for: session))
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer()

                if let date = session.startedAt {
                    Text(relativeFormatter.localizedString(for: date, relativeTo: Date()))
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isActive ? AnyShapeStyle(AppColors.accent.opacity(0.18)) : AnyShapeStyle(Color.clear))
            )
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }

    private func iconColor(for source: String) -> Color {
        switch source {
        case "cli": return .orange
        case "telegram": return .blue
        case "discord": return .purple
        case "api_server": return AppColors.accent
        default: return .secondary.opacity(0.6)
        }
    }

    /// Title fallback chain: cached LLM title → DB title → first user message
    /// preview → "Untitled".
    private func displayTitle(for session: SessionSummary) -> String {
        if let cached = titleStore.title(for: session.id), !cached.isEmpty {
            return cached
        }
        if let stored = session.title, !stored.isEmpty {
            return stored
        }
        if let preview = session.messagePreview() {
            return preview
        }
        return "Untitled"
    }

    private func loadSession(_ session: SessionSummary) {
        let msgs = sessionStore.messagesForSession(sessionId: session.id)
        chatVM.messages = msgs.compactMap { msg in
            guard let role = ChatMessage.Role(rawValue: msg.role) else { return nil }
            return ChatMessage(role: role, content: msg.content)
        }
        chatVM.sessionId = session.id
        notchVM.isHistoryOpen = false
    }
}

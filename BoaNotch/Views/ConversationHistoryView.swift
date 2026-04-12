import SwiftUI

struct ConversationHistoryView: View {
    @ObservedObject var chatVM: ChatViewModel
    @ObservedObject var sessionStore: SessionStore
    @ObservedObject var notchVM: NotchViewModel

    private let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Conversations")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
                Spacer()
                Button {
                    chatVM.startNewConversation()
                    notchVM.isHistoryOpen = false
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .semibold))
                        Text("New")
                            .font(.system(size: 12, weight: .medium))
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
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.3))
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(sessionStore.recentSessions) { session in
                            sessionRow(session)
                        }
                    }
                }
            }
        }
    }

    private func sessionRow(_ session: SessionSummary) -> some View {
        let isActive = chatVM.sessionId == session.id

        return Button {
            loadSession(session)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: session.sourceIcon)
                    .font(.system(size: 11))
                    .foregroundStyle(iconColor(for: session.source))
                    .frame(width: 16)

                Text(session.displayTitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)

                Spacer()

                if let date = session.updatedAt {
                    Text(relativeFormatter.localizedString(for: date, relativeTo: Date()))
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.3))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(isActive ? AppColors.accent.opacity(0.15) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }

    private func iconColor(for source: String) -> Color {
        switch source {
        case "cli": return .orange
        case "telegram": return .blue
        case "discord": return .purple
        default: return .white.opacity(0.4)
        }
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

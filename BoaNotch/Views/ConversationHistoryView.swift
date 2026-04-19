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
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
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
                    .font(.footnote)
                    .foregroundStyle(iconColor(for: session.source))
                    .frame(width: 16)

                Text(session.displayTitle)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer()

                if let date = session.updatedAt {
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
        default: return .secondary.opacity(0.6)
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

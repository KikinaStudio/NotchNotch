import SwiftUI

struct ChatView: View {
    @ObservedObject var chatVM: ChatViewModel
    @ObservedObject var notchVM: NotchViewModel
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(chatVM.messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                }
                .scrollIndicators(.hidden)
                .onChange(of: chatVM.messages.count) {
                    if let lastId = chatVM.messages.last?.id {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(lastId, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: chatVM.messages.last?.content) {
                    if let lastId = chatVM.messages.last?.id {
                        proxy.scrollTo(lastId, anchor: .bottom)
                    }
                }
            }

            // Attachment chips
            if !chatVM.pendingAttachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(chatVM.pendingAttachments) { attachment in
                            AttachmentChip(attachment: attachment) {
                                chatVM.removeAttachment(attachment.id)
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }
            }

            // Error banner
            if let error = chatVM.connectionError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                    Text(error)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.7))
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }

            // Input bar
            HStack(spacing: 8) {
                TextField("Message Hermes...", text: $chatVM.draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(.white)
                    .lineLimit(1...4)
                    .focused($isInputFocused)
                    .onSubmit {
                        chatVM.send()
                    }

                if chatVM.isStreaming {
                    Button {
                        chatVM.cancelStream()
                    } label: {
                        Image(systemName: "stop.circle.fill")
                            .foregroundStyle(.red)
                            .font(.system(size: 18))
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        chatVM.send()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .foregroundStyle(
                                chatVM.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    && chatVM.pendingAttachments.isEmpty
                                ? .white.opacity(0.3) : .white
                            )
                            .font(.system(size: 18))
                    }
                    .buttonStyle(.plain)
                    .disabled(
                        chatVM.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        && chatVM.pendingAttachments.isEmpty
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 4)
            .padding(.bottom, 4)
        }
        .onAppear {
            isInputFocused = true
        }
    }
}

struct AttachmentChip: View {
    let attachment: Attachment
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: iconForFileType(attachment.fileType))
                .font(.system(size: 10))
            Text(attachment.fileName)
                .font(.system(size: 10))
                .lineLimit(1)
            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 10))
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(.white.opacity(0.8))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.white.opacity(0.12))
        .clipShape(Capsule())
    }

    private func iconForFileType(_ type: String) -> String {
        switch type {
        case "pdf": return "doc.fill"
        case "txt", "md": return "doc.text.fill"
        case "swift", "py", "js", "ts", "rs", "go": return "chevron.left.forwardslash.chevron.right"
        case "json", "yaml", "yml", "toml", "xml": return "curlybraces"
        case "csv": return "tablecells"
        default: return "paperclip"
        }
    }
}

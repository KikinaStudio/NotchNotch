import Foundation
import Combine

class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var draft: String = ""
    @Published var pendingAttachments: [Attachment] = []
    @Published var isStreaming = false
    @Published var connectionError: String?

    private let client = HermesClient()
    private var streamTask: Task<Void, Never>?

    weak var notchVM: NotchViewModel?

    func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !pendingAttachments.isEmpty else { return }

        // Build user message content with attachments
        var fullContent = ""
        for attachment in pendingAttachments {
            fullContent += "[Attached: \(attachment.fileName)]\n"
            fullContent += attachment.textContent
            fullContent += "\n[End attachment]\n\n"
        }
        fullContent += text

        let userMessage = ChatMessage(role: .user, content: fullContent, attachments: pendingAttachments)
        messages.append(userMessage)

        draft = ""
        pendingAttachments = []
        connectionError = nil

        // Create placeholder assistant message
        let assistantMessage = ChatMessage(role: .assistant, content: "", isStreaming: true)
        messages.append(assistantMessage)
        isStreaming = true

        let apiMessages = messages.map { msg -> [String: String] in
            return ["role": msg.role.rawValue, "content": msg.content]
        }

        streamTask = Task { @MainActor in
            do {
                let stream = client.streamCompletion(messages: apiMessages)
                for try await token in stream {
                    guard !Task.isCancelled else { break }
                    if let lastIndex = messages.indices.last {
                        messages[lastIndex].content += token
                    }
                }
                // Stream completed
                if let lastIndex = messages.indices.last {
                    messages[lastIndex].isStreaming = false
                }
                isStreaming = false

                // Show toast if notch is closed
                if let notchVM, notchVM.isClosed,
                   let lastMsg = messages.last, lastMsg.role == .assistant {
                    notchVM.showToast(lastMsg.content)
                }
            } catch {
                if !Task.isCancelled {
                    connectionError = error.localizedDescription
                    if let lastIndex = messages.indices.last {
                        messages[lastIndex].isStreaming = false
                        messages[lastIndex].content = "Error: \(error.localizedDescription)"
                    }
                    isStreaming = false
                }
            }
        }
    }

    func cancelStream() {
        streamTask?.cancel()
        streamTask = nil
        if let lastIndex = messages.indices.last, messages[lastIndex].isStreaming {
            messages[lastIndex].isStreaming = false
        }
        isStreaming = false
    }

    func removeAttachment(_ id: UUID) {
        pendingAttachments.removeAll { $0.id == id }
    }
}

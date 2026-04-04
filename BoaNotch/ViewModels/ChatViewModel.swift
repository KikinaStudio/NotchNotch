import Foundation
import Combine

enum VoiceState {
    case idle
    case recording
    case transcribing
}

class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var draft: String = ""
    @Published var pendingAttachments: [Attachment] = []
    @Published var isStreaming = false
    @Published var connectionError: String?
    @Published var voiceState: VoiceState = .idle
    @Published var showNewConversationConfirm = false

    private let client = HermesClient()
    var audioRecorder: AudioRecorder?

    var sessionId: String? {
        get { client.sessionId }
        set { client.sessionId = newValue }
    }
    private var streamTask: Task<Void, Never>?
    private var streamingCancellable: AnyCancellable?

    weak var notchVM: NotchViewModel? {
        didSet { bindStreaming() }
    }

    private func bindStreaming() {
        streamingCancellable = $isStreaming.sink { [weak self] streaming in
            self?.notchVM?.isStreaming = streaming
        }
    }

    init() {
        Task { @MainActor in
            let ok = await client.healthCheck()
            if !ok {
                connectionError = "Hermes offline"
            }
        }
    }

    func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !pendingAttachments.isEmpty else { return }

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

        // Build API messages BEFORE adding the placeholder
        let apiMessages = messages
            .filter { !$0.content.isEmpty }
            .map { ["role": $0.role.rawValue, "content": $0.content] }

        let assistantMessage = ChatMessage(role: .assistant, content: "", isStreaming: true)
        messages.append(assistantMessage)
        isStreaming = true

        streamTask = Task { @MainActor in
            do {
                let stream = client.streamCompletion(messages: apiMessages)
                var gotFirstToken = false
                var thinkingStarted: Date?

                for try await event in stream {
                    guard !Task.isCancelled else { break }
                    if !gotFirstToken {
                        gotFirstToken = true
                        connectionError = nil
                    }
                    guard let lastIndex = messages.indices.last else { continue }

                    switch event {
                    case .thinking(let text):
                        if thinkingStarted == nil { thinkingStarted = Date() }
                        messages[lastIndex].thinkingContent += text
                    case .toolCall(let text):
                        messages[lastIndex].toolCallContent += text
                    case .delta(let text):
                        if let start = thinkingStarted {
                            messages[lastIndex].thinkingDuration = Date().timeIntervalSince(start)
                            thinkingStarted = nil
                        }
                        messages[lastIndex].content += text
                    case .done:
                        break
                    }
                }
                if let lastIndex = messages.indices.last {
                    if let start = thinkingStarted {
                        messages[lastIndex].thinkingDuration = Date().timeIntervalSince(start)
                    }
                    messages[lastIndex].isStreaming = false
                    extractCleanResponse(at: lastIndex)
                }
                isStreaming = false
                connectionError = nil

                if let notchVM, notchVM.isClosed,
                   let lastMsg = messages.last, lastMsg.role == .assistant {
                    notchVM.showToast(lastMsg.content)
                }
            } catch {
                if !Task.isCancelled {
                    let desc = error.localizedDescription
                    if desc.contains("Could not connect") || desc.contains("Connection refused") {
                        connectionError = "Hermes offline"
                    } else if desc.contains("timed out") || desc.contains("Timeout") {
                        connectionError = "Timeout"
                    } else {
                        connectionError = desc
                    }
                    if let lastIndex = messages.indices.last {
                        messages[lastIndex].isStreaming = false
                        if messages[lastIndex].content.isEmpty {
                            messages.removeLast()
                        }
                    }
                    isStreaming = false
                }
            }
        }
    }

    func confirmNewConversation() {
        showNewConversationConfirm = false
        cancelStream()
        messages.removeAll()
        draft = "/new"
        send()
    }

    func cancelStream() {
        streamTask?.cancel()
        streamTask = nil
        if let lastIndex = messages.indices.last, messages[lastIndex].isStreaming {
            messages[lastIndex].isStreaming = false
        }
        isStreaming = false
    }

    // MARK: - Post-processing: extract clean response from tool content

    private func extractCleanResponse(at index: Int) {
        let content = messages[index].content.trimmingCharacters(in: .whitespacesAndNewlines)
        let toolContent = messages[index].toolCallContent
        guard content.isEmpty, !toolContent.isEmpty else { return }

        // Split into paragraphs and find where clean response starts (from the end)
        let paragraphs = toolContent.components(separatedBy: "\n\n")
        var cleanStart = paragraphs.count

        for i in stride(from: paragraphs.count - 1, through: 0, by: -1) {
            let p = paragraphs[i].trimmingCharacters(in: .whitespacesAndNewlines)
            if p.isEmpty { continue }
            if looksLikeToolParagraph(p) { break }
            cleanStart = i
        }

        if cleanStart < paragraphs.count {
            messages[index].toolCallContent = paragraphs[0..<cleanStart].joined(separator: "\n\n")
            messages[index].content = paragraphs[cleanStart...].joined(separator: "\n\n")
        }
    }

    private func looksLikeToolParagraph(_ text: String) -> Bool {
        // Emoji markers
        let markers = ["💻", "🔧", "⚙️", "🔎", "🔍", "📚", "📋", "📧", "✍️", "📖"]
        for m in markers { if text.contains(m) { return true } }

        // Shell patterns
        if text.contains("2>/dev/null") || text.contains("2>&1") { return true }
        if text.contains(" && ") || text.contains(" || ") { return true }
        if text.contains("$GAPI") || text.contains("GAPI=") { return true }
        if text.contains(".hermes/") { return true }

        // Command invocations
        if text.hasPrefix("python ") || text.hasPrefix("bash ") || text.hasPrefix("curl ") { return true }

        // JSON output
        if text.hasPrefix("[{") || text.hasPrefix("{\"") || text.hasPrefix("[\"") { return true }

        // CLI flags
        if text.contains(" --output") || text.contains(" --page-size") || text.contains(" --max") { return true }

        return false
    }

    func removeAttachment(_ id: UUID) {
        pendingAttachments.removeAll { $0.id == id }
    }

    func toggleVoiceRecord() {
        switch voiceState {
        case .idle:
            audioRecorder?.startRecording()
            voiceState = .recording
        case .recording:
            guard let url = audioRecorder?.stopRecording() else {
                voiceState = .idle
                return
            }
            voiceState = .transcribing
            Task { @MainActor in
                if let text = await SpeechTranscriber.transcribe(audioURL: url) {
                    self.draft = text
                    self.send()
                } else {
                    let attachment = Attachment(
                        fileName: url.lastPathComponent,
                        fileType: "m4a",
                        textContent: "Audio file at: \(url.path)",
                        fileURL: url
                    )
                    self.pendingAttachments = [attachment]
                    self.draft = "[Voice memo — transcription failed]"
                    self.send()
                }
                self.voiceState = .idle
            }
        case .transcribing:
            break
        }
    }
}

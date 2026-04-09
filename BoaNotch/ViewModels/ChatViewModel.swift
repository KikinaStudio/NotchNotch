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

    func saveToBrain(content: String, fileName: String) {
        let truncated = String(content.prefix(DocumentExtractor.maxCharacters))
        let prompt = "Please save the following content to your memory. File: \(fileName)\n\n\(truncated)"
        let messages: [[String: String]] = [["role": "user", "content": prompt]]
        Task { @MainActor in
            do {
                try await client.sendCompletion(messages: messages)
                notchVM?.showToast("Saved to brain")
            } catch {
                print("[notchnotch] Save to brain error: \(error)")
                notchVM?.showToast("Brain save failed")
            }
        }
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

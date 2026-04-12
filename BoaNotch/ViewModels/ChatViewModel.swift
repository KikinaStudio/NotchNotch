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
    @Published var activeRoutineContext: CronJob? = nil
    @Published var routineCreationMode: Bool = false

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
                connectionError = "Can't reach Hermes on localhost:8642. Make sure the gateway is running (hermes gateway) and API_SERVER_ENABLED=true is set in ~/.hermes/.env"
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

        startRequest(input: fullContent)
    }

    func retryLastAssistant() {
        guard !isStreaming else { return }
        guard let lastAssistantIndex = messages.lastIndex(where: { $0.role == .assistant }) else { return }
        let userIndex = lastAssistantIndex - 1
        guard userIndex >= 0, messages[userIndex].role == .user else { return }

        let savedContent = messages[userIndex].content
        messages.removeSubrange(userIndex...lastAssistantIndex)

        let userMessage = ChatMessage(role: .user, content: savedContent)
        messages.append(userMessage)

        startRequest(input: savedContent)
    }

    private func startRequest(input: String) {
        let assistantMessage = ChatMessage(role: .assistant, content: "", isStreaming: true)
        messages.append(assistantMessage)
        isStreaming = true
        connectionError = nil

        streamTask = Task { @MainActor in
            let startTime = Date()
            do {
                var systemContext: String? = nil
                if let routine = activeRoutineContext {
                    let statusInfo = routine.enabled ? "active" : "paused"
                    let promptPreview = String(routine.prompt.prefix(200))
                    systemContext = "The user is referring to their scheduled routine \"\(routine.name)\" (id: \(routine.id), schedule: \"\(routine.schedule_display)\", status: \(statusInfo)). Current prompt: \"\(promptPreview)\". Interpret their message as instructions about this specific cron job. Use your cronjob tools to make any requested changes."
                } else if routineCreationMode {
                    systemContext = "The user dropped a file from the Routines screen. They want to create a new scheduled routine (cron job). Analyze the attached file and, based on its content and what you know about the user, suggest 1-2 routine ideas that would be useful. Explain each suggestion briefly. Ask the user to confirm or adjust before creating the cron job. Do not create any job until the user explicitly agrees."
                    routineCreationMode = false
                }
                let result = try await client.sendResponse(input: input, systemContext: systemContext)

                guard !Task.isCancelled else { return }
                guard let lastIndex = messages.indices.last else { return }

                messages[lastIndex].content = result.content
                messages[lastIndex].thinkingContent = result.thinkingContent
                messages[lastIndex].toolCallContent = result.toolCalls
                if !result.thinkingContent.isEmpty {
                    messages[lastIndex].thinkingDuration = Date().timeIntervalSince(startTime)
                }
                messages[lastIndex].isStreaming = false
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
                        connectionError = "Can't reach Hermes on localhost:8642. Make sure the gateway is running (hermes gateway) and API_SERVER_ENABLED=true is set in ~/.hermes/.env"
                    } else if desc.contains("timed out") || desc.contains("Timeout") {
                        connectionError = "Hermes took too long to respond. Try reducing max iterations in settings, or check if the agent is stuck (hermes logs)"
                    } else if let hermesError = error as? HermesError,
                              case .httpErrorWithBody(let code, _) = hermesError {
                        if code == 401 || code == 403 {
                            connectionError = "Authentication error. If you set API_SERVER_KEY in ~/.hermes/.env, notchnotch doesn't send it yet. Remove API_SERVER_KEY or leave it empty for local use."
                        } else if code >= 500 {
                            connectionError = "Hermes internal error. Check ~/.hermes/logs/err.log or run: hermes logs --tail 50"
                        } else {
                            connectionError = "Unexpected error: \(desc)"
                        }
                    } else {
                        connectionError = "Unexpected error: \(desc)"
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
        client.resetConversation()
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

    func setRoutineContext(_ job: CronJob) {
        activeRoutineContext = job
    }

    func clearRoutineContext() {
        activeRoutineContext = nil
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

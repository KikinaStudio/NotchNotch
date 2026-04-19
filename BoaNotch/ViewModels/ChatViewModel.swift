import Foundation
import AppKit
import Combine

enum VoiceState {
    case idle
    case recording
    case transcribing
}

struct BrainSetupOptions {
    var enableWiki: Bool
    var enableAutoIngest: Bool
    var enableWeeklyLint: Bool
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
    @Published var editingMessageId: UUID? = nil
    @Published var lastInputTokens: Int = 0

    private let client = HermesClient()
    var audioRecorder: AudioRecorder?

    /// Title cache for conversation history. Wired by AppDelegate.
    weak var titleStore: TitleStore?

    var sessionId: String? {
        get { client.sessionId }
        set {
            objectWillChange.send()
            client.sessionId = newValue
        }
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
                let (filteredTools, subagent) = Self.splitSubagentContent(result.toolCalls)
                messages[lastIndex].toolCallContent = filteredTools
                messages[lastIndex].subagentActivity = subagent
                messages[lastIndex].promptTokens = result.promptTokens
                messages[lastIndex].completionTokens = result.completionTokens
                if let p = result.promptTokens {
                    lastInputTokens = p
                }
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

                // After the first exchange of a fresh conversation, ask
                // Hermes for a 3-7 word title (ChatGPT-style auto-name).
                maybeGenerateTitle(userMessage: input, assistantResponse: result.content)
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

    /// Fire-and-forget LLM title generation, gated to the first exchange and
    /// to sessions that don't already have a cached title.
    private func maybeGenerateTitle(userMessage: String, assistantResponse: String) {
        guard let store = titleStore,
              let sid = client.sessionId,
              store.title(for: sid) == nil,
              !assistantResponse.isEmpty else { return }
        // First exchange = exactly one user message after the response lands.
        let userCount = messages.filter { $0.role == .user }.count
        guard userCount == 1 else { return }

        let client = self.client
        Task.detached(priority: .background) {
            guard let title = await client.generateTitle(
                userMessage: userMessage,
                assistantResponse: assistantResponse
            ) else { return }
            await MainActor.run { store.setTitle(title, for: sid) }
        }
    }

    func confirmNewConversation() {
        showNewConversationConfirm = false
        startNewConversation()
    }

    func startNewConversation() {
        cancelStream()
        messages.removeAll()
        lastInputTokens = 0
        // Generate a fresh notchnotch-{uuid} session so this conversation
        // gets its own row in Hermes state.db.
        objectWillChange.send()
        client.sessionId = "notchnotch-\(UUID().uuidString.lowercased())"
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

    func setupBrainPipeline(
        options: BrainSetupOptions,
        onStep: ((Int, Int, String) -> Void)? = nil
    ) async throws {
        struct Step { let label: String; let message: String }
        var steps: [Step] = []
        if options.enableWiki {
            steps.append(Step(
                label: "Installation du skill llm-wiki…",
                message: "Installe le skill llm-wiki depuis le hub officiel, puis configure son chemin de wiki sur ~/.hermes/brain/wiki. Les sources brutes sont dans ~/.hermes/brain/raw. Confirme quand c'est fait."
            ))
            steps.append(Step(
                label: "Vérification du skill…",
                message: "Vérifie que le skill llm-wiki est bien installé et configuré avec skills.config.wiki.path = ~/.hermes/brain/wiki."
            ))
        }
        if options.enableAutoIngest {
            steps.append(Step(
                label: "Création de la routine d'ingestion…",
                message: "Crée une routine cron qui exécute le skill llm-wiki en mode ingest sur le contenu de ~/.hermes/brain/raw toutes les 2 heures. Nomme-la 'brain-ingest'."
            ))
        }
        if options.enableWeeklyLint {
            steps.append(Step(
                label: "Création de la routine de maintenance…",
                message: "Crée une routine cron qui exécute le skill llm-wiki en mode lint tous les dimanches à 9h. Nomme-la 'brain-lint'."
            ))
        }
        let total = steps.count
        for (idx, step) in steps.enumerated() {
            await MainActor.run { onStep?(idx + 1, total, step.label) }
            try await client.sendCompletion(messages: [["role": "user", "content": step.message]])
        }
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

    func editMessage(id: UUID, newContent: String) {
        guard !isStreaming else { return }
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        guard messages[index].role == .user else { return }

        messages[index].content = newContent
        messages.removeSubrange((index + 1)...)
        editingMessageId = nil

        startRequest(input: newContent)
    }

    func removeAttachment(_ id: UUID) {
        pendingAttachments.removeAll { $0.id == id }
    }

    /// Returns true if clipboard contained an image and was handled
    func pasteFromClipboard() -> Bool {
        let pb = NSPasteboard.general
        let hasImageType = pb.types?.contains(where: { [.png, .tiff].contains($0) }) ?? false
        guard hasImageType, let image = NSImage(pasteboard: pb) else { return false }
        if let attachment = DocumentExtractor.extractFromClipboardImage(image) {
            pendingAttachments.append(attachment)
            return true
        }
        return false
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

    private static func splitSubagentContent(_ toolCalls: String) -> (toolCalls: String, subagent: String) {
        guard toolCalls.contains("🤖") else { return (toolCalls, "") }
        let lines = toolCalls.components(separatedBy: "\n")
        var tools: [String] = []
        var subagent: [String] = []
        for line in lines {
            if line.contains("🤖") || line.contains("delegate_task") {
                subagent.append(line)
            } else {
                tools.append(line)
            }
        }
        return (tools.joined(separator: "\n"), subagent.joined(separator: "\n"))
    }
}

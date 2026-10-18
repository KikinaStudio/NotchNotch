import Foundation
import AppKit
import Combine
import os.log

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
    /// Notice for a Hermes slash command NotchNotch doesn't run (`HermesSlashCommand`).
    @Published var slashNotice: String?
    /// Regenerated whenever the composer needs to grab focus from a remote
    /// trigger (e.g. tapping "Affine" on a routine delivery). ChatView
    /// observes `.onChange` and sets `isInputFocused = true`. UUID rather
    /// than Bool so re-firing always emits even if focus is already held.
    @Published var focusComposerTrigger: UUID = UUID()

    private let client = HermesClient()
    var audioRecorder: AudioRecorder?

    /// Title cache for conversation history. Wired by AppDelegate.
    weak var titleStore: TitleStore?

    /// Cron job store. Wired by AppDelegate; used for optimistic UI updates
    /// when toggling routine pause/resume so the dot flips before Hermes
    /// rewrites jobs.json.
    weak var cronStore: CronStore?

    /// Installed skills, for the `/` palette and `/skill` messages. Wired by AppDelegate.
    weak var brainVM: BrainViewModel?

    var sessionId: String? { client.sessionId }
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
        slashNotice = nil
        if runSlashCommand(text) { return }

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

    /// Runs `text` when it is a Hermes slash command and returns true: it never reaches the model
    /// (see `HermesSlashCommand`). The draft stays for a command NotchNotch doesn't run.
    private func runSlashCommand(_ text: String) -> Bool {
        guard let command = HermesSlashCommand.match(text) else { return false }
        // A skill one letter away from a command (`goals`) is the skill, not a typo.
        if case .nearMiss = command, SlashPalette.invokedSkill(in: text, skills: installedSkills) != nil { return false }
        let name = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix { !$0.isWhitespace })
        os_log("[notchnotch] slash command kept from the model: %{public}@", type: .info, name)
        switch command {
        case .unavailable, .nearMiss:
            slashNotice = command.notice
            return true
        case .newConversation: startNewConversation()
        case .modelMenu: notchVM?.openExpandedBar()
        case .history: notchVM?.openHistory()
        case .stop: cancelStream()
        }
        draft = ""
        editingMessageId = nil
        return true
    }

    private var installedSkills: [SkillInfo] {
        brainVM?.loadSkillsIfNeeded()
        return brainVM?.skills ?? []
    }

    /// System line for a message starting with an installed skill (`/llm-wiki …`). Hermes's API
    /// takes it as plain text (only Telegram and the terminal load the skill), and free-tier
    /// models skip it. Attachments come first in `input`, the typed text after the last one.
    private func skillContext(for input: String) -> String? {
        let text = input.range(of: "[End attachment]\n\n", options: .backwards).map { String(input[$0.upperBound...]) } ?? input
        guard let skill = SlashPalette.invokedSkill(in: text, skills: installedSkills) else { return nil }
        return "The user invoked the \"\(skill.name)\" skill by starting their message with /\(skill.slug). Load it with skill_view(\"\(skill.name)\") before answering, then follow its instructions for the rest of the message."
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
                if let skill = skillContext(for: input) {
                    systemContext = [systemContext, skill].compactMap { $0 }.joined(separator: "\n\n")
                }

                // streamResponse fires onEvent from the URLSession iterator's
                // context (not the main actor). Hop back to MainActor for
                // each UI mutation. Final reconciliation after the call
                // uses ResponseResult as source-of-truth against any
                // out-of-order or dropped deltas.
                let result = try await client.streamResponse(
                    input: input,
                    systemContext: systemContext
                ) { [weak self] event in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        guard let lastIndex = self.messages.indices.last else { return }
                        switch event {
                        case .textDelta(let d):
                            self.messages[lastIndex].content.append(d)
                            self.messages[lastIndex].liveStatus = nil  // progress makes the last status stale
                            // The agent is blocked while it waits, so new text under an unanswered
                            // card means Hermes timed out and denied it (fail-closed).
                            if self.messages[lastIndex].approval?.state == .pending {
                                self.messages[lastIndex].approval?.state = .expired
                            }

                        case .thinkingDelta(let d):
                            // Append to the last in-progress thinking event.
                            // If none, drop silently (orphan delta — never
                            // create a phantom event from a stray chunk).
                            guard let evIdx = self.messages[lastIndex].events.lastIndex(where: {
                                if case .thinking = $0.kind, case .inProgress = $0.status { return true }
                                return false
                            }) else { break }
                            self.messages[lastIndex].events[evIdx].detail.append(d)

                        case .thinkingStarted:
                            self.messages[lastIndex].liveStatus = nil
                            self.messages[lastIndex].events.append(AgentEvent(
                                id: UUID().uuidString,
                                kind: .thinking,
                                status: .inProgress,
                                startedAt: Date(),
                                endedAt: nil,
                                detail: ""
                            ))

                        case .thinkingEnded:
                            // Close the most recent in-progress thinking
                            // event. Drop silently if none — an orphaned
                            // close event shouldn't synthesize one.
                            guard let evIdx = self.messages[lastIndex].events.lastIndex(where: {
                                if case .thinking = $0.kind, case .inProgress = $0.status { return true }
                                return false
                            }) else { break }
                            self.messages[lastIndex].events[evIdx].status = .completed
                            self.messages[lastIndex].events[evIdx].endedAt = Date()

                        case .toolCallStarted(let id, let name, let preview):
                            self.messages[lastIndex].liveStatus = nil
                            self.messages[lastIndex].events.append(AgentEvent(
                                id: id,
                                kind: .tool(name: name, argsPreview: preview),
                                status: .inProgress,
                                startedAt: Date(),
                                endedAt: nil,
                                detail: preview
                            ))

                        case .toolCallCompleted(let id, _, let resultPreview):
                            // Match by call_id (stable across started/completed
                            // per Hermes contract). If no match, drop — never
                            // fabricate a synthetic completed event.
                            guard let evIdx = self.messages[lastIndex].events.firstIndex(where: { $0.id == id }) else { break }
                            self.messages[lastIndex].events[evIdx].status = .completed
                            self.messages[lastIndex].events[evIdx].endedAt = Date()
                            if !resultPreview.isEmpty {
                                let sep = self.messages[lastIndex].events[evIdx].detail.isEmpty ? "" : "\n→ "
                                self.messages[lastIndex].events[evIdx].detail.append(sep + resultPreview)
                            }

                        case .status(let text):
                            self.messages[lastIndex].liveStatus = text

                        case .completed(let pt, _):
                            if let pt { self.lastInputTokens = pt }

                        case .failed(let reason):
                            // Mark every still-in-progress event as failed
                            // with the stream-level reason. Imprecise (we
                            // don't know which one actually broke) but
                            // honest — partial detail text is preserved.
                            for i in self.messages[lastIndex].events.indices {
                                if case .inProgress = self.messages[lastIndex].events[i].status {
                                    self.messages[lastIndex].events[i].status = .failed(reason)
                                    self.messages[lastIndex].events[i].endedAt = Date()
                                }
                            }

                        case .retryStarted:
                            // The retry restarts a fresh agent turn server-side
                            // (no true mid-stream resume on /v1/responses), so
                            // any deltas accumulated on this assistant message
                            // would be doubled by the second pass. Clear them.
                            // Final reconciliation via ResponseResult guarantees
                            // the visible content matches the surviving turn.
                            self.messages[lastIndex].content = ""
                            self.messages[lastIndex].events.removeAll()
                            self.messages[lastIndex].liveStatus = nil
                            self.messages[lastIndex].approval = nil

                        case .approvalRequested(let request):
                            self.messages[lastIndex].liveStatus = nil
                            self.messages[lastIndex].approval = request
                            if let notchVM = self.notchVM, notchVM.isClosed {
                                notchVM.showActionableToast("Hermes attend ton accord pour une commande. Tape pour voir.", kind: .info) { [weak notchVM] in
                                    notchVM?.open()
                                }
                            }
                        }
                    }
                }

                guard !Task.isCancelled else { return }
                guard let lastIndex = messages.indices.last else { return }

                // Reconcile content from the authoritative ResponseResult.
                // Events array is the source of truth for the timeline (built
                // incrementally), so we only sync `content` here — events
                // were already finalized as deltas arrived.
                messages[lastIndex].content = result.content
                messages[lastIndex].promptTokens = result.promptTokens
                messages[lastIndex].completionTokens = result.completionTokens
                if let p = result.promptTokens {
                    lastInputTokens = p
                }

                // Safety net: any event still flagged inProgress at this
                // point (e.g. dropped close event) gets force-completed so
                // the UI never shows a perpetual spinner.
                let now = Date()
                for i in messages[lastIndex].events.indices {
                    if case .inProgress = messages[lastIndex].events[i].status {
                        messages[lastIndex].events[i].status = .completed
                        messages[lastIndex].events[i].endedAt = now
                    }
                }

                messages[lastIndex].isStreaming = false
                clearApproval(at: lastIndex)
                isStreaming = false
                connectionError = nil

                if let notchVM, notchVM.isClosed,
                   let lastMsg = messages.last, lastMsg.role == .assistant {
                    notchVM.showToast(lastMsg.content, kind: .chat)
                }

                // After the first exchange of a fresh conversation, ask
                // Hermes for a 3-7 word title (ChatGPT-style auto-name).
                maybeGenerateTitle(userMessage: input, assistantResponse: result.content)
            } catch {
                if !Task.isCancelled {
                    let desc = error.localizedDescription
                    // Typed retry-exhaustion errors from streamResponse take
                    // priority — their French localizedDescription is the
                    // user-facing message (in-bubble, no toast).
                    if let hermesError = error as? HermesError,
                       case .unreachable = hermesError {
                        connectionError = hermesError.errorDescription
                        // Surface an actionable toast on top of the in-bubble
                        // error. Bubble carries the explanation; toast carries
                        // the one-tap repair (install LaunchAgent / kickstart).
                        offerHermesRepair()
                    } else if let hermesError = error as? HermesError,
                              case .streamInterrupted = hermesError {
                        connectionError = hermesError.errorDescription
                    } else if let hermesError = error as? HermesError,
                              case .serverError = hermesError {
                        connectionError = hermesError.errorDescription
                    } else if let hermesError = error as? HermesError,
                              case .agentFailed = hermesError {
                        // Hermes's own failure message (provider error, crash), verbatim.
                        connectionError = hermesError.errorDescription
                    } else if desc.contains("Could not connect") || desc.contains("Connection refused") {
                        connectionError = "Can't reach Hermes on localhost:8642. Make sure the gateway is running (hermes gateway) and API_SERVER_ENABLED=true is set in ~/.hermes/.env"
                        offerHermesRepair()
                    } else if desc.contains("timed out") || desc.contains("Timeout") {
                        connectionError = "Hermes took too long to respond. Try reducing max iterations in settings, or check if the agent is stuck (hermes logs)"
                    } else if let hermesError = error as? HermesError,
                              case .httpErrorWithBody(let code, let body) = hermesError {
                        if code == 401 || code == 403 {
                            connectionError = "Clé API Hermes manquante ou invalide (API_SERVER_KEY dans ~/.hermes/.env)."
                            offerHermesRepair("Clé API Hermes invalide. Tape pour réparer.")
                        } else if body.contains("Nous Portal") || body.contains("hermes auth add nous") {
                            connectionError = "Nous Portal sign-in required. Open Terminal and run: hermes auth add nous"
                        } else if code >= 500 {
                            connectionError = "Hermes internal error. Check ~/.hermes/logs/err.log or run: hermes logs --tail 50"
                        } else {
                            connectionError = "Unexpected error: \(desc)"
                        }
                    } else {
                        connectionError = "Unexpected error: \(desc)"
                    }
                    if let lastIndex = messages.indices.last {
                        // Mark any in-progress events as failed so the UI
                        // doesn't keep spinning. Use the connectionError
                        // text as the reason if available, else a generic.
                        let reason = connectionError ?? "Stream interrupted"
                        let now = Date()
                        for i in messages[lastIndex].events.indices {
                            if case .inProgress = messages[lastIndex].events[i].status {
                                messages[lastIndex].events[i].status = .failed(reason)
                                messages[lastIndex].events[i].endedAt = now
                            }
                        }
                        messages[lastIndex].isStreaming = false
                        clearApproval(at: lastIndex)
                        if messages[lastIndex].content.isEmpty && messages[lastIndex].events.isEmpty {
                            messages.removeLast()
                        }
                    }
                    isStreaming = false
                }
            }
        }
    }

    /// Surface an actionable toast that says "tap to fix" — when tapped,
    /// writes any missing API_SERVER_* env (key included), starts or
    /// restarts the gateway,
    /// waits up to 10s for `/health`, then retries the last user message.
    /// Inline `connectionError` stays in the bubble for context; the toast
    /// is the one-tap recovery path for users who shouldn't have to know
    /// what a gateway is.
    @MainActor
    func offerHermesRepair(_ message: String = "Hermes ne répond pas. Tape pour réparer.") {
        // The closure captures notchVM/self weakly; toast tap-only triggers
        // the work (we don't fire it eagerly to avoid running on transient
        // network blips that resolve on their own).
        notchVM?.showActionableToast(
            message,
            kind: .error
        ) { [weak self] in
            Task { @MainActor in
                await self?.repairAndRetry()
            }
        }
    }

    /// Run the LaunchAgent repair appropriate to the current state, then
    /// retry the last user message once /health responds. Fires progress /
    /// outcome toasts at each step. Best-effort — surfaces a final error
    /// toast and bails if the repair fails or `/health` never comes up.
    @MainActor
    private func repairAndRetry() async {
        let launcher = HermesGatewayLauncher.shared
        launcher.refreshState()

        notchVM?.showToast("Réparation d'Hermes…", kind: .info)

        // A missing key keeps :8642 closed, so this is the usual root cause of
        // "unreachable". Already restarts a loaded gateway when it wrote.
        let wroteEnv = await launcher.ensureApiServerEnv()

        switch launcher.state {
        case .notInstalled, .installedNotLoaded:
            do {
                try await launcher.install()
            } catch {
                notchVM?.showToast(
                    "Échec de la réparation : \(error.localizedDescription)",
                    kind: .error
                )
                return
            }
        case .installedAndLoaded:
            // Loaded but /health silent (stuck), or 401 with a valid key in
            // .env (gateway still on an older one): restart, never rotate the key.
            if !wroteEnv { await launcher.restart() }
        }

        // Poll /health for up to 10s. Hermes takes a few seconds to import
        // all the Python modules and bind the socket — anything under 10s
        // is normal.
        var becameReachable = false
        for _ in 0..<10 {
            if await launcher.isHermesReachable() {
                becameReachable = true
                break
            }
            try? await Task.sleep(for: .seconds(1))
        }

        guard becameReachable else {
            notchVM?.showToast(
                "Hermes ne démarre pas. Regarde ~/.hermes/logs/gateway.error.log.",
                kind: .error
            )
            return
        }

        // Clear the inline error and retry the last user message. If there
        // isn't one (edge case — toast tapped after manual cancel), at
        // least the user is back to a working state.
        connectionError = nil
        notchVM?.showToast("Hermes redémarré ✓", kind: .success)
        retryLastUserMessage()
    }

    /// Replay the last user message in the current conversation. The catch
    /// block in `startRequest` strips the empty assistant placeholder on
    /// error, so we just append a fresh placeholder + start a new request
    /// with the same input. No-op if there's no user message to retry, or
    /// if a stream is currently in flight.
    @MainActor
    func retryLastUserMessage() {
        guard !isStreaming else { return }
        guard let lastUser = messages.last(where: { $0.role == .user }) else { return }
        startRequest(input: lastUser.content)
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
        objectWillChange.send()
        client.startConversation()
    }

    /// Resume a history row. A `notchnotch-` key also names its `conversation`, so Hermes
    /// re-chains the server-side history (rows from before H2a used a separate name and
    /// restart empty). Other sources (Telegram, CLI…) continue in a fresh conversation.
    func resumeConversation(key: String) {
        cancelStream()
        objectWillChange.send()
        client.startConversation(id: key.hasPrefix("notchnotch-") ? key : nil)
    }

    func cancelStream() {
        streamTask?.cancel()
        streamTask = nil
        if let lastIndex = messages.indices.last, messages[lastIndex].isStreaming {
            // Force-close any in-progress events so the UI doesn't keep
            // spinning post-cancel.
            let now = Date()
            for i in messages[lastIndex].events.indices {
                if case .inProgress = messages[lastIndex].events[i].status {
                    messages[lastIndex].events[i].status = .failed("Cancelled")
                    messages[lastIndex].events[i].endedAt = now
                }
            }
            messages[lastIndex].isStreaming = false
            clearApproval(at: lastIndex)
        }
        isStreaming = false
    }

    /// End of turn: Hermes no longer waits, so drop the card unless it shows the expiry.
    private func clearApproval(at index: Int) {
        if messages[index].approval?.state != .expired { messages[index].approval = nil }
    }

    /// Answer the approval card of message `messageId` ("once" or "deny", never "always").
    /// 200 removes the card; 409 means Hermes stopped waiting (timeout → denied); a transport
    /// error re-enables the buttons.
    func respondToApproval(messageId: UUID, choice: String) {
        guard let index = messages.firstIndex(where: { $0.id == messageId }),
              let request = messages[index].approval, request.state == .pending else { return }
        messages[index].approval?.state = .sending
        Task { @MainActor [weak self] in
            guard let self else { return }
            let result: Bool?
            do {
                result = try await self.client.respondToApproval(runId: request.runId, requestId: request.requestId, choice: choice)
            } catch {
                os_log("[notchnotch] approval response failed: %{public}@", type: .error, String(describing: error))
                result = nil
            }
            guard let index = self.messages.firstIndex(where: { $0.id == messageId }),
                  self.messages[index].approval?.requestId == request.requestId else { return }
            switch result {
            case true?: self.messages[index].approval = nil
            case false?: self.messages[index].approval?.state = .expired
            case nil:
                self.messages[index].approval?.state = .pending
                self.notchVM?.showToast("Impossible d'envoyer ta réponse à Hermes. Réessaye.", kind: .error)
            }
        }
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
                notchVM?.showToast("Saved to brain", kind: .success)
            } catch {
                print("[notchnotch] Save to brain error: \(error)")
                notchVM?.showToast("Brain save failed", kind: .error)
            }
        }
    }

    /// Fire-and-forget routine creation via chat. Composed prompt instructs
    /// Hermes to invoke its `cronjob(action="create", ...)` tool. HTTP 200
    /// means the request was received, not that the job is live — the
    /// CronStore watcher will pick up the new entry when jobs.json changes.
    func createRoutine(draft: String) {
        let messages: [[String: String]] = [["role": "user", "content": draft]]
        Task { @MainActor in
            do {
                try await client.sendCompletion(messages: messages)
                notchVM?.showToast("Routine created", kind: .success)
            } catch {
                print("[notchnotch] Create routine error: \(error)")
                notchVM?.showToast("Routine creation failed", kind: .error)
            }
        }
    }

    /// Fire-and-forget request to Hermes to rewrite a memory block. NotchNotch
    /// never writes `~/.hermes/memories/` directly — Hermes owns those files
    /// and applies the change through its `memory` tool. UI shows an optimistic
    /// toast; callers should schedule a BrainViewModel reload a few seconds
    /// later to pick up the rewritten MEMORY.md / USER.md.
    func updateMemory(oldContent: String, newContent: String) {
        let trimmedOld = oldContent.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNew = newContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedOld != trimmedNew, !trimmedNew.isEmpty else { return }
        let prompt = """
        Please update my memory. Find the existing block that matches the text below and replace it with the new version. Keep the `§` separators and your usual formatting conventions intact.

        === OLD BLOCK ===
        \(trimmedOld)

        === NEW VERSION ===
        \(trimmedNew)
        """
        let messages: [[String: String]] = [["role": "user", "content": prompt]]
        Task { @MainActor in
            do {
                try await client.sendCompletion(messages: messages)
                notchVM?.showToast("Mémoire mise à jour", kind: .success)
            } catch {
                print("[notchnotch] Memory update error: \(error)")
                notchVM?.showToast("Mise à jour échouée", kind: .error)
            }
        }
    }

    /// Fire-and-forget request to Hermes to delete a memory block.
    func deleteMemory(content: String) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let prompt = """
        Please delete this exact memory block from my memory. Remove the entire block and the surrounding `§` separator so nothing dangling remains.

        === BLOCK TO DELETE ===
        \(trimmed)
        """
        let messages: [[String: String]] = [["role": "user", "content": prompt]]
        Task { @MainActor in
            do {
                try await client.sendCompletion(messages: messages)
                notchVM?.showToast("Mémoire supprimée", kind: .success)
            } catch {
                print("[notchnotch] Memory delete error: \(error)")
                notchVM?.showToast("Suppression échouée", kind: .error)
            }
        }
    }

    /// Pause/resume a cron job silently via the Hermes REST endpoint — no chat
    /// message is created, no panel switching. Documented exception to the
    /// "everything through chat" principle (see CLAUDE.md). UX rationale: the
    /// status dot toggle on routine cards must feel instant; routing through
    /// the LLM added 500ms-1s of latency and could be misrouted.
    func setRoutinePaused(_ job: CronJob, paused: Bool) {
        cronStore?.applyOptimisticPause(jobId: job.id, paused: paused)
        Task { @MainActor in
            do {
                if paused {
                    try await client.pauseCronJob(id: job.id)
                } else {
                    try await client.resumeCronJob(id: job.id)
                }
            } catch {
                print("[notchnotch] setRoutinePaused error: \(error)")
                cronStore?.applyOptimisticPause(jobId: job.id, paused: !paused)
                notchVM?.showToast("Échec — Hermes injoignable", kind: .error)
            }
        }
    }

    /// Edit a cron job's name / prompt / schedule / deliver via the Hermes REST
    /// endpoint. CronStore's file watcher reconciles the UI ~500ms after the
    /// successful PATCH — same eventual-consistency pattern as memory edits.
    /// Skip empty patches (no-op submit).
    func updateRoutine(jobId: String, patch: [String: Any]) {
        guard !patch.isEmpty else { return }
        Task { @MainActor in
            do {
                try await client.updateCronJob(id: jobId, patch: patch)
                notchVM?.showToast("Routine modifiée", kind: .success)
            } catch {
                print("[notchnotch] updateRoutine error: \(error)")
                notchVM?.showToast("Échec — Hermes injoignable", kind: .error)
            }
        }
    }

    func setRoutineContext(_ job: CronJob) {
        activeRoutineContext = job
    }

    func clearRoutineContext() {
        activeRoutineContext = nil
    }

    /// Open a refinement turn for a routine: set its context (sticky — the
    /// user can chain follow-up turns until they close the routineContextTag),
    /// pre-fill the composer with a neutral primer, and trigger composer
    /// focus so the cursor lands ready to type. Overwrites any existing
    /// draft — the primer IS the desired entry state. No-op if the routine
    /// has been removed since the delivery was injected.
    func startRefine(routineId: String) {
        guard let job = cronStore?.jobs.first(where: { $0.id == routineId }) else {
            print("[notchnotch] startRefine: routine \(routineId) not found")
            return
        }
        activeRoutineContext = job
        draft = "Pour cette routine, je voudrais que tu… "
        focusComposerTrigger = UUID()
    }

    func editMessage(id: UUID, newContent: String) {
        guard !isStreaming else { return }
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        guard messages[index].role == .user else { return }
        slashNotice = nil
        if runSlashCommand(newContent) { return }

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
            voiceState = .recording
            Task { @MainActor in
                await audioRecorder?.startRecordingWithPermission()
            }
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

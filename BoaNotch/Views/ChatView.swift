import SwiftUI

struct ChatView: View {
    @ObservedObject var chatVM: ChatViewModel
    @ObservedObject var notchVM: NotchViewModel
    @ObservedObject var searchVM: SearchViewModel
    @ObservedObject var hermesConfig: HermesConfig
    @FocusState private var isInputFocused: Bool
    @State private var pasteMonitor: Any?

    @EnvironmentObject var appearanceSettings: AppearanceSettings

    var body: some View {
        VStack(spacing: 0) {
            // Messages — bottom-anchored, with fade overlay
            ZStack {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            Spacer(minLength: 0)
                                .frame(maxHeight: .infinity)

                            ForEach(chatVM.messages) { message in
                                MessageBubble(
                                    message: message,
                                    searchQuery: searchVM.query,
                                    onRetry: (message.role == .assistant && message.id == chatVM.messages.last(where: { $0.role == .assistant })?.id)
                                        ? { chatVM.retryLastAssistant() }
                                        : nil,
                                    onEdit: (message.role == .user && !chatVM.isStreaming)
                                        ? { msg in
                                            chatVM.editingMessageId = msg.id
                                            chatVM.draft = msg.content
                                        }
                                        : nil,
                                    onRefine: (message.routineId != nil)
                                        ? { rid in chatVM.startRefine(routineId: rid) }
                                        : nil,
                                    isChatStreaming: chatVM.isStreaming
                                )
                                .id(message.id)
                            }
                        }
                        .padding(.horizontal, 2)
                        .padding(.bottom, 14)
                        .frame(minHeight: 0, maxHeight: .infinity, alignment: .bottom)
                    }
                    .scrollIndicators(.hidden)
                    .defaultScrollAnchor(.bottom)
                    .onChange(of: chatVM.messages.count) { scrollToBottom(proxy) }
                    .onChange(of: chatVM.messages.last?.content) { scrollToBottom(proxy) }
                    .onChange(of: searchVM.currentMatchIndex) { scrollToSearch(proxy) }
                    .onChange(of: searchVM.totalMatches) { scrollToSearch(proxy) }
                }

                // Fade to black at the top of the scroll area
                VStack {
                    LinearGradient(
                        colors: [.black, .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 20)
                    .allowsHitTesting(false)
                    Spacer()
                }

                // Fade to black at the bottom of the scroll area
                VStack {
                    Spacer()
                    LinearGradient(
                        colors: [.clear, .black],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 20)
                    .allowsHitTesting(false)
                }
            }

            // Connection error banner
            if let errorMessage = chatVM.connectionError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(DS.Text.micro)
                    Text(errorMessage)
                        .font(DS.Text.microMedium)
                        .lineLimit(3)
                }
                .foregroundStyle(.orange)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .padding(.horizontal, 2)
                .onTapGesture { chatVM.connectionError = nil }
                .task(id: errorMessage) {
                    try? await Task.sleep(nanoseconds: 15_000_000_000)
                    if !Task.isCancelled {
                        chatVM.connectionError = nil
                    }
                }
                .transition(.opacity)
            }

            // Pending attachment chips
            if !chatVM.pendingAttachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(chatVM.pendingAttachments) { attachment in
                            PendingAttachmentChip(attachment: attachment) {
                                chatVM.removeAttachment(attachment.id)
                            }
                        }
                    }
                    .padding(.horizontal, 2)
                    .padding(.vertical, 4)
                }
            }

            if let routine = chatVM.activeRoutineContext {
                routineContextTag(routine)
            }

            if chatVM.editingMessageId != nil {
                HStack {
                    Text("Editing message")
                        .font(DS.Text.micro)
                        .foregroundStyle(DS.Surface.tertiary)
                    Spacer()
                    Button("Cancel") {
                        chatVM.editingMessageId = nil
                        chatVM.draft = ""
                    }
                    .font(DS.Text.micro)
                    .foregroundStyle(DS.Surface.tertiary)
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 2)
            }

            inputBar
        }
        .onAppear {
            isInputFocused = true
            pasteMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "v" {
                    if notchVM.isOpen && chatVM.pasteFromClipboard() {
                        return nil
                    }
                }
                return event
            }
        }
        .onChange(of: chatVM.focusComposerTrigger) {
            isInputFocused = true
        }
        .onDisappear {
            if let monitor = pasteMonitor {
                NSEvent.removeMonitor(monitor)
                pasteMonitor = nil
            }
        }
    }

    private func routineContextTag(_ job: CronJob) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(DS.Text.nano)
                .foregroundStyle(AppColors.accent)

            Text(job.name)
                .font(DS.Text.microMedium)
                // TODO(design): 0.7 — entre primary (~1.0) et secondary (~0.55), aucun ShapeStyle natif aligné
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)

            Button {
                chatVM.clearRoutineContext()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(DS.Text.micro)
                    .foregroundStyle(DS.Surface.tertiary)
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(AppColors.accent.opacity(0.12))
        .clipShape(Capsule())
        .padding(.horizontal, 2)
        .padding(.bottom, 4)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
        .animation(.easeInOut(duration: 0.2), value: chatVM.activeRoutineContext?.id)
    }

    // MARK: - Input bar (bare text field, buttons on right)

    private var inputBar: some View {
        VStack(spacing: 0) {
            // Expanded bar
            if notchVM.isExpandedBarOpen {
                ExpandedBarView(config: hermesConfig, notchVM: notchVM, chatVM: chatVM)
                    .padding(.horizontal, 2)
                    .padding(.bottom, 6)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            HStack(alignment: .center, spacing: 10) {
                TextField("", text: $chatVM.draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    // TODO(design): 13pt scaled par appearanceSettings.textSize, token DS.Text.* fixe non applicable
                    .font(.system(size: 13 * appearanceSettings.textSize.scale))
                    .foregroundStyle(.white)
                    .tint(AppColors.accent)
                    .lineLimit(1...4)
                    .focused($isInputFocused)
                    .onSubmit { sendAndCloseBar() }

                Button { openFilePicker() } label: {
                    Image(systemName: "plus")
                        .font(DS.Icon.secondary)
                        .foregroundStyle(DS.Surface.secondary)
                }
                .buttonStyle(.plain)
                .pointingHandCursor()

                micButton

                // More icon — toggles expanded bar
                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        notchVM.isExpandedBarOpen.toggle()
                    }
                } label: {
                    Image(systemName: notchVM.isExpandedBarOpen ? "ellipsis.circle.fill" : "ellipsis.circle")
                        // TODO(design): 15pt one-off entre DS.Icon.secondary (14) et DS.Icon.primary (18) — taille intermédiaire pour ce toggle
                        .font(.system(size: 15))
                        .foregroundStyle(notchVM.isExpandedBarOpen ? AnyShapeStyle(AppColors.accent) : DS.Surface.tertiary)
                }
                .buttonStyle(.plain)
                .pointingHandCursor()

                if chatVM.isStreaming {
                    Button { chatVM.cancelStream() } label: {
                        // TODO(design): 0.7 spinner — entre primary (~1.0) et secondary (~0.55), pas de ShapeStyle natif aligné
                        BrailleSpinner(size: 16, color: .white.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    .pointingHandCursor()
                } else {
                    Button { sendAndCloseBar() } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .foregroundStyle(canSend ? DS.Surface.primary : AnyShapeStyle(Color.white.opacity(0.20)))
                            .font(DS.Icon.primary)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSend)
                    .pointingHandCursor()
                }

}
            .padding(.horizontal, 2)
            .padding(.top, 2)
            .padding(.bottom, 6)
        }
    }

    private func sendAndCloseBar() {
        if let editId = chatVM.editingMessageId {
            chatVM.editMessage(id: editId, newContent: chatVM.draft)
        } else {
            chatVM.send()
        }
        if notchVM.isExpandedBarOpen {
            withAnimation(.easeOut(duration: 0.2)) {
                notchVM.isExpandedBarOpen = false
            }
        }
    }

    // MARK: - Mic button (idle / recording / transcribing)

    @ViewBuilder
    private var micButton: some View {
        switch chatVM.voiceState {
        case .idle:
            Button { chatVM.toggleVoiceRecord() } label: {
                Image(systemName: "mic.fill")
                    .font(DS.Icon.secondary)
                    .foregroundStyle(DS.Surface.secondary)
            }
            .buttonStyle(.plain)
            .pointingHandCursor()

        case .recording:
            Button { chatVM.toggleVoiceRecord() } label: {
                Image(systemName: "mic.fill")
                    .font(DS.Icon.secondary)
                    .foregroundStyle(AppColors.accent)
            }
            .buttonStyle(.plain)
            .modifier(PulsingModifier())
            .pointingHandCursor()

        case .transcribing:
            SpinningRing()
        }
    }

    private var canSend: Bool {
        !chatVM.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !chatVM.pendingAttachments.isEmpty
    }


    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        if let lastId = chatVM.messages.last?.id {
            withAnimation(.easeOut(duration: 0.15)) {
                proxy.scrollTo(lastId, anchor: .bottom)
            }
        }
    }

    private func scrollToSearch(_ proxy: ScrollViewProxy) {
        if let msgId = searchVM.currentMessageId {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(msgId, anchor: .center)
            }
        }
    }

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.begin { response in
            guard response == .OK else { return }
            for url in panel.urls {
                let attachment = DocumentExtractor.extract(from: url)
                DispatchQueue.main.async {
                    chatVM.pendingAttachments.append(attachment)
                }
            }
        }
    }
}

// MARK: - Spinning ring for transcription state

struct SpinningRing: View {
    @State private var isSpinning = false

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.7)
            .stroke(AppColors.accent, lineWidth: 1.5)
            .frame(width: 14, height: 14)
            .rotationEffect(.degrees(isSpinning ? 360 : 0))
            .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: isSpinning)
            .onAppear { isSpinning = true }
    }
}

struct PendingAttachmentChip: View {
    let attachment: Attachment
    let onRemove: () -> Void

    private static let imageTypes: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic"]

    var body: some View {
        HStack(spacing: 4) {
            if Self.imageTypes.contains(attachment.fileType),
               let url = attachment.fileURL,
               let nsImage = NSImage(contentsOf: url) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 20, height: 20)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            } else {
                Image(systemName: sfIconForFileType(attachment.fileType))
                    .font(DS.Text.nano)
            }
            Text(attachment.fileName)
                .font(DS.Text.micro)
                .lineLimit(1)
            Button { onRemove() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(DS.Text.micro)
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(DS.Surface.secondary)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(DS.Stroke.hairline)
        .clipShape(Capsule())
    }
}

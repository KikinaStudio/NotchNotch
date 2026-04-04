import SwiftUI

struct ChatView: View {
    @ObservedObject var chatVM: ChatViewModel
    @ObservedObject var notchVM: NotchViewModel
    @ObservedObject var searchVM: SearchViewModel
    @ObservedObject var hermesConfig: HermesConfig
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Messages — bottom-anchored, with fade overlay
            ZStack(alignment: .bottom) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            Spacer(minLength: 0)
                                .frame(maxHeight: .infinity)

                            ForEach(chatVM.messages) { message in
                                MessageBubble(message: message, searchQuery: searchVM.query)
                                    .id(message.id)
                            }
                        }
                        .padding(.horizontal, 2)
                        .padding(.bottom, 36)
                        .frame(minHeight: 0, maxHeight: .infinity, alignment: .bottom)
                    }
                    .scrollIndicators(.hidden)
                    .defaultScrollAnchor(.bottom)
                    .onChange(of: chatVM.messages.count) { scrollToBottom(proxy) }
                    .onChange(of: chatVM.messages.last?.content) { scrollToBottom(proxy) }
                    .onChange(of: searchVM.currentMatchIndex) { scrollToSearch(proxy) }
                    .onChange(of: searchVM.totalMatches) { scrollToSearch(proxy) }
                }

                // Fade to black at the bottom of the scroll area
                LinearGradient(
                    colors: [.clear, .black],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 32)
                .allowsHitTesting(false)
            }

            if chatVM.messages.isEmpty && chatVM.connectionError == nil {
                VStack(spacing: 12) {
                    if let resourceURL = Bundle.main.resourceURL,
                       let logoData = try? Data(contentsOf: resourceURL.appendingPathComponent("logo-white.png")),
                       let nsImage = NSImage(data: logoData) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: 220)
                            .opacity(0.12)
                    }
                    Text("Notch Notch ! Who's there ? Your future.")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.12))
                        .multilineTextAlignment(.center)
                }
                .padding(.bottom, 8)
            }

            // Connection error indicator
            if chatVM.connectionError != nil {
                HStack(spacing: 4) {
                    Circle()
                        .fill(.red.opacity(0.8))
                        .frame(width: 6, height: 6)
                    Text("Offline")
                        .font(.system(size: 10))
                        .foregroundStyle(.red.opacity(0.6))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 2)
                .padding(.bottom, 4)
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

            // Iteration warning banner
            if hermesConfig.iterationPercentage >= 0.80 {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                    Text(hermesConfig.iterationPercentage >= 0.95
                         ? "Iteration limit reached (\(hermesConfig.currentIteration)/\(hermesConfig.effectiveMaxIterations))"
                         : "Approaching iteration limit (\(hermesConfig.currentIteration)/\(hermesConfig.effectiveMaxIterations))")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(hermesConfig.iterationPercentage >= 0.95 ? .red : .orange)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity)
                .background((hermesConfig.iterationPercentage >= 0.95 ? Color.red : .orange).opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .padding(.horizontal, 2)
                .transition(.opacity)
            }

            inputBar
        }
        .onAppear { isInputFocused = true }
    }

    // MARK: - Input bar (bare text field, buttons on right)

    private var inputBar: some View {
        VStack(spacing: 0) {
            // Expanded bar (brain toggle)
            if notchVM.isExpandedBarOpen {
                ExpandedBarView(config: hermesConfig, notchVM: notchVM)
                    .padding(.horizontal, 2)
                    .padding(.bottom, 6)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            HStack(alignment: .center, spacing: 10) {
                TextField("", text: $chatVM.draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(.white)
                    .tint(AppColors.accent)
                    .lineLimit(1...4)
                    .focused($isInputFocused)
                    .onSubmit { sendAndCloseBar() }

                Button { openFilePicker() } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
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
                        .font(.system(size: 15))
                        .foregroundStyle(notchVM.isExpandedBarOpen ? AppColors.accent : .white.opacity(0.4))
                }
                .buttonStyle(.plain)
                .pointingHandCursor()

                if chatVM.isStreaming {
                    Button { chatVM.cancelStream() } label: {
                        BrailleSpinner(size: 16, color: .white.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    .pointingHandCursor()
                } else {
                    Button { sendAndCloseBar() } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .foregroundStyle(canSend ? .white.opacity(0.85) : .white.opacity(0.15))
                            .font(.system(size: 18))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSend)
                    .pointingHandCursor()
                }

}
            .padding(.horizontal, 2)
            .padding(.vertical, 6)
        }
    }

    private func sendAndCloseBar() {
        chatVM.send()
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
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .buttonStyle(.plain)
            .pointingHandCursor()

        case .recording:
            Button { chatVM.toggleVoiceRecord() } label: {
                Image(systemName: "mic.fill")
                    .font(.system(size: 14))
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

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: sfIconForFileType(attachment.fileType))
                .font(.system(size: 9))
            Text(attachment.fileName)
                .font(.system(size: 10))
                .lineLimit(1)
            Button { onRemove() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 10))
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(.white.opacity(0.5))
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(.white.opacity(0.06))
        .clipShape(Capsule())
    }

}

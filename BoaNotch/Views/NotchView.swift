import SwiftUI
import UniformTypeIdentifiers

struct NotchView: View {
    @ObservedObject var chatVM: ChatViewModel
    @ObservedObject var notchVM: NotchViewModel
    @ObservedObject var sessionStore: SessionStore
    @ObservedObject var searchVM: SearchViewModel
    @ObservedObject var hermesConfig: HermesConfig
    @ObservedObject var onboardingVM: OnboardingViewModel
    @ObservedObject var cronStore: CronStore
    @ObservedObject var brainVM: BrainViewModel

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear

            VStack(alignment: .center, spacing: 0) {
                notchBody
                    .frame(
                        width: notchVM.currentWidth,
                        height: notchVM.currentHeight
                    )
                    .contentShape(
                        NotchShape(
                            topCornerRadius: notchVM.topCornerRadius,
                            bottomCornerRadius: notchVM.bottomCornerRadius
                        )
                    )
                    .onHover { hovering in notchVM.handleHover(hovering) }
                    .onTapGesture { notchVM.handleClick() }
                    .onDrop(of: [.fileURL], delegate: NotchDropDelegate(
                        notchVM: notchVM, chatVM: chatVM, notchWidth: notchVM.currentWidth
                    ))
                    .animation(
                        .interactiveSpring(response: 0.42, dampingFraction: 0.8, blendDuration: 0),
                        value: notchVM.isOpen
                    )
                    .animation(
                        .interactiveSpring(response: 0.4, dampingFraction: 0.8, blendDuration: 0),
                        value: notchVM.isThinkingClosed
                    )

                // Recording toast — directly below the closed notch
                if notchVM.isRecording && !notchVM.isOpen {
                    RecordingToastView(notchVM: notchVM)
                        .padding(.top, 8)
                        .transition(.asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal: .opacity
                        ))
                }

                if notchVM.isToastVisible, let msg = notchVM.toastMessage {
                    ToastView(message: msg, notchWidth: notchVM.closedSize.width, isClipperToast: notchVM.isClipperToast)
                        .padding(.top, 8)
                        .transition(.asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal: .opacity
                        ))
                        .onTapGesture { notchVM.open() }
                }

            }
        }
        .frame(
            width: NotchWindowController.panelWidth,
            height: NotchWindowController.panelHeight,
            alignment: .top
        )
    }

    private var notchBody: some View {
        ZStack {
            NotchShape(
                topCornerRadius: notchVM.topCornerRadius,
                bottomCornerRadius: notchVM.bottomCornerRadius
            )
            .fill(Color.black)
            .shadow(
                color: .black.opacity(notchVM.isOpen ? 0.5 : 0),
                radius: notchVM.isOpen ? 20 : 0,
                x: 0, y: notchVM.isOpen ? 6 : 0
            )

            // nothing here — glow applied outside clip

            // Braille thinking spinner — visible in closed notch, right side
            if notchVM.isThinkingClosed {
                HStack {
                    Spacer()
                    BrailleSpinner()
                        .padding(.trailing, 12)
                }
                .padding(.top, 6)
            }

            if notchVM.isOpen {
                if onboardingVM.needsOnboarding {
                    OnboardingContainerView(onboardingVM: onboardingVM)
                        .padding(.top, 36)
                        .padding(.horizontal, 42)
                        .padding(.bottom, 18)
                        .transition(.opacity.animation(.easeIn(duration: 0.12).delay(0.08)))
                } else {
                    VStack(spacing: 0) {
                        if notchVM.isSettingsOpen {
                            settingsTopBar
                        } else if notchVM.isHistoryOpen {
                            settingsTopBar
                        } else if notchVM.isSearchOpen {
                            SearchBarView(searchVM: searchVM) {
                                searchVM.close()
                                notchVM.isSearchOpen = false
                            }
                        } else if notchVM.isRoutinesOpen {
                            settingsTopBar
                        } else if notchVM.isBrainOpen {
                            settingsTopBar
                        } else {
                            notchTopBar
                        }

                        Group {
                            if notchVM.isSettingsOpen {
                                SettingsView(sessionStore: sessionStore, notchVM: notchVM, hermesConfig: hermesConfig)
                                .padding(.top, 14)
                                .padding(.horizontal, 42)
                                .padding(.bottom, 18)
                                .background(Color.white.opacity(0.05))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .padding(.horizontal, 42)
                                .padding(.bottom, 18)
                                .transition(.opacity)
                            } else if notchVM.isRoutinesOpen {
                                RoutinesView(cronStore: cronStore, onSelectJob: { job in
                                    chatVM.setRoutineContext(job)
                                    notchVM.isRoutinesOpen = false
                                }, onSelectTemplate: { draft in
                                    chatVM.draft = draft
                                    notchVM.isRoutinesOpen = false
                                }, onCreateOwn: {
                                    chatVM.draft = "Schedule a new routine: "
                                    notchVM.isRoutinesOpen = false
                                }, onDropFile: { providers in
                                    for provider in providers {
                                        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
                                            guard let data = data as? Data,
                                                  let url = URL(dataRepresentation: data, relativeTo: nil, isAbsolute: true) else { return }
                                            let attachment = DocumentExtractor.extract(from: url)
                                            DispatchQueue.main.async {
                                                chatVM.pendingAttachments.append(attachment)
                                                chatVM.draft = "What routine would make sense for this file?"
                                                chatVM.routineCreationMode = true
                                                notchVM.isRoutinesOpen = false
                                            }
                                        }
                                    }
                                }, onDraftAction: { draft, autoSend in
                                    chatVM.draft = draft
                                    notchVM.isRoutinesOpen = false
                                    if autoSend { chatVM.send() }
                                })
                                .transition(.opacity)
                            } else if notchVM.isHistoryOpen {
                                ConversationHistoryView(chatVM: chatVM, sessionStore: sessionStore, notchVM: notchVM)
                                    .padding(.top, 14)
                                    .padding(.horizontal, 42)
                                    .padding(.bottom, 18)
                                    .background(Color.white.opacity(0.05))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .padding(.horizontal, 42)
                                    .padding(.bottom, 18)
                                    .transition(.opacity)
                            } else if notchVM.isBrainOpen {
                                BrainView(brainVM: brainVM, onSendToChat: { message in
                                    chatVM.draft = message
                                    notchVM.isBrainOpen = false
                                    chatVM.send()
                                })
                                    .padding(.top, 14)
                                    .padding(.horizontal, 42)
                                    .padding(.bottom, 18)
                                    .background(Color.white.opacity(0.05))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .padding(.horizontal, 42)
                                    .padding(.bottom, 18)
                                    .transition(.opacity)
                            } else {
                                ChatView(chatVM: chatVM, notchVM: notchVM, searchVM: searchVM, hermesConfig: hermesConfig)
                                    .padding(.top, 4)
                                    .padding(.horizontal, 42)
                                    .padding(.bottom, 18)
                            }
                        }
                    }
                    .onChange(of: notchVM.isHistoryOpen) { _, isOpen in
                        if isOpen { sessionStore.loadRecentSessions() }
                    }
                    .onChange(of: notchVM.isBrainOpen) { _, isOpen in
                        if isOpen { brainVM.loadIfNeeded() }
                    }
                    .transition(.opacity.animation(.easeIn(duration: 0.12).delay(0.08)))
                }
            }

            if notchVM.isDragTargeted {
                DropOverlay(activeZone: notchVM.activeDropZone)
                    .transition(.opacity)
            }
        }
        .clipShape(
            NotchShape(
                topCornerRadius: notchVM.topCornerRadius,
                bottomCornerRadius: notchVM.bottomCornerRadius
            )
        )
        .overlay(alignment: .top) {
            // Flanking buttons — burger menu beside the hardware notch
            if notchVM.isOpen && !onboardingVM.needsOnboarding {
                HStack {
                    if !notchVM.isAnyPanelOpen {
                        Button {
                            chatVM.startNewConversation()
                        } label: {
                            Image(systemName: "plus.bubble")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.white.opacity(0.4))
                        }
                        .buttonStyle(.plain)
                        .pointingHandCursor()
                    }

                    Spacer()

                    if notchVM.isAnyPanelOpen {
                        Button {
                            notchVM.isSettingsOpen = false
                            notchVM.isRoutinesOpen = false
                            notchVM.isSearchOpen = false
                            notchVM.isHistoryOpen = false
                            notchVM.isBrainOpen = false
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.white.opacity(0.4))
                        }
                        .buttonStyle(.plain)
                        .pointingHandCursor()
                    } else {
                        ZStack(alignment: .trailing) {
                            Image(systemName: "line.3.horizontal")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.25))
                                .opacity(notchVM.isMenuExpanded ? 0 : 1)

                            HStack(spacing: 12) {
                                menuButton("clock.arrow.circlepath") {
                                    notchVM.openHistory()
                                    notchVM.collapseMenu()
                                }
                                menuButton("magnifyingglass") {
                                    notchVM.isSearchOpen = true
                                    notchVM.collapseMenu()
                                }
                                menuButton("arrow.triangle.2.circlepath") {
                                    notchVM.openRoutines()
                                    notchVM.collapseMenu()
                                }
                                menuButton("brain") {
                                    notchVM.openBrain()
                                    notchVM.collapseMenu()
                                }
                                menuButton("gearshape") {
                                    notchVM.isSettingsOpen = true
                                    notchVM.collapseMenu()
                                }
                            }
                            .opacity(notchVM.isMenuExpanded ? 1 : 0)
                            .offset(x: notchVM.isMenuExpanded ? 0 : 8)
                            .allowsHitTesting(notchVM.isMenuExpanded)
                        }
                        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: notchVM.isMenuExpanded)
                        .onHover { hovering in
                            if hovering && !notchVM.isMenuExpanded {
                                notchVM.expandMenu()
                            }
                        }
                    }
                }
                .padding(.horizontal, 42)
                .padding(.top, 6)
                .transition(.opacity.animation(.easeIn(duration: 0.15).delay(0.1)))
            }
        }
    }

    // MARK: - Burger menu icon button

    private func menuButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }

    // MARK: - Settings top bar spacer (buttons moved to flanking overlay)

    private var settingsTopBar: some View {
        Color.clear
            .frame(height: 32)
            .padding(.top, 4)
    }

    // MARK: - Top bar spacer (buttons moved to flanking overlay)

    private var notchTopBar: some View {
        Color.clear
            .frame(height: 32)
            .padding(.top, 4)
    }

}

// MARK: - Recording toast (below closed notch, with action buttons)

struct RecordingToastView: View {
    @ObservedObject var notchVM: NotchViewModel

    var body: some View {
        HStack(spacing: 12) {
            // Blinking red dot
            Circle()
                .fill(AppColors.recordingDot)
                .frame(width: 8, height: 8)
                .modifier(PulsingModifier())

            // Talk button
            Button { notchVM.onTalkAction?() } label: {
                HStack(spacing: 5) {
                    Image(systemName: "text.bubble.fill")
                        .font(.system(size: 10))
                    Text("Talk")
                        .font(.system(size: 11, weight: .semibold))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    LinearGradient(
                        colors: [AppColors.kittViolet, AppColors.accent],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .pointingHandCursor()

            // Brain Dump button
            Button { notchVM.onBrainDumpAction?() } label: {
                HStack(spacing: 5) {
                    Text("🧠")
                        .font(.system(size: 10))
                    Text("Dump")
                        .font(.system(size: 11, weight: .semibold))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.1))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
        }
        .foregroundStyle(.white.opacity(0.9))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.black)
        .clipShape(Capsule())
    }
}

// MARK: - Drop delegate for split drop zones

struct NotchDropDelegate: DropDelegate {
    let notchVM: NotchViewModel
    let chatVM: ChatViewModel
    let notchWidth: CGFloat

    func dropEntered(info: DropInfo) {
        notchVM.isDragTargeted = true
        updateZone(info: info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        updateZone(info: info)
        return DropProposal(operation: .copy)
    }

    func dropExited(info: DropInfo) {
        notchVM.isDragTargeted = false
        notchVM.activeDropZone = .none
    }

    func performDrop(info: DropInfo) -> Bool {
        let zone = notchVM.activeDropZone
        let providers = info.itemProviders(for: [.fileURL])
        guard !providers.isEmpty else { return false }

        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
                guard let data = data as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil, isAbsolute: true)
                else { return }
                let attachment = DocumentExtractor.extract(from: url)
                DispatchQueue.main.async {
                    switch zone {
                    case .left, .none:
                        chatVM.pendingAttachments.append(attachment)
                        if !notchVM.isOpen { notchVM.open() }
                    case .right:
                        chatVM.saveToBrain(content: attachment.textContent, fileName: attachment.fileName)
                    }
                }
            }
        }
        notchVM.isDragTargeted = false
        notchVM.activeDropZone = .none
        return true
    }

    private func updateZone(info: DropInfo) {
        notchVM.activeDropZone = info.location.x < notchWidth / 2.0 ? .left : .right
    }
}

// MARK: - Recording pulse (closed notch glows purple)

struct KITTScanner: View {
    let width: CGFloat

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let now = timeline.date.timeIntervalSinceReferenceDate
                // Smooth ping-pong: 0→1→0 over ~1.6s
                let cycle = now.truncatingRemainder(dividingBy: 1.6) / 1.6
                let pos = CGFloat(1.0 - abs(cycle * 2.0 - 1.0))
                // Ease in-out
                let eased = pos * pos * (3.0 - 2.0 * pos)

                let centerX = 20 + eased * (size.width - 40)

                // Draw multiple layers for diffuse glow
                let layers: [(CGFloat, Double)] = [
                    (80, 0.06),  // wide ambient
                    (50, 0.12),  // medium glow
                    (30, 0.25),  // inner glow
                    (14, 0.5),   // bright core
                    (6,  0.9),   // hot center
                ]

                let violet = AppColors.kittViolet

                for (spread, alpha) in layers {
                    let rect = CGRect(
                        x: centerX - spread / 2,
                        y: (size.height - 6) / 2,
                        width: spread,
                        height: 6
                    )
                    context.fill(
                        Path(roundedRect: rect, cornerRadius: 3),
                        with: .color(violet.opacity(alpha))
                    )
                }

                // Diffuse tail — fills most of the line with a fading glow
                let direction: CGFloat = cycle < 0.5 ? 1 : -1
                let tailSteps = 30
                let tailReach: CGFloat = size.width * 0.7
                for i in 1...tailSteps {
                    let frac = CGFloat(i) / CGFloat(tailSteps)
                    let tailX = centerX - direction * tailReach * frac
                    let alpha = 0.2 * Double((1.0 - frac) * (1.0 - frac))
                    let spread: CGFloat = 12 + 40 * frac
                    let h: CGFloat = 6 * (1.0 - frac * 0.5)
                    let rect = CGRect(
                        x: tailX - spread / 2,
                        y: (size.height - h) / 2,
                        width: spread,
                        height: h
                    )
                    context.fill(
                        Path(roundedRect: rect, cornerRadius: 3),
                        with: .color(violet.opacity(alpha))
                    )
                }

                // Subtle ambient baseline across the full line
                let baseLine = CGRect(x: 0, y: (size.height - 2) / 2, width: size.width, height: 2)
                context.fill(
                    Path(roundedRect: baseLine, cornerRadius: 1),
                    with: .color(violet.opacity(0.06))
                )
            }
        }
        .frame(width: width, height: 8)
    }
}

struct BrailleSpinner: View {
    private static let frames: [String] = ["⠋","⠙","⠹","⠸","⠼","⠴","⠦","⠧","⠇","⠏"]
    var size: CGFloat = 14
    var color: Color = AppColors.accent

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.08)) { timeline in
            let idx = Int(timeline.date.timeIntervalSinceReferenceDate / 0.08) % Self.frames.count
            Text(Self.frames[idx])
                .font(.system(size: size, weight: .medium, design: .monospaced))
                .foregroundStyle(color)
        }
    }
}

struct PulsingModifier: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .opacity(isPulsing ? 0.3 : 1.0)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPulsing)
            .onAppear { isPulsing = true }
    }
}

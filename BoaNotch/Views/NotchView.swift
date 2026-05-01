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
    @ObservedObject var loginItemService: LoginItemService
    @ObservedObject var appearanceSettings: AppearanceSettings
    @ObservedObject var panelSizeStore: PanelSizeStore
    @ObservedObject var titleStore: TitleStore

    @AppStorage("hasCompletedBrainOnboarding") private var hasCompletedBrainOnboarding = false
    @State private var didEvaluateBrainOnboarding = false
    @State private var showBrainOnboarding = false
    @State private var hoverResize = false

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
                    ToastView(message: msg, notchWidth: notchVM.closedSize.width, kind: notchVM.toastKind ?? .info)
                        .padding(.top, 8)
                        .transition(.asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal: .opacity
                        ))
                        .onTapGesture {
                            if let pending = notchVM.pendingCronOutput {
                                notchVM.pendingCronOutput = nil
                                chatVM.messages.append(ChatMessage(
                                    role: .assistant,
                                    content: "**\(pending.jobName)**\n\n\(pending.fullContent)",
                                    routineId: pending.jobId
                                ))
                            }
                            notchVM.open()
                        }
                }

            }
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .top
        )
        .onAppear {
            if !onboardingVM.needsOnboarding
                && !hasCompletedBrainOnboarding
                && Self.wikiHasNoMarkdown
                && !didEvaluateBrainOnboarding {
                didEvaluateBrainOnboarding = true
                showBrainOnboarding = true
            }
        }
        .onChange(of: onboardingVM.needsOnboarding) { _, needsIt in
            if !needsIt
                && !hasCompletedBrainOnboarding
                && Self.wikiHasNoMarkdown
                && !didEvaluateBrainOnboarding {
                didEvaluateBrainOnboarding = true
                showBrainOnboarding = true
            }
        }
        .sheet(isPresented: $showBrainOnboarding) {
            BrainOnboardingView(chatVM: chatVM)
        }
    }

    private static var wikiHasNoMarkdown: Bool {
        let path = NSString(string: "~/.hermes/brain/wiki").expandingTildeInPath
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
            return true
        }
        let contents = (try? fm.contentsOfDirectory(atPath: path)) ?? []
        return !contents.contains { $0.hasSuffix(".md") }
    }

    private var notchBody: some View {
        ZStack {
            // Closed = solid black (camouflages hardware notch).
            // Open on macOS 26+ = top-down gradient from black to Liquid Glass.
            // Open on macOS 14/15/25 = solid black (fallback identical to closed).
            Color.clear
                .notchPanelBackground(
                    top: notchVM.topCornerRadius,
                    bottom: notchVM.bottomCornerRadius,
                    isOpen: notchVM.isOpen
                )
                .clipShape(
                    NotchShape(
                        topCornerRadius: notchVM.topCornerRadius,
                        bottomCornerRadius: notchVM.bottomCornerRadius
                    )
                )
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
                        } else if notchVM.isBrainOpen {
                            settingsTopBar
                        } else {
                            notchTopBar
                        }

                        Group {
                            if notchVM.isSettingsOpen {
                                SettingsView(sessionStore: sessionStore, notchVM: notchVM, hermesConfig: hermesConfig, loginItemService: loginItemService, appearanceSettings: appearanceSettings)
                                .padding(.top, 14)
                                .padding(.horizontal, 42)
                                .padding(.bottom, 18)
                                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.black.opacity(0.45)))
                                .padding(.horizontal, 42)
                                .padding(.bottom, 25)
                                .transition(.opacity)
                            } else if notchVM.isHistoryOpen {
                                ConversationHistoryView(chatVM: chatVM, sessionStore: sessionStore, notchVM: notchVM, titleStore: titleStore)
                                    .padding(.top, 14)
                                    .padding(.horizontal, 42)
                                    .padding(.bottom, 18)
                                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.black.opacity(0.45)))
                                    .padding(.horizontal, 42)
                                    .padding(.bottom, 25)
                                    .transition(.opacity)
                            } else if notchVM.isBrainOpen {
                                BrainView(
                                    brainVM: brainVM,
                                    chatVM: chatVM,
                                    notchVM: notchVM,
                                    onSendToChat: { message in
                                        chatVM.draft = message
                                        notchVM.isBrainOpen = false
                                        chatVM.send()
                                    },
                                    onPrefillChat: { message in
                                        chatVM.draft = message
                                        notchVM.isBrainOpen = false
                                        chatVM.focusComposerTrigger = UUID()
                                    },
                                    tasksContent: { AnyView(routinesEmbedded) }
                                )
                                    .padding(.top, 14)
                                    .padding(.horizontal, 42)
                                    .padding(.bottom, 18)
                                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.black.opacity(0.45)))
                                    .padding(.horizontal, 42)
                                    .padding(.bottom, 25)
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
            // Flanking buttons — persistent top bar beside the hardware notch
            if notchVM.isOpen && !onboardingVM.needsOnboarding {
                HStack(spacing: 10) {
                    // Left slot — context-dependent: brain tabs / panel title / left burger
                    leftSlot

                    Spacer(minLength: 8)

                    rightCluster
                }
                .padding(.horizontal, 42)
                .padding(.top, 10)
                .animation(.easeInOut(duration: 0.18), value: panelTitle)
                .transition(.opacity.animation(.easeIn(duration: 0.15).delay(0.1)))
            }
        }
    }

    // MARK: - Right cluster (Settings + Brain/Tools/Tasks burger + resize)

    @ViewBuilder
    private var rightCluster: some View {
        // Fan icons appear when the menu is hovered open OR when a right-side
        // panel is open (so the user can switch tabs without re-hovering).
        let iconsVisible = notchVM.isMenuExpanded || notchVM.isRightPanelOpen
        // The X morph is the only way to close ANY panel (left or right) —
        // see "Right burger owns the X" in CLAUDE.md.
        let showX = notchVM.isAnyPanelOpen || notchVM.isMenuExpanded
        // Read once so the closures below capture the current activeTab value.
        let activeTab = brainVM.activeTab

        HStack(spacing: 8) {
            if iconsVisible {
                // Order left -> right: settings, Brain, Tools, Tasks.
                // Burger/X sits at the rightmost edge so the fan opens leftward
                // toward the center of the top bar.
                menuButton("gearshape", active: notchVM.isSettingsOpen) {
                    if notchVM.isSettingsOpen {
                        notchVM.closeAllPanels()
                    } else {
                        notchVM.openSettings()
                        notchVM.collapseMenu()
                    }
                }
                menuButton("person", active: notchVM.isBrainOpen && activeTab == .brain) {
                    if notchVM.isBrainOpen && activeTab == .brain {
                        notchVM.closeAllPanels()
                    } else {
                        notchVM.openBrain()
                        brainVM.activeTab = .brain
                        notchVM.collapseMenu()
                    }
                }
                // +2pt visual-balance: this glyph packs 4 sub-shapes inside a square and reads ~2pt
                // smaller than its 14pt peers (book / gearshape / checkmark.rectangle.stack).
                menuButton("xmark.triangle.circle.square", active: notchVM.isBrainOpen && activeTab == .tools, sizeBoost: 2) {
                    if notchVM.isBrainOpen && activeTab == .tools {
                        notchVM.closeAllPanels()
                    } else {
                        notchVM.openBrain()
                        brainVM.activeTab = .tools
                        notchVM.collapseMenu()
                    }
                }
                menuButton("checkmark.rectangle.stack", active: notchVM.isBrainOpen && activeTab == .tasks) {
                    if notchVM.isBrainOpen && activeTab == .tasks {
                        notchVM.closeAllPanels()
                    } else {
                        notchVM.openBrain()
                        brainVM.activeTab = .tasks
                        notchVM.collapseMenu()
                    }
                }
            }

            // Burger ↔ X morph (same slot)
            Button {
                if notchVM.isAnyPanelOpen {
                    notchVM.closeAllPanels()
                } else if notchVM.isMenuExpanded {
                    notchVM.collapseMenu()
                } else {
                    notchVM.expandMenu()
                }
            } label: {
                Image(systemName: showX ? "xmark" : "ellipsis")
                    .font(DS.Icon.topBar)
                    .frame(height: 13)
                    .foregroundStyle(showX ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.white.opacity(0.20)))
                    .contentTransition(.symbolEffect(.replace))
                    .drawOnAppear()
            }
            .buttonStyle(.plain)
            .pointingHandCursor()

            // Resize panel size (always visible)
            Button {
                panelSizeStore.size = (panelSizeStore.size == .standard) ? .large : .standard
            } label: {
                Image(systemName: panelSizeStore.size == .standard
                      ? "arrow.up.left.and.arrow.down.right"
                      : "arrow.down.right.and.arrow.up.left")
                    .font(DS.Icon.topBar)
                    .frame(height: 13)
                    .foregroundStyle(hoverResize ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.white.opacity(0.20)))
                    .drawOnAppear()
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            .onHover { hoverResize = $0 }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: iconsVisible)
        .onHover { hovering in
            guard !notchVM.isRightPanelOpen else { return }
            if hovering {
                if notchVM.isMenuExpanded {
                    notchVM.cancelMenuCollapse()
                } else {
                    notchVM.expandMenu()
                }
            } else {
                notchVM.scheduleMenuCollapse(after: 0.6)
            }
        }
    }

    // MARK: - Left cluster (chat-icon burger: new convo + history + search)

    @ViewBuilder
    private var leftCluster: some View {
        // The trio (search · new · history) REPLACES the burger glyph on hover —
        // they never coexist, so the leftmost trio icon can't be misclicked into
        // the burger. Hover-out collapses after 0.6s; the right burger still owns
        // the X (see CLAUDE.md).
        let isDeployed = notchVM.isLeftMenuExpanded

        HStack(spacing: 8) {
            if isDeployed {
                // Search leads (user choice 2026-05-02). Order: search · new · history.
                menuButton("magnifyingglass", active: notchVM.isSearchOpen) {
                    if notchVM.isSearchOpen {
                        notchVM.closeAllPanels()
                    } else {
                        notchVM.openSearch()
                        notchVM.collapseLeftMenu()
                    }
                }
                menuButton("plus.bubble", active: false) {
                    chatVM.startNewConversation()
                    notchVM.collapseLeftMenu()
                }
                menuButton("book", active: notchVM.isHistoryOpen) {
                    if notchVM.isHistoryOpen {
                        notchVM.closeAllPanels()
                    } else {
                        notchVM.openHistory()
                        notchVM.collapseLeftMenu()
                    }
                }
            } else {
                Button {
                    notchVM.expandLeftMenu()
                } label: {
                    Image(systemName: "rectangle.3.group.bubble")
                        .font(DS.Icon.topBar)
                        .frame(height: 13)
                        .foregroundStyle(Color.white.opacity(0.20))
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
                .drawOnAppear()
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isDeployed)
        .onHover { hovering in
            if hovering {
                if notchVM.isLeftMenuExpanded {
                    notchVM.cancelLeftMenuCollapse()
                } else {
                    notchVM.expandLeftMenu()
                }
            } else {
                notchVM.scheduleLeftMenuCollapse(after: 0.6)
            }
        }
    }

    private var panelTitle: String? {
        if notchVM.isHistoryOpen { return "Conversations" }
        if notchVM.isSettingsOpen { return "Settings" }
        if notchVM.isSearchOpen { return "Search" }
        if notchVM.isBrainOpen { return brainVM.activeTab.rawValue }
        return nil
    }

    @ViewBuilder
    private var leftSlot: some View {
        if let title = panelTitle {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(1)
        } else {
            leftCluster
        }
    }

    // MARK: - Burger menu icon button

    private func menuButton(_ icon: String, active: Bool = false, sizeBoost: CGFloat = 0, action: @escaping () -> Void) -> some View {
        // Base aligned on DS.Icon.topBar (13pt) so action icons match the burger glyphs and resize.
        // sizeBoost is a per-icon visual-balance override — not a new design tier.
        let size: CGFloat = 13 + sizeBoost
        return Button(action: action) {
            Image(systemName: icon)
                .symbolVariant(active ? .fill : .none)
                // TODO(design): poids conditionnel actif=semibold/inactif=medium ; DS.Icon.secondary fixe medium, on garde le ternaire pour l'affordance d'état
                .font(.system(size: size, weight: active ? .semibold : .medium))
                .foregroundStyle(active ? AnyShapeStyle(AppColors.accent) : AnyShapeStyle(.secondary))
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .drawOnAppear()
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

    // MARK: - Routines embedded inside Brain panel's Tasks tab

    /// `RoutinesView` wired with callbacks that close the Brain panel after
    /// a selection (replaces the deprecated standalone Routines panel).
    private var routinesEmbedded: some View {
        RoutinesView(
            cronStore: cronStore,
            panelSize: panelSizeStore.size,
            onSelectJob: { job in
                chatVM.setRoutineContext(job)
                notchVM.isBrainOpen = false
            },
            onSelectTemplate: { draft in
                chatVM.draft = draft
                notchVM.isBrainOpen = false
            },
            onCreateOwn: {
                chatVM.draft = "Schedule a new routine: "
                notchVM.isBrainOpen = false
            },
            onDropFile: { providers in
                for provider in providers {
                    provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
                        guard let data = data as? Data,
                              let url = URL(dataRepresentation: data, relativeTo: nil, isAbsolute: true) else { return }
                        let attachment = DocumentExtractor.extract(from: url)
                        DispatchQueue.main.async {
                            chatVM.pendingAttachments.append(attachment)
                            chatVM.draft = "What routine would make sense for this file?"
                            chatVM.routineCreationMode = true
                            notchVM.isBrainOpen = false
                        }
                    }
                }
            },
            onDraftAction: { draft, autoSend in
                chatVM.draft = draft
                notchVM.isBrainOpen = false
                if autoSend { chatVM.send() }
            },
            onCreateCustomRoutine: { draft in
                chatVM.createRoutine(draft: draft)
            },
            onSetPaused: { job, paused in
                chatVM.setRoutinePaused(job, paused: paused)
            },
            onUpdateRoutine: { id, patch in
                chatVM.updateRoutine(jobId: id, patch: patch)
            }
        )
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
                        .font(DS.Text.micro)
                    Text("Talk")
                        .font(.caption.weight(.semibold))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    LinearGradient(
                        colors: [AppColors.kittDeep, AppColors.accent],
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
                        .font(.caption2)
                    Text("Dump")
                        .font(.caption.weight(.semibold))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(.quaternary))
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .nnGlass(in: Capsule())
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

// MARK: - Recording pulse (closed notch glow)

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

                let deep = AppColors.kittDeep

                for (spread, alpha) in layers {
                    let rect = CGRect(
                        x: centerX - spread / 2,
                        y: (size.height - 6) / 2,
                        width: spread,
                        height: 6
                    )
                    context.fill(
                        Path(roundedRect: rect, cornerRadius: 3),
                        with: .color(deep.opacity(alpha))
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
                        with: .color(deep.opacity(alpha))
                    )
                }

                // Subtle ambient baseline across the full line
                let baseLine = CGRect(x: 0, y: (size.height - 2) / 2, width: size.width, height: 2)
                context.fill(
                    Path(roundedRect: baseLine, cornerRadius: 1),
                    with: .color(deep.opacity(0.06))
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
                // TODO(design): taille paramétrique (size CGFloat), token DS.Text.* fixe non applicable
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

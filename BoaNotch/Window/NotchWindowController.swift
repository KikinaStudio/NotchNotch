import AppKit
import Combine
import SwiftUI

class NotchWindowController {
    private var panel: NotchPanel?
    private let chatVM: ChatViewModel
    private let notchVM: NotchViewModel
    private var dragMonitor: Any?
    private var dragEndMonitor: Any?
    private var sizeCancellable: AnyCancellable?
    private var onboardingCancellable: AnyCancellable?

    static let shadowPadding: CGFloat = 20

    /// Panel dimensions per size variant. Uses visibleFrame to stay inside the
    /// menu-bar / Dock reserved area on small screens.
    static func dimensions(for size: PanelSize, on screen: NSScreen) -> CGSize {
        switch size {
        case .standard:
            return CGSize(width: 680, height: 380)
        case .large:
            let visible = screen.visibleFrame
            return CGSize(
                width: min(900, visible.width * 0.9),
                height: min(600, visible.height * 0.8)
            )
        }
    }

    /// The visible black notch size is the panel size minus the invisible
    /// shadow padding on each side. Keep this invariant: `openSize` tracks the
    /// panel size, never diverges.
    static func openSize(for size: PanelSize, on screen: NSScreen) -> CGSize {
        let panel = dimensions(for: size, on: screen)
        return CGSize(
            width: panel.width - 2 * shadowPadding,
            height: panel.height - 2 * shadowPadding
        )
    }

    private let sessionStore: SessionStore
    private let searchVM: SearchViewModel
    private let hermesConfig: HermesConfig
    private let onboardingVM: OnboardingViewModel
    private let cronStore: CronStore
    private let brainVM: BrainViewModel
    private let loginItemService: LoginItemService
    private let appearanceSettings: AppearanceSettings
    private let panelSizeStore: PanelSizeStore
    private let titleStore: TitleStore

    init(chatVM: ChatViewModel, notchVM: NotchViewModel, sessionStore: SessionStore, searchVM: SearchViewModel, hermesConfig: HermesConfig, onboardingVM: OnboardingViewModel, cronStore: CronStore, brainVM: BrainViewModel, loginItemService: LoginItemService, appearanceSettings: AppearanceSettings, panelSizeStore: PanelSizeStore, titleStore: TitleStore) {
        self.chatVM = chatVM
        self.notchVM = notchVM
        self.sessionStore = sessionStore
        self.searchVM = searchVM
        self.hermesConfig = hermesConfig
        self.onboardingVM = onboardingVM
        self.cronStore = cronStore
        self.brainVM = brainVM
        self.loginItemService = loginItemService
        self.appearanceSettings = appearanceSettings
        self.panelSizeStore = panelSizeStore
        self.titleStore = titleStore

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        // `@Published` emits in willSet — the stored property is still the old
        // value at sink time. `receive(on: .main)` defers to the next runloop
        // tick so `applyPanelSize` reads the up-to-date `panelSizeStore.size`.
        // Without this, the first toggle resizes to the OLD size (a no-op) and
        // the icon/panel state drift out of sync.
        sizeCancellable = panelSizeStore.$size
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.applyPanelSize(animated: true)
            }

        // Onboarding forces .standard regardless of user preference. When
        // `needsOnboarding` flips to false (Ready → Start chatting), restore
        // the user's preferred size.
        onboardingCancellable = onboardingVM.$needsOnboarding
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.applyPanelSize(animated: true)
            }
    }

    /// During onboarding the panel is forced to `.standard` (the size
    /// onboarding screens are designed for) even if the user has saved a
    /// `.large` preference. After `completeOnboarding()`, the stored
    /// preference takes over.
    private func effectivePanelSize() -> PanelSize {
        onboardingVM.needsOnboarding ? .standard : panelSizeStore.size
    }

    func showPanel() {
        guard let screen = Self.notchScreen() else { return }

        let closedSize = Self.closedNotchSize(for: screen)
        notchVM.closedSize = closedSize

        let initialPanelSize = Self.dimensions(for: effectivePanelSize(), on: screen)
        notchVM.openSize = Self.openSize(for: effectivePanelSize(), on: screen)

        let panelRect = NSRect(origin: .zero, size: initialPanelSize)
        let panel = NotchPanel(contentRect: panelRect)

        let rootView = NotchView(chatVM: chatVM, notchVM: notchVM, sessionStore: sessionStore, searchVM: searchVM, hermesConfig: hermesConfig, onboardingVM: onboardingVM, cronStore: cronStore, brainVM: brainVM, loginItemService: loginItemService, appearanceSettings: appearanceSettings, panelSizeStore: panelSizeStore, titleStore: titleStore)
            .environmentObject(appearanceSettings)
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.frame = panel.contentView!.bounds
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView?.addSubview(hostingView)

        self.panel = panel
        applyPanelSize(animated: false)

        notchVM.onStateChange = { [weak self] state in
            guard let panel = self?.panel else { return }
            switch state {
            case .open:
                panel.isNotchOpen = true
                panel.makeKey()
            case .closed, .toast, .clipperToast:
                panel.isNotchOpen = false
                panel.resignKey()
            }
        }

        panel.orderFrontRegardless()
        setupDragMonitor(for: screen)
    }

    // MARK: - Global drag monitor

    /// Monitors system-wide drag events. When a file drag enters the notch region, opens the notch.
    private func setupDragMonitor(for screen: NSScreen) {
        let notchWidth = Self.closedNotchSize(for: screen).width + 100
        let screenFrame = screen.frame

        dragMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] event in
            guard let self else { return }
            let mouseLocation = NSEvent.mouseLocation
            let mouseFromTop = screenFrame.maxY - mouseLocation.y

            let inNotchRegion = abs(mouseLocation.x - screenFrame.midX) < notchWidth / 2
                && mouseFromTop < 80

            DispatchQueue.main.async {
                if inNotchRegion && !self.notchVM.isOpen {
                    self.notchVM.isDragTargeted = true
                    self.notchVM.open()
                }
            }
        }

        // When mouse button is released, clear drag state
        dragEndMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in
            guard let self else { return }
            DispatchQueue.main.async {
                if self.notchVM.isDragTargeted {
                    self.notchVM.isDragTargeted = false
                }
            }
        }
    }

    /// Sizes and positions the panel for the current stored PanelSize.
    /// Called on showPanel(), screenDidChange(), and whenever the user toggles size.
    func applyPanelSize(animated: Bool = true) {
        guard let panel, let screen = Self.notchScreen() else { return }
        let newPanelSize = Self.dimensions(for: effectivePanelSize(), on: screen)
        let newOpenSize = Self.openSize(for: effectivePanelSize(), on: screen)
        let screenFrame = screen.frame
        let x = screenFrame.origin.x + (screenFrame.width / 2) - (newPanelSize.width / 2)
        let y = screenFrame.origin.y + screenFrame.height - newPanelSize.height
        let newFrame = NSRect(x: x, y: y, width: newPanelSize.width, height: newPanelSize.height)

        if !animated {
            notchVM.openSize = newOpenSize
            panel.setFrame(newFrame, display: true, animate: false)
            return
        }

        // Grow panel first (so SwiftUI content doesn't clip), then animate the shape;
        // Shrink the shape first, then tighten the panel once the spring settles.
        let isGrowing = newPanelSize.width > panel.frame.size.width

        if isGrowing {
            panel.setFrame(newFrame, display: true, animate: false)
            withAnimation(.interactiveSpring(response: 0.42, dampingFraction: 0.8, blendDuration: 0)) {
                self.notchVM.openSize = newOpenSize
            }
        } else {
            withAnimation(.interactiveSpring(response: 0.42, dampingFraction: 0.8, blendDuration: 0)) {
                self.notchVM.openSize = newOpenSize
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak panel] in
                panel?.setFrame(newFrame, display: true, animate: false)
            }
        }
    }

    @objc private func screenDidChange() {
        guard let screen = Self.notchScreen() else { return }
        let closedSize = Self.closedNotchSize(for: screen)
        notchVM.closedSize = closedSize
        applyPanelSize(animated: false)
    }

    static func notchScreen() -> NSScreen? {
        for screen in NSScreen.screens where screen.safeAreaInsets.top > 0 {
            return screen
        }
        return NSScreen.main
    }

    static func closedNotchSize(for screen: NSScreen) -> CGSize {
        var width: CGFloat = 185
        var height: CGFloat = 32

        if let leftPadding = screen.auxiliaryTopLeftArea?.width,
           let rightPadding = screen.auxiliaryTopRightArea?.width {
            width = screen.frame.width - leftPadding - rightPadding + 4
        }

        if screen.safeAreaInsets.top > 0 {
            height = screen.safeAreaInsets.top
        }

        return CGSize(width: width, height: height)
    }

    deinit {
        if let dragMonitor { NSEvent.removeMonitor(dragMonitor) }
        if let dragEndMonitor { NSEvent.removeMonitor(dragEndMonitor) }
    }
}

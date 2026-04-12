import AppKit
import SwiftUI

class NotchWindowController {
    private var panel: NotchPanel?
    private let chatVM: ChatViewModel
    private let notchVM: NotchViewModel
    private var dragMonitor: Any?
    private var dragEndMonitor: Any?

    // Fixed panel size — never changes, like BoringNotch
    static let panelWidth: CGFloat = 680
    static let panelHeight: CGFloat = 380
    static let shadowPadding: CGFloat = 20

    private let sessionStore: SessionStore
    private let searchVM: SearchViewModel
    private let hermesConfig: HermesConfig
    private let onboardingVM: OnboardingViewModel
    private let cronStore: CronStore

    init(chatVM: ChatViewModel, notchVM: NotchViewModel, sessionStore: SessionStore, searchVM: SearchViewModel, hermesConfig: HermesConfig, onboardingVM: OnboardingViewModel, cronStore: CronStore) {
        self.chatVM = chatVM
        self.notchVM = notchVM
        self.sessionStore = sessionStore
        self.searchVM = searchVM
        self.hermesConfig = hermesConfig
        self.onboardingVM = onboardingVM
        self.cronStore = cronStore

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    func showPanel() {
        guard let screen = Self.notchScreen() else { return }

        let closedSize = Self.closedNotchSize(for: screen)
        notchVM.closedSize = closedSize

        let panelRect = NSRect(
            origin: .zero,
            size: CGSize(width: Self.panelWidth, height: Self.panelHeight)
        )

        let panel = NotchPanel(contentRect: panelRect)

        let rootView = NotchView(chatVM: chatVM, notchVM: notchVM, sessionStore: sessionStore, searchVM: searchVM, hermesConfig: hermesConfig, onboardingVM: onboardingVM, cronStore: cronStore)
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.frame = panel.contentView!.bounds
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView?.addSubview(hostingView)

        self.panel = panel
        positionPanel(on: screen)

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

    private func positionPanel(on screen: NSScreen) {
        guard let panel else { return }
        let screenFrame = screen.frame
        let w = Self.panelWidth
        let h = Self.panelHeight

        let x = screenFrame.origin.x + (screenFrame.width / 2) - (w / 2)
        let y = screenFrame.origin.y + screenFrame.height - h

        panel.setFrame(NSRect(x: x, y: y, width: w, height: h), display: true)
    }

    @objc private func screenDidChange() {
        guard let screen = Self.notchScreen() else { return }
        let closedSize = Self.closedNotchSize(for: screen)
        notchVM.closedSize = closedSize
        positionPanel(on: screen)
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

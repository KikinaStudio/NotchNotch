import AppKit
import SwiftUI

class NotchWindowController {
    private var panel: NotchPanel?
    private let chatVM: ChatViewModel
    private let notchVM: NotchViewModel

    // Fixed panel size — never changes, like BoringNotch
    // Wide enough for the open state (640pt), tall enough for chat + shadow padding
    static let panelWidth: CGFloat = 640
    static let panelHeight: CGFloat = 560  // chat open height
    static let shadowPadding: CGFloat = 20

    init(chatVM: ChatViewModel, notchVM: NotchViewModel) {
        self.chatVM = chatVM
        self.notchVM = notchVM

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

        let rootView = NotchView(chatVM: chatVM, notchVM: notchVM)
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
            case .closed, .toast:
                panel.isNotchOpen = false
                panel.resignKey()
            }
        }

        panel.orderFrontRegardless()
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

    /// Calculate the exact hardware notch dimensions using macOS APIs
    static func closedNotchSize(for screen: NSScreen) -> CGSize {
        var width: CGFloat = 185
        var height: CGFloat = 32

        // Use auxiliaryTopLeftArea / TopRightArea to get exact notch width
        if let leftPadding = screen.auxiliaryTopLeftArea?.width,
           let rightPadding = screen.auxiliaryTopRightArea?.width {
            width = screen.frame.width - leftPadding - rightPadding + 4
        }

        if screen.safeAreaInsets.top > 0 {
            height = screen.safeAreaInsets.top
        }

        return CGSize(width: width, height: height)
    }
}

import AppKit

class NotchPanel: NSPanel {
    var isNotchOpen: Bool = false

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel, .utilityWindow, .hudWindow],
            backing: .buffered,
            defer: false
        )

        level = .mainMenu + 3
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        isMovableByWindowBackground = false
        acceptsMouseMovedEvents = true

        collectionBehavior = [
            .fullScreenAuxiliary,
            .stationary,
            .canJoinAllSpaces,
            .ignoresCycle
        ]
    }

    override var canBecomeKey: Bool {
        return isNotchOpen
    }

    override var canBecomeMain: Bool {
        return false
    }
}

extension NSOpenPanel {
    /// Configures this panel to float above NotchPanel and activates the app
    /// so the picker receives keyboard focus. Call before `.begin { ... }`.
    func presentAboveNotch() {
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 4)
        NSApp.activate(ignoringOtherApps: true)
    }
}

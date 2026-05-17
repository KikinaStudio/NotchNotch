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

extension NotchPanel {
    /// Temporarily drops every NotchPanel window level to `.normal` so a
    /// system TCC prompt (mic, speech recognition, Accessibility, etc.)
    /// renders ABOVE the notch instead of being hidden behind our
    /// `.mainMenu + 3` panel. Restores `.mainMenu + 3` after the block.
    /// `NSApp.activate(ignoringOtherApps:)` mirrors the `presentAboveNotch`
    /// pattern so the prompt receives keyboard focus.
    ///
    /// No-op overhead when the OS doesn't actually present a prompt (already
    /// authorized / already denied) — the block returns instantly.
    @MainActor
    static func withLoweredLevel<T>(_ block: () async -> T) async -> T {
        let panels = NSApp.windows.compactMap { $0 as? NotchPanel }
        for p in panels { p.level = .normal }
        NSApp.activate(ignoringOtherApps: true)
        let result = await block()
        for p in panels { p.level = .mainMenu + 3 }
        return result
    }
}

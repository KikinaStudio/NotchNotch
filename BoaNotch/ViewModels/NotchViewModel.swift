import SwiftUI

enum NotchState: Equatable {
    case closed
    case open
    case toast(String)
    case clipperToast(String)  // brain dump toast with pacman icon
}

enum DropZone {
    case none, left, right
}

class NotchViewModel: ObservableObject {
    @Published var state: NotchState = .closed
    @Published var isDragTargeted = false
    @Published var activeDropZone: DropZone = .none
    @Published var isRecording = false
    @Published var isSettingsOpen = false
    @Published var isSearchOpen = false
    @Published var isRoutinesOpen = false
    @Published var isExpandedBarOpen = false
    @Published var suppressAutoClose = false
    @Published var isMenuExpanded: Bool = false

    /// The exact hardware notch dimensions, set by NotchWindowController at launch
    @Published var closedSize: CGSize = CGSize(width: 185, height: 32)

    /// The fully open size for chat — wide and compact
    let openSize: CGSize = CGSize(width: 640, height: 340)

    var onStateChange: ((NotchState) -> Void)?

    /// Action closures wired by AppDelegate for recording toast buttons
    var onTalkAction: (() -> Void)?
    var onBrainDumpAction: (() -> Void)?

    private var hoverTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?
    private var menuCollapseTask: Task<Void, Never>?

    var isOpen: Bool { state == .open }
    var isClosed: Bool { state == .closed }

    var isToastVisible: Bool {
        switch state {
        case .toast, .clipperToast: return true
        default: return false
        }
    }

    var toastMessage: String? {
        switch state {
        case .toast(let msg), .clipperToast(let msg): return msg
        default: return nil
        }
    }

    var isClipperToast: Bool {
        if case .clipperToast = state { return true }
        return false
    }

    // MARK: - Current animated size

    /// Whether to show the thinking indicator on the closed notch
    var isThinkingClosed: Bool {
        !isOpen && isStreaming
    }

    @Published var isHistoryOpen = false
    @Published var isBrainOpen = false

    var isAnyPanelOpen: Bool {
        isSettingsOpen || isSearchOpen || isRoutinesOpen || isHistoryOpen || isBrainOpen
    }

    @Published var isStreaming = false

    /// When set, a tap on the current toast expands the output into chat.
    /// Cleared whenever a new toast replaces it or the chat consumes it.
    var pendingCronOutput: (jobName: String, fullContent: String)?

    var currentWidth: CGFloat {
        if isOpen { return openSize.width }
        return isThinkingClosed ? closedSize.width + 36 : closedSize.width
    }

    var currentHeight: CGFloat {
        isOpen ? openSize.height : closedSize.height
    }

    // MARK: - Corner radii (from BoringNotch source)

    var topCornerRadius: CGFloat    { isOpen ? 14 : 6 }
    var bottomCornerRadius: CGFloat { isOpen ? 18 : 10 }

    // MARK: - Hover

    func handleHover(_ hovering: Bool) {
        hoverTask?.cancel()
        if hovering {
            hoverTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                self.open()
            }
        } else {
            hoverTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(600))
                guard !Task.isCancelled else { return }
                if !self.suppressAutoClose { self.close() }
            }
        }
    }

    func handleClick() {
        hoverTask?.cancel()
        isOpen ? close() : open()
    }

    // MARK: - State transitions

    func open() {
        toastTask?.cancel()
        withAnimation(.interactiveSpring(response: 0.42, dampingFraction: 0.8, blendDuration: 0)) {
            state = .open
        }
        onStateChange?(.open)
    }

    func close() {
        isDragTargeted = false
        isMenuExpanded = false
        menuCollapseTask?.cancel()
        withAnimation(.interactiveSpring(response: 0.45, dampingFraction: 1.0, blendDuration: 0)) {
            state = .closed
        }
        onStateChange?(.closed)
    }

    func showToast(_ message: String) {
        toastTask?.cancel()
        pendingCronOutput = nil
        let truncated = String(message.prefix(100))
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            state = .toast(truncated)
        }
        onStateChange?(.toast(truncated))

        toastTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                self.state = .closed
            }
            self.onStateChange?(.closed)
        }
    }

    /// Present a cron-job completion toast. Stores the full content so a tap
    /// can expand it into chat before the auto-dismiss fires.
    func showCronToast(jobName: String, fullContent: String) {
        toastTask?.cancel()
        pendingCronOutput = (jobName, fullContent)
        let firstLine = fullContent
            .split(separator: "\n", maxSplits: 1)
            .first.map(String.init) ?? ""
        let preview = "⚙️ \(jobName): \(firstLine)"
        let truncated = String(preview.prefix(100))
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            state = .toast(truncated)
        }
        onStateChange?(.toast(truncated))

        toastTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                self.state = .closed
            }
            self.onStateChange?(.closed)
        }
    }

    func openRoutines() {
        isRoutinesOpen = true
        isSettingsOpen = false
        isSearchOpen = false
        isHistoryOpen = false
        isBrainOpen = false
    }

    func openHistory() {
        isHistoryOpen = true
        isSettingsOpen = false
        isSearchOpen = false
        isRoutinesOpen = false
        isBrainOpen = false
    }

    func openBrain() {
        isBrainOpen = true
        isSettingsOpen = false
        isSearchOpen = false
        isRoutinesOpen = false
        isHistoryOpen = false
    }

    func closeRoutines() {
        isRoutinesOpen = false
    }

    func expandMenu() {
        isMenuExpanded = true
        menuCollapseTask?.cancel()
        menuCollapseTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                isMenuExpanded = false
            }
        }
    }

    func collapseMenu() {
        menuCollapseTask?.cancel()
        isMenuExpanded = false
    }

    func showClipperToast(_ title: String) {
        toastTask?.cancel()
        pendingCronOutput = nil
        let truncated = String(title.prefix(80))
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            state = .clipperToast(truncated)
        }
        onStateChange?(.clipperToast(truncated))

        toastTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                self.state = .closed
            }
            self.onStateChange?(.closed)
        }
    }

}

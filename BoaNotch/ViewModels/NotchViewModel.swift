import SwiftUI

enum NotchState: Equatable {
    case closed
    case open
    case toast(String, ToastKind)
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
    @Published var isExpandedBarOpen = false
    @Published var suppressAutoClose = false
    @Published var isMenuExpanded: Bool = false
    @Published var isLeftMenuExpanded: Bool = false

    /// The exact hardware notch dimensions, set by NotchWindowController at launch
    @Published var closedSize: CGSize = CGSize(width: 185, height: 32)

    /// The fully open size for chat. Owned by NotchWindowController, which keeps
    /// `openSize == panelSize - 2 * shadowPadding` so the NotchShape always fits
    /// inside the NSPanel. Default value matches the `.standard` panel (680×380)
    /// minus 20pt shadow padding on each side — used only until the controller
    /// runs showPanel() or applyPanelSize().
    @Published var openSize: CGSize = CGSize(width: 640, height: 340)

    var onStateChange: ((NotchState) -> Void)?

    /// Action closures wired by AppDelegate for recording toast buttons
    var onTalkAction: (() -> Void)?
    var onBrainDumpAction: (() -> Void)?

    private var hoverTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?
    private var menuCollapseTask: Task<Void, Never>?
    private var leftMenuCollapseTask: Task<Void, Never>?

    var isOpen: Bool { state == .open }
    var isClosed: Bool { state == .closed }

    var isToastVisible: Bool {
        if case .toast = state { return true }
        return false
    }

    var toastMessage: String? {
        if case .toast(let msg, _) = state { return msg }
        return nil
    }

    var toastKind: ToastKind? {
        if case .toast(_, let kind) = state { return kind }
        return nil
    }

    // MARK: - Current animated size

    /// Whether to show the thinking indicator on the closed notch
    var isThinkingClosed: Bool {
        !isOpen && isStreaming
    }

    @Published var isHistoryOpen = false
    @Published var isBrainOpen = false

    var isAnyPanelOpen: Bool {
        isSettingsOpen || isSearchOpen || isHistoryOpen || isBrainOpen
    }

    /// Panels reachable from the right-side burger (settings + Brain panel
    /// with its Brain/Tools/Tasks tabs). Used to render the right-side X.
    var isRightPanelOpen: Bool {
        isSettingsOpen || isBrainOpen
    }

    /// Panels reachable from the left-side burger (history + search). Used
    /// to render the left-side X.
    var isLeftPanelOpen: Bool {
        isHistoryOpen || isSearchOpen
    }

    @Published var isStreaming = false

    /// When set, a tap on the current toast expands the output into chat.
    /// Cleared whenever a new toast replaces it or the chat consumes it.
    /// `jobId` is carried through so the injected ChatMessage can carry a
    /// stable `routineId` (drives the "Affine" button on the bubble).
    var pendingCronOutput: (jobId: String, jobName: String, fullContent: String)?

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
        // Only open on tap. Missed clicks inside the open panel must NOT close
        // it — that was a frequent frustration. The user can still dismiss via
        // hover-out (handleHover) or the explicit X button.
        if !isOpen { open() }
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
        isLeftMenuExpanded = false
        menuCollapseTask?.cancel()
        leftMenuCollapseTask?.cancel()
        withAnimation(.interactiveSpring(response: 0.45, dampingFraction: 1.0, blendDuration: 0)) {
            state = .closed
        }
        onStateChange?(.closed)
    }

    func showToast(_ message: String, kind: ToastKind = .info) {
        toastTask?.cancel()
        pendingCronOutput = nil
        let truncated = String(message.prefix(100))
        let next: NotchState = .toast(truncated, kind)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            state = next
        }
        onStateChange?(next)

        toastTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(kind.displayDuration))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                self.state = .closed
            }
            self.onStateChange?(.closed)
        }
    }

    /// Present a cron-job completion toast. Stores the full content so a tap
    /// can expand it into chat before the auto-dismiss fires. The `jobId`
    /// rides through end-to-end so the eventual ChatMessage carries a stable
    /// `routineId` (drives the "Affine" button on the bubble).
    func showCronToast(jobId: String, jobName: String, fullContent: String) {
        let firstLine = fullContent
            .split(separator: "\n", maxSplits: 1)
            .first.map(String.init) ?? ""
        let preview = "⚙️ \(jobName): \(firstLine)"
        showToast(preview, kind: .cron)
        // showToast clears pendingCronOutput; reassign after so the tap-to-expand works.
        pendingCronOutput = (jobId, jobName, fullContent)
    }

    func openHistory() {
        isHistoryOpen = true
        isSettingsOpen = false
        isSearchOpen = false
        isBrainOpen = false
    }

    func openBrain() {
        isBrainOpen = true
        isSettingsOpen = false
        isSearchOpen = false
        isHistoryOpen = false
    }

    func openSearch() {
        isSearchOpen = true
        isSettingsOpen = false
        isHistoryOpen = false
        isBrainOpen = false
    }

    func openSettings() {
        isSettingsOpen = true
        isSearchOpen = false
        isHistoryOpen = false
        isBrainOpen = false
    }

    func closeAllPanels() {
        isSettingsOpen = false
        isSearchOpen = false
        isHistoryOpen = false
        isBrainOpen = false
        collapseMenu()
        collapseLeftMenu()
    }

    func expandMenu() {
        isMenuExpanded = true
        scheduleMenuCollapse(after: 3.0)
    }

    func collapseMenu() {
        menuCollapseTask?.cancel()
        isMenuExpanded = false
    }

    /// Cancel any pending auto-collapse — call while the cursor is inside the
    /// menu area so it doesn't disappear while the user is still deciding.
    func cancelMenuCollapse() {
        menuCollapseTask?.cancel()
    }

    /// Schedule (or reschedule) auto-collapse. Default uses the long initial
    /// timeout; pass a shorter delay for the post-hover-out grace window.
    func scheduleMenuCollapse(after seconds: Double = 3.0) {
        menuCollapseTask?.cancel()
        menuCollapseTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                isMenuExpanded = false
            }
        }
    }

    // MARK: - Left burger menu (mirror of right)

    func expandLeftMenu() {
        isLeftMenuExpanded = true
        scheduleLeftMenuCollapse(after: 3.0)
    }

    func collapseLeftMenu() {
        leftMenuCollapseTask?.cancel()
        isLeftMenuExpanded = false
    }

    func cancelLeftMenuCollapse() {
        leftMenuCollapseTask?.cancel()
    }

    func scheduleLeftMenuCollapse(after seconds: Double = 3.0) {
        leftMenuCollapseTask?.cancel()
        leftMenuCollapseTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                isLeftMenuExpanded = false
            }
        }
    }

}

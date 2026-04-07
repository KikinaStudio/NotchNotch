import SwiftUI

enum NotchState: Equatable {
    case closed
    case open
    case toast(String)
    case clipperToast(String)  // brain dump toast with pacman icon
    case awaitingClassification
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

    /// The exact hardware notch dimensions, set by NotchWindowController at launch
    @Published var closedSize: CGSize = CGSize(width: 185, height: 32)

    /// The open width for chat (fixed)
    let openWidth: CGFloat = 580
    /// The open height for chat (dynamic — grows with content or drag)
    @Published var openHeight: CGFloat = 340

    // MARK: - Dynamic height state
    /// nil = auto-grow active. Non-nil = user has dragged, respect their preference.
    var userResizedHeight: CGFloat? = nil
    /// Screen height, set by NotchWindowController at launch.
    var screenHeight: CGFloat = 900

    static let defaultOpenHeight: CGFloat = 340
    static let fixedChromeHeight: CGFloat = 96  // topBar(36) + chatTopPad(4) + inputBar(~32) + chatBottomPad(18) + margin(6)

    var autoGrowMax: CGFloat { screenHeight * 4.0 / 9.0 }
    var dragMin: CGFloat { Self.fixedChromeHeight + 60 }  // 60pt ≈ 3 lines of chat
    var dragMax: CGFloat { screenHeight * 5.0 / 7.0 }

    var onStateChange: ((NotchState) -> Void)?

    /// Transcript waiting for user classification (Talk vs Brain Dump)
    @Published var pendingTranscript: String?

    /// Action closure wired by AppDelegate — called on classification timeout
    var onDiscardAction: (() -> Void)?

    private var hoverTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?

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

    @Published var isStreaming = false

    var currentWidth: CGFloat {
        if isOpen { return openWidth }
        return isThinkingClosed ? closedSize.width + 36 : closedSize.width
    }

    var currentHeight: CGFloat {
        if isOpen {
            return isSettingsOpen ? Self.defaultOpenHeight : openHeight
        }
        return closedSize.height
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
        userResizedHeight = nil
        withAnimation(.interactiveSpring(response: 0.45, dampingFraction: 1.0, blendDuration: 0)) {
            state = .closed
            openHeight = Self.defaultOpenHeight
        }
        onStateChange?(.closed)
    }

    func showToast(_ message: String) {
        toastTask?.cancel()
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

    func showClipperToast(_ title: String) {
        toastTask?.cancel()
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

    // MARK: - Dynamic height

    func updateContentHeight(_ contentHeight: CGFloat) {
        guard userResizedHeight == nil, isOpen, !isSettingsOpen else { return }
        let ideal = Self.fixedChromeHeight + contentHeight
        let clamped = min(ideal, autoGrowMax)
        let floored = max(clamped, Self.defaultOpenHeight)
        if floored > openHeight + 2 {  // only grow, never shrink; ignore micro-updates
            withAnimation(.interactiveSpring(response: 0.3, dampingFraction: 0.85, blendDuration: 0)) {
                openHeight = floored
            }
        }
    }

    /// Apply a drag resize given the height at drag start and current translation.
    /// The view tracks the start height locally so we don't need mutable state here.
    func applyDragResize(startHeight: CGFloat, translation: CGFloat) {
        let newHeight = startHeight + translation
        let clamped = min(max(newHeight, dragMin), dragMax)
        userResizedHeight = clamped
        openHeight = clamped
    }

    // MARK: - Classification (post-recording intent picker)

    func showClassification(transcript: String) {
        toastTask?.cancel()
        pendingTranscript = transcript
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            state = .awaitingClassification
        }
        onStateChange?(.awaitingClassification)

        // Auto-timeout: discard after 10 seconds
        toastTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }
            self.onDiscardAction?()
        }
    }

    func dismissClassification() {
        toastTask?.cancel()
        pendingTranscript = nil
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            state = .closed
        }
        onStateChange?(.closed)
    }
}

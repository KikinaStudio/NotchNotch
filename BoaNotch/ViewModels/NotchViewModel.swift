import SwiftUI
import Combine

enum NotchState: Equatable {
    case closed
    case open
    case toast(String)

    static func == (lhs: NotchState, rhs: NotchState) -> Bool {
        switch (lhs, rhs) {
        case (.closed, .closed), (.open, .open): return true
        case (.toast(let a), .toast(let b)): return a == b
        default: return false
        }
    }
}

class NotchViewModel: ObservableObject {
    @Published var state: NotchState = .closed
    @Published var isDragTargeted = false
    @Published var isRecording = false

    /// The exact hardware notch dimensions, set by NotchWindowController at launch
    @Published var closedSize: CGSize = CGSize(width: 185, height: 32)

    /// The fully open size for chat — wide and compact
    let openSize: CGSize = CGSize(width: 580, height: 340)

    var onStateChange: ((NotchState) -> Void)?

    private var hoverTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?

    var isOpen: Bool { state == .open }
    var isClosed: Bool { state == .closed }

    var isToastVisible: Bool {
        if case .toast = state { return true }
        return false
    }

    var toastMessage: String? {
        if case .toast(let msg) = state { return msg }
        return nil
    }

    // MARK: - Current animated size

    /// Whether to show the thinking indicator on the closed notch
    var isThinkingClosed: Bool {
        !isOpen && isStreaming
    }

    @Published var isStreaming = false

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
                self.close()
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
        withAnimation(.interactiveSpring(response: 0.45, dampingFraction: 1.0, blendDuration: 0)) {
            state = .closed
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
}

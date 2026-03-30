import SwiftUI
import UniformTypeIdentifiers

struct NotchView: View {
    @ObservedObject var chatVM: ChatViewModel
    @ObservedObject var notchVM: NotchViewModel

    var body: some View {
        // Fixed-size container — same as the panel, never changes
        // Top-aligned ZStack so the notch shape sits at the top, just like BoringNotch
        ZStack(alignment: .top) {
            Color.clear

            VStack(alignment: .center, spacing: 0) {
                notchBody
                    .frame(
                        width: notchVM.currentWidth,
                        height: notchVM.currentHeight
                    )
                    // These two lines are the BoringNotch magic:
                    // the shape animates its size, the panel stays fixed
                    .animation(.interactiveSpring(response: 0.42, dampingFraction: 0.8, blendDuration: 0), value: notchVM.isOpen)

                // Toast appears below notch (outside the black shape)
                if notchVM.isToastVisible, let msg = notchVM.toastMessage {
                    ToastView(message: msg)
                        .padding(.top, 10)
                        .transition(.asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal: .opacity
                        ))
                        .onTapGesture { notchVM.open() }
                }
            }
        }
        .frame(
            width: NotchWindowController.panelWidth,
            height: NotchWindowController.panelHeight,
            alignment: .top
        )
        .contentShape(Rectangle())
        .onHover { hovering in notchVM.handleHover(hovering) }
        .onTapGesture { notchVM.handleClick() }
        .onDrop(of: [.fileURL], isTargeted: $notchVM.isDragTargeted) { providers in
            handleDrop(providers)
            return true
        }
    }

    // MARK: - Notch body

    private var notchBody: some View {
        ZStack {
            // Black notch shape — the animated pill/panel
            NotchShape(
                topCornerRadius: notchVM.topCornerRadius,
                bottomCornerRadius: notchVM.bottomCornerRadius
            )
            .fill(Color.black)
            .shadow(
                color: .black.opacity(0.6),
                radius: notchVM.isOpen ? 24 : 0,
                x: 0, y: notchVM.isOpen ? 8 : 0
            )

            // Content inside the notch
            if notchVM.isOpen {
                ChatView(chatVM: chatVM, notchVM: notchVM)
                    .padding(.top, 16)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                    .transition(.opacity.animation(
                        .easeIn(duration: 0.15).delay(0.1)
                    ))
            } else {
                // Closed state: subtle status dot
                closedIndicator
                    .transition(.opacity)
            }

            // Drag-over overlay
            if notchVM.isDragTargeted {
                DropOverlay()
                    .padding(4)
                    .transition(.opacity)
            }
        }
    }

    // MARK: - Closed indicator

    private var closedIndicator: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(Color(red: 0.2, green: 0.9, blue: 0.4))
                .frame(width: 5, height: 5)
            Text("Hermes")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
        }
    }

    // MARK: - Drop handling

    @discardableResult
    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
                guard let data = data as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil, isAbsolute: true)
                else { return }

                let attachment = DocumentExtractor.extract(from: url)
                DispatchQueue.main.async {
                    self.chatVM.pendingAttachments.append(attachment)
                    if !self.notchVM.isOpen { self.notchVM.open() }
                }
            }
        }
        return true
    }
}

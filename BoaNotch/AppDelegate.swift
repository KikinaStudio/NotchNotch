import AppKit
import SwiftUI
import Carbon.HIToolbox

class AppDelegate: NSObject, NSApplicationDelegate {
    var panelController: NotchWindowController?
    let chatVM = ChatViewModel()
    let notchVM = NotchViewModel()
    let audioRecorder = AudioRecorder()
    let sessionStore = SessionStore()
    let searchVM = SearchViewModel()
    let hermesConfig = HermesConfig()
    let onboardingVM = OnboardingViewModel()
    let cronStore = CronStore()
    let brainVM = BrainViewModel()
    private let clipperListener = ClipperListener()
    private var statusItem: NSStatusItem?
    private var flagsMonitor: Any?
    private var controlTapTimestamps: [Date] = []
    private var controlWasDown = false
    private static weak var shared: AppDelegate?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Self.shared = self

        chatVM.notchVM = notchVM
        chatVM.audioRecorder = audioRecorder
        chatVM.sessionId = sessionStore.selectedSessionId
        searchVM.chatVM = chatVM

        onboardingVM.notchVM = notchVM
        onboardingVM.hermesConfig = hermesConfig

        panelController = NotchWindowController(chatVM: chatVM, notchVM: notchVM, sessionStore: sessionStore, searchVM: searchVM, hermesConfig: hermesConfig, onboardingVM: onboardingVM, cronStore: cronStore, brainVM: brainVM)
        panelController?.showPanel()

        // If onboarding is needed, open notch immediately and suppress auto-close
        if onboardingVM.needsOnboarding {
            notchVM.suppressAutoClose = true
            notchVM.open()
        }

        notchVM.onTalkAction = { [weak self] in self?.talkAction() }
        notchVM.onBrainDumpAction = { [weak self] in self?.brainDumpAction() }

        registerTripleTapMonitor()
        setupMenuBarItem()
        startClipperListener()
        wireCronOutputToasts()
    }

    private func wireCronOutputToasts() {
        cronStore.onNewOutput = { [weak self] jobName, content in
            DispatchQueue.main.async {
                self?.notchVM.showCronToast(jobName: jobName, fullContent: content)
            }
        }
    }

    private func startClipperListener() {
        clipperListener.onClip = { [weak self] title, url in
            guard let self else { return }
            let label = title.isEmpty ? url : title
            self.notchVM.showClipperToast(label)
        }
        clipperListener.start()
    }

    // MARK: - Menu bar icon

    private func setupMenuBarItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            if let url = Bundle.module.url(forResource: "menubar-icon", withExtension: "png", subdirectory: "Resources"),
               let image = NSImage(contentsOf: url) {
                image.size = NSSize(width: 16, height: 16)
                image.isTemplate = true
                button.image = image
            } else if let url = Bundle.main.resourceURL?.appendingPathComponent("menubar-icon.png"),
                      let image = NSImage(contentsOf: url) {
                image.size = NSSize(width: 16, height: 16)
                image.isTemplate = true
                button.image = image
            }
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Open notchnotch", action: #selector(openNotch), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit notchnotch", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    @objc private func openNotch() {
        notchVM.open()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    // MARK: - Triple-tap Control detection

    private func registerTripleTapMonitor() {
        flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
        }
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        let keyCode = Int(event.keyCode)
        guard keyCode == kVK_Control || keyCode == kVK_RightControl else { return }

        let nowDown = event.modifierFlags.contains(.control)
        let wasDown = controlWasDown
        controlWasDown = nowDown

        let otherModifiers = event.modifierFlags.intersection([.shift, .command, .option])
        guard wasDown, !nowDown, otherModifiers.isEmpty else { return }

        let now = Date()
        controlTapTimestamps.append(now)
        controlTapTimestamps = controlTapTimestamps.filter { now.timeIntervalSince($0) < 0.5 }

        if controlTapTimestamps.count >= 3 {
            controlTapTimestamps.removeAll()
            DispatchQueue.main.async {
                if self.audioRecorder.isRecording {
                    // Triple-tap while recording = cancel
                    _ = self.audioRecorder.stopRecording()
                    self.notchVM.isRecording = false
                } else {
                    self.audioRecorder.startRecording()
                    self.notchVM.isRecording = true
                }
            }
        }
    }

    // MARK: - Recording actions (called from toast buttons)

    /// Stop recording → transcribe → send to chat
    private func talkAction() {
        guard let url = audioRecorder.stopRecording() else { return }
        notchVM.isRecording = false

        Task { @MainActor in
            let text = await SpeechTranscriber.transcribe(audioURL: url)
            if let text, !text.isEmpty {
                print("[notchnotch] Transcription OK: \(text.prefix(50))…")
                notchVM.open()
                chatVM.draft = text
                chatVM.send()
            } else {
                print("[notchnotch] Transcription failed for \(url.lastPathComponent)")
                let attachment = Attachment(
                    fileName: url.lastPathComponent,
                    fileType: "m4a",
                    textContent: "Audio file at: \(url.path)",
                    fileURL: url
                )
                chatVM.pendingAttachments = [attachment]
                chatVM.draft = "[Voice memo — transcription failed]"
                notchVM.open()
                chatVM.send()
            }
        }
    }

    /// Stop recording → transcribe → save to brain
    private func brainDumpAction() {
        guard let url = audioRecorder.stopRecording() else { return }
        notchVM.isRecording = false

        Task { @MainActor in
            let text = await SpeechTranscriber.transcribe(audioURL: url)
            if let text, !text.isEmpty {
                print("[notchnotch] Brain dump OK: \(text.prefix(50))…")
                chatVM.saveToBrain(content: text, fileName: "voice-note")
                notchVM.showClipperToast("Note archivée 🧠")
            } else {
                print("[notchnotch] Brain dump — transcription failed for \(url.lastPathComponent)")
                notchVM.showToast("Transcription échouée")
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let flagsMonitor { NSEvent.removeMonitor(flagsMonitor) }
        clipperListener.stop()
    }
}

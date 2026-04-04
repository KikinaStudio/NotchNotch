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
    private var statusItem: NSStatusItem?
    private var hotKeyRef: EventHotKeyRef?
    private var enterHotKeyRef: EventHotKeyRef?
    private static weak var shared: AppDelegate?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Self.shared = self

        chatVM.notchVM = notchVM
        chatVM.audioRecorder = audioRecorder
        chatVM.sessionId = sessionStore.selectedSessionId
        searchVM.chatVM = chatVM

        panelController = NotchWindowController(chatVM: chatVM, notchVM: notchVM, sessionStore: sessionStore, searchVM: searchVM, hermesConfig: hermesConfig)
        panelController?.showPanel()

        registerGlobalHotkey()
        setupMenuBarItem()
    }

    // MARK: - Menu bar icon

    private func setupMenuBarItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "bubble.left.fill", accessibilityDescription: "BoaNotch")
            button.image?.size = NSSize(width: 16, height: 16)
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Open BoaNotch", action: #selector(openNotch), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit BoaNotch", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    @objc private func openNotch() {
        notchVM.open()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    // MARK: - Global hotkey (Carbon RegisterEventHotKey — intercepts the event, no error beep)

    private func registerGlobalHotkey() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        InstallEventHandler(GetApplicationEventTarget(), { (_, event, _) -> OSStatus in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            guard let delegate = AppDelegate.shared else { return noErr }
            DispatchQueue.main.async {
                switch hotKeyID.id {
                case 1: delegate.toggleRecording()   // Ctrl+Shift+R
                case 2: delegate.confirmRecording()   // Enter (during recording)
                default: break
                }
            }
            return noErr
        }, 1, &eventType, nil, nil)

        // Ctrl+Shift+R — toggle recording
        let recID = EventHotKeyID(signature: OSType(0x424E4348), id: 1)
        RegisterEventHotKey(UInt32(kVK_ANSI_R), UInt32(controlKey | shiftKey), recID, GetApplicationEventTarget(), 0, &hotKeyRef)

        // Enter — confirm and send recording (registered dynamically in toggleRecording)
    }

    private func registerEnterHotkey() {
        guard enterHotKeyRef == nil else { return }
        let enterID = EventHotKeyID(signature: OSType(0x424E4348), id: 2)
        RegisterEventHotKey(UInt32(kVK_Return), 0, enterID, GetApplicationEventTarget(), 0, &enterHotKeyRef)
    }

    private func unregisterEnterHotkey() {
        if let ref = enterHotKeyRef {
            UnregisterEventHotKey(ref)
            enterHotKeyRef = nil
        }
    }

    private func toggleRecording() {
        if audioRecorder.isRecording {
            sendVoiceMemo()
        } else {
            audioRecorder.startRecording()
            notchVM.isRecording = true
            registerEnterHotkey()
        }
    }

    private func confirmRecording() {
        guard audioRecorder.isRecording else { return }
        sendVoiceMemo()
    }

    private func sendVoiceMemo() {
        unregisterEnterHotkey()
        guard let url = audioRecorder.stopRecording() else {
            notchVM.isRecording = false
            return
        }
        notchVM.isRecording = false

        // Transcribe locally, then send as text
        Task { @MainActor in
            if let text = await SpeechTranscriber.transcribe(audioURL: url) {
                chatVM.draft = text
                chatVM.send()
            } else {
                // Fallback: send audio file path if transcription fails
                let attachment = Attachment(
                    fileName: url.lastPathComponent,
                    fileType: "m4a",
                    textContent: "Audio file at: \(url.path)",
                    fileURL: url
                )
                chatVM.pendingAttachments = [attachment]
                chatVM.draft = "[Voice memo — transcription failed]"
                chatVM.send()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        unregisterEnterHotkey()
    }
}

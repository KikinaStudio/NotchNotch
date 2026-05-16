import AppKit
import SwiftUI
import Carbon.HIToolbox
import os.log

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
    let loginItemService = LoginItemService()
    let appearanceSettings = AppearanceSettings()
    let panelSizeStore = PanelSizeStore()
    let titleStore = TitleStore()
    private let clipperListener = ClipperListener()
    private var statusItem: NSStatusItem?
    private var flagsMonitor: Any?
    private var controlTapTimestamps: [Date] = []
    private var controlWasDown = false
    private var didProbeCompression = false
    private static weak var shared: AppDelegate?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Self.shared = self

        // Touch the ComputerUseService singleton to trigger its lazy init.
        // The private init() kicks off a refreshState() Task that logs the
        // cua-driver detection via os_log (visible in Console.app and
        // `log show`). @MainActor on the class requires we touch the
        // singleton from a main-actor context (here) rather than at
        // AppDelegate class-level init.
        _ = ComputerUseService.shared

        // Same dance for HermesGatewayLauncher: its init refreshes state
        // (plist on disk + launchctl loaded?) so it's ready before the
        // first chat send. Then re-load the plist if needed — covers the
        // case where the user nuked the LaunchAgent manually, or NotchNotch
        // updated to a new plist version that needs re-bootstrapping.
        _ = HermesGatewayLauncher.shared
        reinstallLaunchAgentIfNeeded()

        ensureBrainDirectories()

        chatVM.notchVM = notchVM
        chatVM.audioRecorder = audioRecorder
        chatVM.titleStore = titleStore
        chatVM.cronStore = cronStore
        // Note: do NOT hijack chatVM.sessionId from sessionStore.selectedSessionId.
        // That used to merge every NotchNotch chat into the Telegram session,
        // producing one giant 268-message blob. The HermesClient now owns its
        // own persistent notchnotch-{uuid} session ID per conversation.
        searchVM.chatVM = chatVM

        onboardingVM.notchVM = notchVM

        panelController = NotchWindowController(chatVM: chatVM, notchVM: notchVM, sessionStore: sessionStore, searchVM: searchVM, hermesConfig: hermesConfig, onboardingVM: onboardingVM, cronStore: cronStore, brainVM: brainVM, loginItemService: loginItemService, appearanceSettings: appearanceSettings, panelSizeStore: panelSizeStore, titleStore: titleStore)
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
        probeCompressionEndpointOnce()

        // After Sparkle relaunches us, surface the Gatekeeper hint so users know
        // macOS may block the new binary on first run (we ship ad-hoc-signed).
        UpdaterService.shared.presentPostUpdateGatekeeperHintIfNeeded()

        applyHermesLocaleOnce()
    }

    /// Re-load the LaunchAgent plist if it exists but isn't loaded. Covers
    /// two scenarios: (1) the user unloaded it manually with `launchctl
    /// bootout` and didn't reboot, (2) a NotchNotch update changed the
    /// plist template and the on-disk file needs replacing.
    ///
    /// `.notInstalled` is intentionally a no-op here — touching the
    /// LaunchAgent without user consent at boot would be invasive. The
    /// actionable "Hermes ne répond pas" toast handles that case lazily,
    /// only when the user actually tries to chat and hits the failure.
    ///
    /// `.installedAndLoaded` is also a no-op — the gateway is up. If it's
    /// up-but-silent (process stuck), the same toast handles it via
    /// `kickstart` in `repairAndRetry`.
    private func reinstallLaunchAgentIfNeeded() {
        Task { @MainActor in
            let launcher = HermesGatewayLauncher.shared
            launcher.refreshState()
            guard launcher.state == .installedNotLoaded else { return }
            do {
                try launcher.install()
                os_log("[notchnotch] LaunchAgent re-loaded at launch", type: .info)
            } catch {
                os_log("[notchnotch] LaunchAgent re-load failed: %{public}@",
                       type: .info,
                       error.localizedDescription)
            }
        }
    }

    /// One-shot, idempotent: write `display.language: fr` to ~/.hermes/config.yaml
    /// once per install so Hermes v0.13+ static i18n (PR #20329) renders CLI
    /// and gateway messages in French. No UI, no toast — fail silently if the
    /// config doesn't exist yet (Hermes not installed) so we don't create an
    /// orphan file. Retries automatically next launch if the write itself fails
    /// (the flag stays false until success).
    private func applyHermesLocaleOnce() {
        let key = "didSetHermesLocaleFr"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        let configPath = NSString(string: "~/.hermes/config.yaml").expandingTildeInPath
        guard FileManager.default.fileExists(atPath: configPath) else { return }
        hermesConfig.setImmediate("display.language", value: "fr")
        UserDefaults.standard.set(true, forKey: key)
    }

    private func ensureBrainDirectories() {
        let fm = FileManager.default
        for sub in ["raw", "wiki"] {
            let path = NSString(string: "~/.hermes/brain/\(sub)").expandingTildeInPath
            try? fm.createDirectory(atPath: path, withIntermediateDirectories: true)
        }
    }

    private func probeCompressionEndpointOnce() {
        guard !didProbeCompression else { return }
        didProbeCompression = true
        let config = hermesConfig
        let vm = notchVM
        Task.detached {
            let health = await config.probeCompressionEndpoint()
            guard case .unreachable(let reason) = health else { return }
            os_log("Compression endpoint unreachable: %{public}@", type: .info, reason)
            await MainActor.run {
                vm.showToast("Modèle de compression injoignable. Vérifie ta config Hermes.", kind: .error)
            }
        }
    }

    private func wireCronOutputToasts() {
        cronStore.onNewOutput = { [weak self] jobId, jobName, content in
            DispatchQueue.main.async {
                self?.notchVM.showCronToast(jobId: jobId, jobName: jobName, fullContent: content)
            }
        }
    }

    private func startClipperListener() {
        clipperListener.onClip = { [weak self] title, url in
            guard let self else { return }
            let label = title.isEmpty ? url : title
            self.notchVM.showToast(label, kind: .success)
        }
        clipperListener.start()
    }

    // MARK: - Menu bar icon

    private func setupMenuBarItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            if let url = Bundle.main.resourceURL?.appendingPathComponent("menubar-icon.png"),
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
                notchVM.showToast("Note archivée 🧠", kind: .success)
            } else {
                print("[notchnotch] Brain dump — transcription failed for \(url.lastPathComponent)")
                notchVM.showToast("Transcription échouée", kind: .error)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let flagsMonitor { NSEvent.removeMonitor(flagsMonitor) }
        clipperListener.stop()
    }
}

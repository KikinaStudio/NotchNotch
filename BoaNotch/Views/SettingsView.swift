import SwiftUI

struct SettingsView: View {
    @ObservedObject var sessionStore: SessionStore
    @ObservedObject var notchVM: NotchViewModel
    @ObservedObject var hermesConfig: HermesConfig
    @ObservedObject var loginItemService: LoginItemService
    @ObservedObject var appearanceSettings: AppearanceSettings
    @StateObject private var googleConnection = GoogleConnectionState()
    @State private var apiKey = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                Text("Settings")
                    .font(.headline)
                    .foregroundStyle(.primary)

                // ── AI Provider ──
                settingsSection("AI Provider") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Model provider")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 2) {
                            ForEach([("nous", "Nous"), ("openrouter", "OpenRouter"), ("openai", "OpenAI"), ("anthropic", "Anthropic"), ("minimax", "MiniMax")], id: \.0) { value, label in
                                segmentedButton(label: label, isSelected: hermesConfig.modelProvider == value) {
                                    hermesConfig.modelProvider = value
                                    hermesConfig.setImmediate("model.provider", value: value)
                                    if let baseURL = HermesConfig.defaultBaseURL(for: value) {
                                        hermesConfig.setImmediate("model.base_url", value: baseURL)
                                    }
                                }
                            }
                        }

                        if hermesConfig.modelProvider == "nous" {
                            Text("Free models via Nous Portal. No API key needed.")
                                .font(.caption2)
                                .foregroundStyle(AppColors.accent.opacity(0.6))
                        }

                        if hermesConfig.modelProvider != "nous" {
                            apiKeyField
                        }
                    }
                }

                // ── Google Workspace ──
                settingsSection("Google Workspace") {
                    googleWorkspaceSection
                }

                // ── Agent ──
                settingsSection("Agent") {
                    // Max iterations
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Max iterations")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 2) {
                            ForEach([("Quick", 15), ("Normal", 50), ("Deep", 90)], id: \.1) { label, val in
                                segmentedButton(label: label, isSelected: hermesConfig.maxIterations == val) {
                                    hermesConfig.maxIterations = val
                                    hermesConfig.setImmediate("agent.max_iterations", value: val)
                                }
                            }

                            Spacer()

                            // Native stepper for fine-grained control
                            HStack(spacing: 6) {
                                Text("\(hermesConfig.maxIterations)")
                                    .font(.footnote.monospacedDigit())
                                    .foregroundStyle(.primary)
                                    .frame(width: 24)
                                Stepper(
                                    "",
                                    value: Binding(
                                        get: { hermesConfig.maxIterations },
                                        set: { val in
                                            hermesConfig.maxIterations = val
                                            hermesConfig.set("agent.max_iterations", value: val)
                                        }
                                    ),
                                    in: 5...200,
                                    step: 5
                                )
                                .labelsHidden()
                                .controlSize(.mini)
                            }
                        }
                    }

                    // Streaming toggle
                    HStack {
                        Text("Stream responses")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { hermesConfig.streaming },
                            set: { val in
                                hermesConfig.streaming = val
                                hermesConfig.setImmediate("display.streaming", value: val)
                            }
                        ))
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .labelsHidden()
                    }
                }

                // ── Execution ──
                settingsSection("Execution") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Terminal backend")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 2) {
                            ForEach(["local", "docker", "ssh"], id: \.self) { backend in
                                segmentedButton(label: backend, isSelected: hermesConfig.terminalBackend == backend) {
                                    hermesConfig.terminalBackend = backend
                                    hermesConfig.setImmediate("terminal.backend", value: backend)
                                }
                            }
                        }

                        // Conditional sub-fields
                        if hermesConfig.terminalBackend == "ssh" {
                            VStack(spacing: 4) {
                                configTextField("Host", text: Binding(
                                    get: { hermesConfig.sshHost },
                                    set: { hermesConfig.sshHost = $0; hermesConfig.set("terminal.ssh_host", value: $0) }
                                ))
                                configTextField("User", text: Binding(
                                    get: { hermesConfig.sshUser },
                                    set: { hermesConfig.sshUser = $0; hermesConfig.set("terminal.ssh_user", value: $0) }
                                ))
                                HStack {
                                    Text("Port")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 35, alignment: .leading)
                                    TextField("", value: Binding(
                                        get: { hermesConfig.sshPort },
                                        set: { hermesConfig.sshPort = $0; hermesConfig.set("terminal.ssh_port", value: $0) }
                                    ), format: .number)
                                    .textFieldStyle(.plain)
                                    .font(.caption)
                                    .foregroundStyle(.primary)
                                }
                            }
                            .padding(.leading, 8)
                            .transition(.opacity)
                        }

                        if hermesConfig.terminalBackend == "docker" {
                            configTextField("Image", text: Binding(
                                get: { hermesConfig.dockerImage },
                                set: { hermesConfig.dockerImage = $0; hermesConfig.set("terminal.docker_image", value: $0) }
                            ))
                            .padding(.leading, 8)
                            .transition(.opacity)
                        }
                    }
                }

                // ── Session ──
                settingsSection("Session") {
                    HStack(spacing: 6) {
                        Image(systemName: "paperplane.fill")
                            .font(.footnote)
                            .foregroundStyle(sessionStore.isLinked ? AppColors.accent : Color.secondary)
                        Text(sessionStore.isLinked ? "Telegram linked" : "No Telegram session")
                            .font(.footnote)
                            .foregroundStyle(sessionStore.isLinked ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                        if sessionStore.isLinked {
                            Spacer()
                            Text(sessionStore.selectedSessionId ?? "")
                                .font(.caption2.monospaced())
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                }

                // ── Appearance ──
                settingsSection("Appearance") {
                    HStack {
                        Text("Text size")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Spacer()
                        HStack(spacing: 0) {
                            textSizeSegment(.small, display: 10)
                            segmentDivider
                            textSizeSegment(.medium, display: 13)
                            segmentDivider
                            textSizeSegment(.large, display: 16)
                        }
                        .background(Capsule().fill(.quaternary))
                    }
                }

                // ── Startup ──
                settingsSection("Startup") {
                    HStack {
                        Text("Launch notchnotch at login")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { loginItemService.isEnabled },
                            set: { loginItemService.setEnabled($0) }
                        ))
                        .toggleStyle(.switch)
                        .tint(AppColors.accent)
                        .controlSize(.mini)
                        .labelsHidden()
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Helpers

    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold).monospaced())
                .foregroundStyle(.tertiary)
                .tracking(1.5)
            content()
        }
    }

    private var apiKeyPlaceholder: String {
        switch hermesConfig.modelProvider {
        case "openrouter": return "sk-or-v1-..."
        case "openai": return "sk-..."
        case "anthropic": return "sk-ant-..."
        case "minimax": return "sk-..."
        default: return ""
        }
    }

    @ViewBuilder
    private var googleWorkspaceSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            if googleConnection.isConnected, let email = googleConnection.connectedEmail {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.footnote)
                        .foregroundStyle(AppColors.accent)
                    Text("Connected as ")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    + Text(email)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.primary)
                    Spacer()
                    Button {
                        googleConnection.disconnect()
                    } label: {
                        Text("Disconnect")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(.quaternary))
                    }
                    .buttonStyle(.plain)
                    .pointingHandCursor()
                }
            } else {
                HStack(spacing: 8) {
                    Button {
                        Task { await googleConnection.connect() }
                    } label: {
                        HStack(spacing: 6) {
                            if googleConnection.isConnecting {
                                ProgressView()
                                    .controlSize(.mini)
                                    .scaleEffect(0.7)
                                    .frame(width: 10, height: 10)
                            }
                            Text(googleConnection.isConnecting ? "Connecting…" : "Connect Google")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(googleConnection.isConnecting ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(AppColors.accent.opacity(0.35)))
                    }
                    .buttonStyle(.plain)
                    .disabled(googleConnection.isConnecting)
                    .pointingHandCursor()

                    Text("Gmail, Calendar, Drive, and more")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if let err = googleConnection.errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.red)
                    Text(err)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(3)
                    Spacer()
                    Button {
                        googleConnection.dismissError()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .pointingHandCursor()
                }
                .padding(.top, 2)
            }
        }
    }

    private var apiKeyField: some View {
        HStack(spacing: 6) {
            SecureField(apiKeyPlaceholder, text: $apiKey)
                .textFieldStyle(.plain)
                .font(.caption)
                .foregroundStyle(.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary))

            Button {
                hermesConfig.writeAPIKey(provider: hermesConfig.modelProvider, key: apiKey)
                apiKey = ""
            } label: {
                Text("Save")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(apiKey.isEmpty ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background {
                        if apiKey.isEmpty {
                            Capsule().fill(.clear)
                        } else {
                            Capsule().fill(AppColors.accent.opacity(0.35))
                        }
                    }
            }
            .buttonStyle(.plain)
            .disabled(apiKey.isEmpty)
        }
    }

    private func textSizeSegment(_ size: AppearanceSettings.TextSize, display: CGFloat) -> some View {
        let isSelected = appearanceSettings.textSize == size
        return Button {
            appearanceSettings.textSize = size
        } label: {
            Text("A")
                .font(.system(size: display, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .frame(width: 32, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }

    private var segmentDivider: some View {
        Rectangle()
            .fill(.separator)
            .frame(width: 1, height: 14)
    }

    private func segmentedButton(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption.weight(isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background {
                    if isSelected {
                        Capsule().fill(.quaternary)
                    } else {
                        Capsule().fill(.clear)
                    }
                }
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }

    private func configTextField(_ label: String, text: Binding<String>) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 35, alignment: .leading)
            TextField("", text: text)
                .textFieldStyle(.plain)
                .font(.caption)
                .foregroundStyle(.primary)
        }
    }
}

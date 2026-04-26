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
        FadingScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // ── AI Provider ──
                settingsSection("AI Provider") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Model provider")
                            .font(DS.Text.caption)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 4) {
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
                                .font(DS.Text.micro)
                                .foregroundStyle(AppColors.accent.opacity(0.6))
                        }

                        if hermesConfig.modelProvider != "nous" {
                            apiKeyField
                        }
                    }
                }

                sectionDivider

                // ── Google Workspace ──
                settingsSection("Google Workspace") {
                    googleWorkspaceSection
                }

                sectionDivider

                // ── Agent ──
                settingsSection("Agent") {
                    // Max iterations
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Max iterations")
                            .font(DS.Text.caption)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 4) {
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
                                    .font(DS.Text.caption.monospacedDigit())
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
                            .font(DS.Text.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        StatusDotButton(isOn: hermesConfig.streaming) {
                            let newValue = !hermesConfig.streaming
                            hermesConfig.streaming = newValue
                            hermesConfig.setImmediate("display.streaming", value: newValue)
                        }
                        .accessibilityLabel("Stream responses")
                    }
                }

                sectionDivider

                // ── Execution ──
                settingsSection("Execution") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Terminal backend")
                            .font(DS.Text.caption)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 4) {
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
                                        .font(DS.Text.caption)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 35, alignment: .leading)
                                    TextField("", value: Binding(
                                        get: { hermesConfig.sshPort },
                                        set: { hermesConfig.sshPort = $0; hermesConfig.set("terminal.ssh_port", value: $0) }
                                    ), format: .number)
                                    .textFieldStyle(.plain)
                                    .font(DS.Text.caption)
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

                sectionDivider

                // ── Session ──
                settingsSection("Session") {
                    HStack(spacing: 6) {
                        Image(systemName: "paperplane.fill")
                            .font(DS.Text.caption)
                            .foregroundStyle(sessionStore.isLinked ? AppColors.accent : Color.secondary)
                        Text(sessionStore.isLinked ? "Telegram linked" : "No Telegram session")
                            .font(DS.Text.caption)
                            .foregroundStyle(sessionStore.isLinked ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                        if sessionStore.isLinked {
                            Spacer()
                            Text(sessionStore.selectedSessionId ?? "")
                                .font(DS.Text.microMono)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                }

                sectionDivider

                // ── Appearance ──
                settingsSection("Appearance") {
                    HStack {
                        Text("Text size")
                            .font(DS.Text.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        HStack(spacing: 0) {
                            textSizeSegment(.medium, display: 12)
                            segmentDivider
                            textSizeSegment(.large, display: 15)
                        }
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.quaternary))
                    }
                }

                sectionDivider

                // ── Startup ──
                settingsSection("Startup") {
                    HStack {
                        Text("Launch notchnotch at login")
                            .font(DS.Text.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        StatusDotButton(isOn: loginItemService.isEnabled) {
                            loginItemService.setEnabled(!loginItemService.isEnabled)
                        }
                        .accessibilityLabel("Launch notchnotch at login")
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(DS.Text.sectionHead)
                .foregroundStyle(.tertiary)
                .tracking(1.5)
            content()
        }
        .padding(.vertical, 14)
    }

    private var sectionDivider: some View {
        Rectangle()
            .fill(DS.Stroke.hairline)
            .frame(height: 1)
            .frame(maxWidth: .infinity)
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
                        .font(DS.Text.caption)
                        .foregroundStyle(AppColors.accent)
                    Text("Connected as ")
                        .font(DS.Text.caption)
                        .foregroundStyle(.secondary)
                    + Text(email)
                        .font(DS.Text.captionMedium)
                        .foregroundStyle(.primary)
                    Spacer()
                    Button {
                        googleConnection.disconnect()
                    } label: {
                        Text("Disconnect")
                            .font(DS.Text.captionMedium)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.quaternary))
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
                                .font(DS.Text.caption.weight(.semibold))
                                .foregroundStyle(googleConnection.isConnecting ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(AppColors.accent.opacity(0.35)))
                    }
                    .buttonStyle(.plain)
                    .disabled(googleConnection.isConnecting)
                    .pointingHandCursor()

                    Text("Gmail, Calendar, Drive, and more")
                        .font(DS.Text.micro)
                        .foregroundStyle(.secondary)
                }
            }

            if let err = googleConnection.errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(DS.Text.micro)
                        .foregroundStyle(.red)
                    Text(err)
                        .font(DS.Text.micro)
                        .foregroundStyle(.red)
                        .lineLimit(3)
                    Spacer()
                    Button {
                        googleConnection.dismissError()
                    } label: {
                        Image(systemName: "xmark")
                            .font(DS.Text.micro)
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
                .font(DS.Text.caption)
                .foregroundStyle(.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary))

            Button {
                hermesConfig.writeAPIKey(provider: hermesConfig.modelProvider, key: apiKey)
                apiKey = ""
            } label: {
                Text("Save")
                    .font(DS.Text.caption.weight(.semibold))
                    .foregroundStyle(apiKey.isEmpty ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background {
                        let saveShape = RoundedRectangle(cornerRadius: 8, style: .continuous)
                        if apiKey.isEmpty {
                            saveShape.fill(.clear)
                        } else {
                            saveShape.fill(AppColors.accent.opacity(0.35))
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
                // TODO(design): taille dynamique (12pt/15pt) reflétant le réglage textSize, pas tokenisable
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
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        return Button(action: action) {
            Text(label)
                // TODO(design): poids conditionnel actif=semibold/inactif=medium pour affordance d'état segmenté
                .font(DS.Text.caption.weight(isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? AnyShapeStyle(Color.black.opacity(0.85)) : AnyShapeStyle(.secondary))
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background {
                    if isSelected {
                        shape.fill(AppColors.accent)
                    } else {
                        shape.stroke(Color.gray.opacity(0.45), lineWidth: 1)
                    }
                }
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }

    private func configTextField(_ label: String, text: Binding<String>) -> some View {
        HStack {
            Text(label)
                .font(DS.Text.caption)
                .foregroundStyle(.secondary)
                .frame(width: 35, alignment: .leading)
            TextField("", text: text)
                .textFieldStyle(.plain)
                .font(DS.Text.caption)
                .foregroundStyle(.primary)
        }
    }
}

import SwiftUI

struct SettingsView: View {
    @ObservedObject var sessionStore: SessionStore
    @ObservedObject var notchVM: NotchViewModel
    @ObservedObject var hermesConfig: HermesConfig
    @State private var apiKey = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                Text("Settings")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))

                // ── AI Provider ──
                settingsSection("AI Provider") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Model provider")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.5))

                        HStack(spacing: 2) {
                            ForEach([("nous", "Nous"), ("openrouter", "OpenRouter"), ("openai", "OpenAI"), ("anthropic", "Anthropic")], id: \.0) { value, label in
                                segmentedButton(label: label, isSelected: hermesConfig.modelProvider == value) {
                                    hermesConfig.modelProvider = value
                                    hermesConfig.setImmediate("model.provider", value: value)
                                }
                            }
                        }

                        if hermesConfig.modelProvider == "nous" {
                            Text("Free models via Nous Portal. No API key needed.")
                                .font(.system(size: 9))
                                .foregroundStyle(AppColors.accent.opacity(0.4))
                        }

                        if hermesConfig.modelProvider != "nous" {
                            apiKeyField
                        }
                    }
                }

                // ── Agent ──
                settingsSection("Agent") {
                    // Max iterations
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Max iterations")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.5))

                        HStack(spacing: 2) {
                            ForEach([("Quick", 15), ("Normal", 50), ("Deep", 90)], id: \.1) { label, val in
                                segmentedButton(label: label, isSelected: hermesConfig.maxIterations == val) {
                                    hermesConfig.maxIterations = val
                                    hermesConfig.setImmediate("agent.max_iterations", value: val)
                                }
                            }

                            Spacer()

                            // Custom stepper
                            HStack(spacing: 4) {
                                Button {
                                    let val = max(5, hermesConfig.maxIterations - 5)
                                    hermesConfig.maxIterations = val
                                    hermesConfig.set("agent.max_iterations", value: val)
                                } label: {
                                    Image(systemName: "minus")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.white.opacity(0.4))
                                }
                                .buttonStyle(.plain)

                                Text("\(hermesConfig.maxIterations)")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.7))
                                    .frame(width: 28)

                                Button {
                                    let val = min(200, hermesConfig.maxIterations + 5)
                                    hermesConfig.maxIterations = val
                                    hermesConfig.set("agent.max_iterations", value: val)
                                } label: {
                                    Image(systemName: "plus")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.white.opacity(0.4))
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.white.opacity(0.04))
                            .clipShape(Capsule())
                        }
                    }

                    // Streaming toggle
                    HStack {
                        Text("Stream responses")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.5))
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { hermesConfig.streaming },
                            set: { val in
                                hermesConfig.streaming = val
                                hermesConfig.setImmediate("display.streaming", value: val)
                            }
                        ))
                        .toggleStyle(.switch)
                        .scaleEffect(0.7)
                        .frame(width: 40)
                    }
                }

                // ── Execution ──
                settingsSection("Execution") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Terminal backend")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.5))

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
                                        .font(.system(size: 10))
                                        .foregroundStyle(.white.opacity(0.35))
                                        .frame(width: 35, alignment: .leading)
                                    TextField("", value: Binding(
                                        get: { hermesConfig.sshPort },
                                        set: { hermesConfig.sshPort = $0; hermesConfig.set("terminal.ssh_port", value: $0) }
                                    ), format: .number)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.white.opacity(0.7))
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
                            .font(.system(size: 10))
                            .foregroundStyle(sessionStore.isLinked ? AppColors.accent : .white.opacity(0.3))
                        Text(sessionStore.isLinked ? "Telegram linked" : "No Telegram session")
                            .font(.system(size: 11))
                            .foregroundStyle(sessionStore.isLinked ? .white.opacity(0.6) : .white.opacity(0.3))
                        if sessionStore.isLinked {
                            Spacer()
                            Text(sessionStore.selectedSessionId ?? "")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.2))
                                .lineLimit(1)
                        }
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
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.28))
                .tracking(1.5)
            content()
        }
    }

    private var apiKeyPlaceholder: String {
        switch hermesConfig.modelProvider {
        case "openrouter": return "sk-or-v1-..."
        case "openai": return "sk-..."
        case "anthropic": return "sk-ant-..."
        default: return ""
        }
    }

    private var apiKeyField: some View {
        HStack(spacing: 6) {
            SecureField(apiKeyPlaceholder, text: $apiKey)
                .textFieldStyle(.plain)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.7))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            Button {
                hermesConfig.writeAPIKey(provider: hermesConfig.modelProvider, key: apiKey)
                apiKey = ""
            } label: {
                Text("Save")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(apiKey.isEmpty ? .white.opacity(0.3) : .white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(apiKey.isEmpty ? .clear : .white.opacity(0.12))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(apiKey.isEmpty)
        }
    }

    private func segmentedButton(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 10, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? .white : .white.opacity(0.35))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(isSelected ? Color.white.opacity(0.1) : .clear)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }

    private func configTextField(_ label: String, text: Binding<String>) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.35))
                .frame(width: 35, alignment: .leading)
            TextField("", text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.7))
        }
    }

}

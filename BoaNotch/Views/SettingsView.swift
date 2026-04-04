import SwiftUI

struct SettingsView: View {
    @ObservedObject var sessionStore: SessionStore
    @ObservedObject var notchVM: NotchViewModel
    @ObservedObject var hermesConfig: HermesConfig
    var onSessionChanged: (String?) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                Text("Settings")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))

                // ── Agent ──
                settingsSection("Agent") {
                    // Max iterations
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Max iterations")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.5))

                        HStack(spacing: 6) {
                            ForEach([("Quick", 15), ("Normal", 50), ("Deep", 90)], id: \.1) { label, val in
                                Button {
                                    hermesConfig.maxIterations = val
                                    hermesConfig.setImmediate("agent.max_iterations", value: val)
                                } label: {
                                    Text(label)
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(hermesConfig.maxIterations == val ? .white : .white.opacity(0.5))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .background(hermesConfig.maxIterations == val ? AppColors.accent.opacity(0.3) : .white.opacity(0.06))
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
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
                            .background(.white.opacity(0.06))
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

                        HStack(spacing: 6) {
                            ForEach(["local", "docker", "ssh"], id: \.self) { backend in
                                Button {
                                    hermesConfig.terminalBackend = backend
                                    hermesConfig.setImmediate("terminal.backend", value: backend)
                                } label: {
                                    Text(backend)
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(hermesConfig.terminalBackend == backend ? .white : .white.opacity(0.5))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .background(hermesConfig.terminalBackend == backend ? AppColors.accent.opacity(0.3) : .white.opacity(0.06))
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
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

                // ── Sessions ──
                settingsSection("Sessions") {
                    if !sessionStore.sources.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(sessionStore.sources, id: \.self) { source in
                                Button {
                                    sessionStore.selectedSource = sessionStore.selectedSource == source ? nil : source
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: iconForSource(source))
                                            .font(.system(size: 10))
                                        Text(source.capitalized)
                                            .font(.system(size: 11, weight: .medium))
                                    }
                                    .foregroundStyle(sessionStore.selectedSource == source ? .white : .white.opacity(0.5))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(sessionStore.selectedSource == source ? AppColors.accent.opacity(0.3) : .white.opacity(0.06))
                                    .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                                .pointingHandCursor()
                            }

                            if sessionStore.selectedSessionId != nil {
                                Spacer()
                                Button {
                                    sessionStore.disconnect()
                                    onSessionChanged(nil)
                                } label: {
                                    Text("Disconnect")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.red.opacity(0.6))
                                }
                                .buttonStyle(.plain)
                                .pointingHandCursor()
                            }
                        }

                        if sessionStore.selectedSource != nil {
                            VStack(spacing: 2) {
                                ForEach(sessionStore.sessions) { session in
                                    sessionRow(session)
                                }
                            }
                        }
                    } else {
                        Text("No external sessions found")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.3))
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
                .foregroundStyle(.white.opacity(0.25))
                .tracking(1.5)
            content()
        }
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

    private func sessionRow(_ session: HermesSession) -> some View {
        let isSelected = sessionStore.selectedSessionId == session.id
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "fr-FR")

        return Button {
            sessionStore.selectedSessionId = session.id
            onSessionChanged(session.id)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.title.isEmpty ? session.id : session.title)
                        .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? AppColors.accent : .white.opacity(0.7))
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        Text(formatter.string(from: session.startedAt))
                            .font(.system(size: 9))
                        Text("\(session.messageCount) msgs")
                            .font(.system(size: 9))
                    }
                    .foregroundStyle(.white.opacity(0.3))
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(AppColors.accent)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(isSelected ? AppColors.accent.opacity(0.1) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }

    private func iconForSource(_ source: String) -> String {
        switch source {
        case "telegram": return "paperplane.fill"
        case "slack": return "number"
        case "discord": return "bubble.left.and.bubble.right.fill"
        case "whatsapp": return "phone.fill"
        case "signal": return "lock.fill"
        default: return "message.fill"
        }
    }
}

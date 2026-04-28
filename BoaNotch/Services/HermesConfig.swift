import Foundation
import Combine
import Yams

enum EndpointHealth {
    case notConfigured
    case reachable
    case unreachable(reason: String)
}

class HermesConfig: ObservableObject {
    static let shared = HermesConfig()

    private var configPath: String {
        let hermesHome = ProcessInfo.processInfo.environment["HERMES_HOME"]
            ?? "\(NSHomeDirectory())/.hermes"
        return "\(hermesHome)/config.yaml"
    }

    // MARK: - Published config values

    // Zone B: Expanded bar
    @Published var activeProfile: String = "default"
    @Published var modelDefault: String = ""
    @Published var modelProvider: String = "openrouter"
    @Published var reasoningEffort: String = "medium"
    @Published var skipMemory: Bool = false
    @Published var maxIterations: Int = 50

    // Zone C: Settings panel
    @Published var streaming: Bool = true
    @Published var terminalBackend: String = "local"
    @Published var sshHost: String = ""
    @Published var sshUser: String = ""
    @Published var sshPort: Int = 22
    @Published var dockerImage: String = ""


    // Profiles
    @Published var availableProfiles: [String] = ["default"]

    // User-added custom model IDs per provider (persisted in UserDefaults)
    @Published var userCustomModels: [String: [CustomModel]] = [:]
    private let userCustomModelsKey = "userCustomModels"

    struct CustomModel: Codable, Equatable {
        let value: String
        let label: String?
    }

    // Compression (read-only — Hermes owns this field, we only observe)
    private var compressionBaseURLString: String?

    var compressionBaseURL: URL? {
        guard let str = compressionBaseURLString, !str.isEmpty else { return nil }
        return URL(string: str)
    }

    var availableModels: [(value: String, label: String)] {
        let base: [(value: String, label: String)] = {
            switch modelProvider {
            case "openai":
                return [
                    ("gpt-4o-mini", "gpt-4o mini"),
                    ("gpt-4o", "gpt-4o"),
                    ("gpt-5", "gpt-5"),
                ]
            case "anthropic":
                return [
                    ("claude-sonnet-4-6-20250514", "sonnet 4.6"),
                    ("claude-opus-4-6-20250514", "opus 4.6"),
                ]
            case "openrouter":
                return [
                    ("anthropic/claude-sonnet-4.6", "sonnet 4.6"),
                    ("google/gemini-3-flash-preview", "gemini flash"),
                    ("minimax/minimax-m2.7", "minimax m2.7"),
                    ("qwen/qwen-3.6-plus-preview", "qwen 3.6+"),
                ]
            case "minimax":
                return [
                    ("MiniMax-M2.7", "MiniMax M2.7"),
                    ("MiniMax-M2.5", "MiniMax M2.5"),
                    ("MiniMax-M2.1", "MiniMax M2.1"),
                    ("MiniMax-M2", "MiniMax M2"),
                ]
            case "gemini":
                return [
                    ("gemini-3-flash-preview", "gemini 3 flash"),
                    ("gemini-3-pro", "gemini 3 pro"),
                    ("gemini-2.5-flash", "gemini 2.5 flash"),
                ]
            case "huggingface":
                return [
                    ("meta-llama/Llama-3.3-70B-Instruct", "llama 3.3 70b"),
                    ("Qwen/Qwen3-72B", "qwen 3 72b"),
                ]
            case "zai":
                return [
                    ("glm-4.7", "glm 4.7"),
                    ("glm-4.7-flash", "glm 4.7 flash"),
                ]
            case "kimi-coding":
                return [("kimi-k3-coding", "kimi k3 coding")]
            case "xiaomi":
                return [
                    ("xiaomi/mimo-v2-pro", "mimo v2 pro"),
                    ("xiaomi/mimo-v2", "mimo v2"),
                ]
            case "custom":
                return []
            case "nous":
                fallthrough
            default:
                return [
                    ("nousresearch/hermes-4-70b", "hermes 4 70b"),
                    ("nousresearch/deephermes-3-8b", "deephermes 3 8b"),
                ]
            }
        }()
        let customs = userCustomModels[modelProvider]?.map {
            (value: $0.value, label: $0.label ?? $0.value)
        } ?? []
        return customs + base
    }

    static func defaultBaseURL(for provider: String) -> String? {
        switch provider {
        case "openai": return "https://api.openai.com/v1"
        case "anthropic": return "https://api.anthropic.com/v1"
        case "openrouter": return "https://openrouter.ai/api/v1"
        case "nous": return "https://inference-api.nousresearch.com/v1"
        case "minimax": return "https://api.minimax.io/v1"
        case "gemini": return "https://generativelanguage.googleapis.com/v1beta/openai"
        case "huggingface": return "https://router.huggingface.co/v1"
        case "zai": return "https://api.z.ai/api/paas/v4"
        case "kimi-coding": return "https://api.moonshot.cn/v1"
        case "xiaomi": return "https://api.xiaomimimo.com/v1"
        case "custom": return nil  // user supplies via Advanced > Base URL
        default: return nil
        }
    }

    var modelDisplayName: String {
        availableModels.first(where: { $0.value == modelDefault })?.label
            ?? modelDefault.split(separator: "/").last.map(String.init) ?? modelDefault
    }

    func switchModel(_ model: (value: String, label: String)) {
        modelDefault = model.value
        setImmediate("model.default", value: model.value)
    }

    // MARK: - API key storage (~/.hermes/.env)

    func writeAPIKey(provider: String, key: String) {
        let envKey: String
        switch provider {
        case "openai": envKey = "OPENAI_API_KEY"
        case "anthropic": envKey = "ANTHROPIC_API_KEY"
        case "openrouter": envKey = "OPENROUTER_API_KEY"
        case "minimax": envKey = "MINIMAX_API_KEY"
        case "nous": envKey = "NOUS_API_KEY"
        case "gemini": envKey = "GEMINI_API_KEY"
        case "huggingface": envKey = "HF_TOKEN"
        case "zai": envKey = "ZAI_API_KEY"
        case "kimi-coding": envKey = "KIMI_API_KEY"
        case "xiaomi": envKey = "XIAOMI_API_KEY"
        case "custom": envKey = "OPENAI_API_KEY"  // custom maps to provider:openai in config.yaml
        default: return  // unknown provider: do nothing instead of trashing OPENROUTER_API_KEY
        }
        writeRawEnv(key: envKey, value: key)
    }

    /// Write or replace a single KEY=VALUE line in ~/.hermes/.env atomically.
    /// Idempotent: existing line for the same key is replaced, not duplicated.
    func writeRawEnv(key: String, value: String) {
        let hermesHome = ProcessInfo.processInfo.environment["HERMES_HOME"]
            ?? "\(NSHomeDirectory())/.hermes"
        let envPath = "\(hermesHome)/.env"
        try? FileManager.default.createDirectory(atPath: hermesHome, withIntermediateDirectories: true)

        var content = (try? String(contentsOfFile: envPath, encoding: .utf8)) ?? ""
        let pattern = "(?m)^" + NSRegularExpression.escapedPattern(for: key) + "=.*$"
        if let regex = try? NSRegularExpression(pattern: pattern),
           regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)) != nil {
            content = regex.stringByReplacingMatches(
                in: content,
                range: NSRange(content.startIndex..., in: content),
                withTemplate: NSRegularExpression.escapedTemplate(for: "\(key)=\(value)"))
        } else {
            if !content.isEmpty && !content.hasSuffix("\n") { content += "\n" }
            content += "\(key)=\(value)\n"
        }
        try? content.write(toFile: envPath, atomically: true, encoding: .utf8)
    }

    // MARK: - Custom model storage (UserDefaults)

    func addCustomModel(provider: String, modelID: String, label: String? = nil) {
        let entry = CustomModel(value: modelID, label: label)
        var list = userCustomModels[provider] ?? []
        guard !list.contains(where: { $0.value == modelID }) else { return }
        list.append(entry)
        userCustomModels[provider] = list
        persistCustomModels()
    }

    func removeCustomModel(provider: String, modelID: String) {
        userCustomModels[provider]?.removeAll { $0.value == modelID }
        if userCustomModels[provider]?.isEmpty == true {
            userCustomModels.removeValue(forKey: provider)
        }
        persistCustomModels()
    }

    private func persistCustomModels() {
        if let data = try? JSONEncoder().encode(userCustomModels) {
            UserDefaults.standard.set(data, forKey: userCustomModelsKey)
        }
    }

    private func loadCustomModels() {
        guard let data = UserDefaults.standard.data(forKey: userCustomModelsKey),
              let decoded = try? JSONDecoder().decode([String: [CustomModel]].self, from: data)
        else { return }
        userCustomModels = decoded
    }

    // MARK: - File watcher

    private var fileSource: DispatchSourceFileSystemObject?
    private var debounceTask: Task<Void, Never>?
    private var writeDebounceTask: Task<Void, Never>?

    // MARK: - Init

    init() {
        load()
        loadCustomModels()
        scanProfiles()
        startWatching()
    }

    deinit {
        fileSource?.cancel()
    }

    // MARK: - Load from config.yaml

    func load() {
        guard let content = try? String(contentsOfFile: configPath, encoding: .utf8),
              let yaml = (try? Yams.load(yaml: content)) as? [String: Any] else { return }

        modelDefault = yamlString(yaml, "model.default") ?? modelDefault
        modelProvider = yamlString(yaml, "model.provider") ?? modelProvider
        reasoningEffort = yamlString(yaml, "agent.reasoning_effort") ?? reasoningEffort
        maxIterations = yamlInt(yaml, "agent.max_iterations") ?? maxIterations
        streaming = yamlBool(yaml, "display.streaming") ?? streaming
        terminalBackend = yamlString(yaml, "terminal.backend") ?? terminalBackend
        sshHost = yamlString(yaml, "terminal.ssh_host") ?? sshHost
        sshUser = yamlString(yaml, "terminal.ssh_user") ?? sshUser
        sshPort = yamlInt(yaml, "terminal.ssh_port") ?? sshPort
        dockerImage = yamlString(yaml, "terminal.docker_image") ?? dockerImage

        // skip_memory can be top-level or under agent
        if let sm = yamlBool(yaml, "skip_memory") {
            skipMemory = sm
        } else if let sm = yamlBool(yaml, "agent.skip_memory") {
            skipMemory = sm
        }

        compressionBaseURLString = yamlString(yaml, "compression.summary_base_url")
    }

    // MARK: - Compression endpoint health probe

    func probeCompressionEndpoint() async -> EndpointHealth {
        guard let baseURL = compressionBaseURL else { return .notConfigured }
        let modelsURL = baseURL.appendingPathComponent("models")
        var request = URLRequest(url: modelsURL)
        request.timeoutInterval = 2.0
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .unreachable(reason: "non-HTTP response")
            }
            if (200..<300).contains(http.statusCode) { return .reachable }
            return .unreachable(reason: "HTTP \(http.statusCode)")
        } catch {
            return .unreachable(reason: error.localizedDescription)
        }
    }

    // MARK: - Write single key (atomic, debounced)

    func set(_ keyPath: String, value: Any) {
        writeDebounceTask?.cancel()
        writeDebounceTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self.writeToConfig(keyPath, value: value)
        }
    }

    /// Immediate write (no debounce) for discrete actions like button taps
    func setImmediate(_ keyPath: String, value: Any) {
        writeToConfig(keyPath, value: value)
    }

    private func writeToConfig(_ keyPath: String, value: Any) {
        guard var content = try? String(contentsOfFile: configPath, encoding: .utf8) else { return }

        let parts = keyPath.split(separator: ".").map(String.init)
        let key = parts.last!
        let section = parts.count > 1 ? parts.dropLast().joined(separator: ".") : nil

        let valueStr: String
        switch value {
        case let b as Bool:
            valueStr = b ? "true" : "false"
        case let i as Int:
            valueStr = "\(i)"
        case let d as Double:
            valueStr = String(format: "%.2f", d)
        case let s as String:
            valueStr = s
        default:
            valueStr = "\(value)"
        }

        if let section {
            // Nested key: find the section, then the key within it
            content = replaceNestedYAML(content, section: section, key: key, value: valueStr)
        } else {
            // Top-level key
            content = replaceTopLevelYAML(content, key: key, value: valueStr)
        }

        do {
            let data = content.data(using: .utf8)!
            try data.write(to: URL(fileURLWithPath: configPath), options: .atomic)
        } catch {
            print("[notchnotch] Config write error: \(error)")
        }
    }

    // MARK: - Profile scanning

    func scanProfiles() {
        let hermesHome = ProcessInfo.processInfo.environment["HERMES_HOME"]
            ?? "\(NSHomeDirectory())/.hermes"
        let profilesDir = "\(hermesHome)/profiles"
        var profiles = ["default"]
        if let contents = try? FileManager.default.contentsOfDirectory(atPath: profilesDir) {
            var isDir: ObjCBool = false
            for item in contents {
                let path = "\(profilesDir)/\(item)"
                if FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
                    profiles.append(item)
                }
            }
        }
        availableProfiles = profiles.sorted()
    }

    // MARK: - File watcher (FSEvents via GCD)

    private func startWatching() {
        let fd = open(configPath, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            self?.handleFileChange()
        }
        source.setCancelHandler {
            close(fd)
        }
        source.resume()
        fileSource = source
    }

    private func handleFileChange() {
        debounceTask?.cancel()
        debounceTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self.load()
        }
    }

    // MARK: - YAML read helpers (Yams)

    private func yamlValue(_ dict: [String: Any], _ keyPath: String) -> Any? {
        let parts = keyPath.split(separator: ".").map(String.init)
        var current: Any = dict
        for part in parts {
            guard let d = current as? [String: Any], let next = d[part] else { return nil }
            current = next
        }
        return current
    }

    private func yamlString(_ dict: [String: Any], _ keyPath: String) -> String? {
        guard let val = yamlValue(dict, keyPath) else { return nil }
        if val is NSNull { return nil }
        if let s = val as? String { return s }
        return "\(val)"
    }

    private func yamlInt(_ dict: [String: Any], _ keyPath: String) -> Int? {
        guard let val = yamlValue(dict, keyPath) else { return nil }
        if let i = val as? Int { return i }
        if let s = val as? String { return Int(s) }
        return nil
    }

    private func yamlBool(_ dict: [String: Any], _ keyPath: String) -> Bool? {
        guard let val = yamlValue(dict, keyPath) else { return nil }
        if let b = val as? Bool { return b }
        if let s = val as? String { return s.lowercased() == "true" ? true : s.lowercased() == "false" ? false : nil }
        return nil
    }

    // MARK: - YAML write helpers

    private func replaceTopLevelYAML(_ content: String, key: String, value: String) -> String {
        let pattern = "(?m)^(" + NSRegularExpression.escapedPattern(for: key) + ":\\s*).+$"
        if let regex = try? NSRegularExpression(pattern: pattern),
           regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)) != nil {
            return regex.stringByReplacingMatches(in: content, range: NSRange(content.startIndex..., in: content),
                                                   withTemplate: "$1" + NSRegularExpression.escapedTemplate(for: value))
        }
        // Key not found — append at end
        return content + "\n\(key): \(value)\n"
    }

    private func replaceNestedYAML(_ content: String, section: String, key: String, value: String) -> String {
        let sectionParts = section.split(separator: ".").map(String.init)
        let sectionKey = sectionParts.last!
        let keyIndent = String(repeating: "  ", count: sectionParts.count)

        var lines = content.components(separatedBy: "\n")
        var inSection = false
        var replaced = false

        for i in 0..<lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            if !inSection {
                if trimmed.hasPrefix(sectionKey + ":") {
                    inSection = true
                }
            } else {
                if trimmed.isEmpty { continue }
                if !lines[i].hasPrefix(keyIndent) && !trimmed.isEmpty {
                    // Left the section without finding the key — insert before this line
                    lines.insert("\(keyIndent)\(key): \(value)", at: i)
                    replaced = true
                    break
                }
                if trimmed.hasPrefix(key + ":") {
                    lines[i] = "\(keyIndent)\(key): \(value)"
                    replaced = true
                    break
                }
            }
        }

        if !replaced && inSection {
            lines.append("\(keyIndent)\(key): \(value)")
        }

        return lines.joined(separator: "\n")
    }
}

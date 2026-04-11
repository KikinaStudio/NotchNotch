import Foundation
import Combine
import Yams

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

    // Zone A: Session state (in-memory only)
    @Published var currentIteration: Int = 0
    @Published var sessionCost: Double = 0.0
    @Published var maxIterationsOverride: Int? = nil

    var effectiveMaxIterations: Int {
        maxIterationsOverride ?? maxIterations
    }

    var iterationPercentage: Double {
        guard effectiveMaxIterations > 0 else { return 0 }
        return Double(currentIteration) / Double(effectiveMaxIterations)
    }

    // Profiles
    @Published var availableProfiles: [String] = ["default"]

    // Only models with working API keys
    var availableModels: [(value: String, label: String, provider: String, baseURL: String)] {
        [
            ("MiniMax-M2.7", "m2.7", "minimax", "https://api.minimax.io/v1"),
            ("MiniMax-M2.5", "m2.5", "minimax", "https://api.minimax.io/v1"),
            ("nous/mimo-v2-pro", "mimo v2", "openrouter", "https://openrouter.ai/api/v1"),
        ]
    }

    var modelDisplayName: String {
        availableModels.first(where: { $0.value == modelDefault })?.label
            ?? modelDefault.split(separator: "/").last.map(String.init) ?? modelDefault
    }

    /// Switch model, provider, and base_url in a single atomic write
    func switchModel(_ model: (value: String, label: String, provider: String, baseURL: String)) {
        modelDefault = model.value
        modelProvider = model.provider
        guard var content = try? String(contentsOfFile: configPath, encoding: .utf8) else {
            print("[notchnotch] switchModel: cannot read \(configPath)")
            return
        }
        content = replaceNestedYAML(content, section: "model", key: "default", value: model.value)
        content = replaceNestedYAML(content, section: "model", key: "provider", value: model.provider)
        content = replaceNestedYAML(content, section: "model", key: "base_url", value: model.baseURL)
        do {
            let data = content.data(using: .utf8)!
            try data.write(to: URL(fileURLWithPath: configPath), options: .atomic)
        } catch {
            print("[notchnotch] switchModel write error: \(error)")
        }
    }

    // MARK: - File watcher

    private var fileSource: DispatchSourceFileSystemObject?
    private var debounceTask: Task<Void, Never>?
    private var writeDebounceTask: Task<Void, Never>?

    // MARK: - Init

    init() {
        load()
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

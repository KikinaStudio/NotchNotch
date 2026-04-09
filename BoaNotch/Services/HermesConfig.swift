import Foundation
import Combine

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

    // Models filtered by active provider
    var availableModels: [(value: String, label: String)] {
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
        case "minimax":
            return [
                ("MiniMax-M2.7", "m2.7"),
                ("MiniMax-M2.7-highspeed", "m2.7 fast"),
            ]
        case "google":
            return [
                ("gemini-3-flash-preview", "gemini flash"),
                ("gemini-3-pro-preview", "gemini pro"),
            ]
        default: // openrouter — proxies everything
            return [
                ("anthropic/claude-opus-4.6", "opus 4.6"),
                ("anthropic/claude-sonnet-4.6", "sonnet 4.6"),
                ("google/gemini-3-flash-preview", "gemini flash"),
                ("google/gemini-3-pro-preview", "gemini pro"),
                ("openai/gpt-4o", "gpt-4o"),
                ("openai/gpt-5", "gpt-5"),
                ("minimax/minimax-m2.7", "minimax m2.7"),
                ("qwen/qwen-3.6-plus-preview", "qwen 3.6+"),
                ("nous/mimo-v2-pro", "mimo v2 pro"),
            ]
        }
    }

    var modelDisplayName: String {
        availableModels.first(where: { $0.value == modelDefault })?.label
            ?? modelDefault.split(separator: "/").last.map(String.init) ?? modelDefault
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
        guard let content = try? String(contentsOfFile: configPath, encoding: .utf8) else { return }

        modelDefault = readYAML(content, key: "model.default") ?? modelDefault
        modelProvider = readYAML(content, key: "model.provider") ?? modelProvider
        reasoningEffort = readYAML(content, key: "agent.reasoning_effort") ?? reasoningEffort
        maxIterations = readYAMLInt(content, key: "agent.max_iterations") ?? maxIterations
        streaming = readYAMLBool(content, key: "display.streaming") ?? streaming
        terminalBackend = readYAML(content, key: "terminal.backend") ?? terminalBackend
        sshHost = readYAML(content, key: "terminal.ssh_host") ?? sshHost
        sshUser = readYAML(content, key: "terminal.ssh_user") ?? sshUser
        sshPort = readYAMLInt(content, key: "terminal.ssh_port") ?? sshPort
        dockerImage = readYAML(content, key: "terminal.docker_image") ?? dockerImage

        // skip_memory can be top-level or under agent
        if let sm = readYAMLBool(content, key: "skip_memory") {
            skipMemory = sm
        } else if let sm = readYAMLBool(content, key: "agent.skip_memory") {
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

        // Atomic write: temp file + rename
        let tmpPath = configPath + ".tmp"
        do {
            try content.write(toFile: tmpPath, atomically: true, encoding: .utf8)
            try FileManager.default.moveItem(atPath: tmpPath, toPath: configPath)
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

    // MARK: - YAML regex helpers

    /// Read a value for a potentially nested key like "agent.reasoning_effort"
    private func readYAML(_ content: String, key: String) -> String? {
        let parts = key.split(separator: ".").map(String.init)

        if parts.count == 1 {
            return matchTopLevel(content, key: parts[0])
        }

        // Nested: find section block, then key within it
        let section = parts.dropLast().joined(separator: ".")
        let leaf = parts.last!
        return matchNested(content, section: section, key: leaf)
    }

    private func readYAMLInt(_ content: String, key: String) -> Int? {
        readYAML(content, key: key).flatMap { Int($0) }
    }

    private func readYAMLBool(_ content: String, key: String) -> Bool? {
        guard let val = readYAML(content, key: key)?.lowercased() else { return nil }
        if val == "true" { return true }
        if val == "false" { return false }
        return nil
    }

    private func matchTopLevel(_ content: String, key: String) -> String? {
        // Match "key: value" at the start of a line (no indentation)
        let pattern = "(?m)^" + NSRegularExpression.escapedPattern(for: key) + ":\\s*(.+?)\\s*$"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)),
              let range = Range(match.range(at: 1), in: content) else { return nil }
        let val = String(content[range])
        return cleanYAMLValue(val)
    }

    private func matchNested(_ content: String, section: String, key: String) -> String? {
        // For "agent.reasoning_effort": find "agent:" section, then "  reasoning_effort: value"
        let sectionParts = section.split(separator: ".").map(String.init)

        // Find the section header line
        let sectionKey = sectionParts.last!
        let sectionPattern = "(?m)^" + String(repeating: "  ", count: sectionParts.count - 1) + NSRegularExpression.escapedPattern(for: sectionKey) + ":\\s*$"

        // Also try "section:" with inline value (shouldn't happen for sections but be safe)
        let lines = content.components(separatedBy: "\n")
        let indent = String(repeating: "  ", count: sectionParts.count - 1)
        let keyIndent = String(repeating: "  ", count: sectionParts.count)

        var inSection = false
        for line in lines {
            if !inSection {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if line.hasPrefix(indent) && !line.hasPrefix(keyIndent) && trimmed.hasPrefix(sectionKey + ":") {
                    inSection = true
                }
            } else {
                // We're in the section — check for the key
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty { continue }

                // If we hit a line at the same or lesser indent as the section, we've left it
                if !line.hasPrefix(keyIndent) && !trimmed.isEmpty {
                    break
                }

                if trimmed.hasPrefix(key + ":") {
                    let afterColon = trimmed.dropFirst(key.count + 1).trimmingCharacters(in: .whitespaces)
                    if !afterColon.isEmpty {
                        return cleanYAMLValue(afterColon)
                    }
                }
            }
        }
        return nil
    }

    private func cleanYAMLValue(_ val: String) -> String {
        var v = val
        // Remove inline comments
        if let commentIdx = v.firstIndex(of: "#") {
            // Only strip if preceded by whitespace (not inside a string)
            let before = v[v.startIndex..<commentIdx]
            if before.last == " " || before.last == "\t" {
                v = String(before).trimmingCharacters(in: .whitespaces)
            }
        }
        // Remove quotes
        if (v.hasPrefix("\"") && v.hasSuffix("\"")) || (v.hasPrefix("'") && v.hasSuffix("'")) {
            v = String(v.dropFirst().dropLast())
        }
        return v
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

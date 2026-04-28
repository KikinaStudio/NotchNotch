import Foundation
import Combine
import Yams

struct MemoryProviderInfo: Identifiable {
    let id: String              // "" = built-in only, otherwise plugin name
    let displayName: String
    let tagline: String
    let isLocal: Bool           // true = no cloud key needed (or env-driven endpoint only)
    let docURL: URL
    var requiresEnv: [String] = []   // populated from plugin.yaml at scan time
}

/// Read/write Hermes memory provider configuration via direct config.yaml + .env writes.
/// Documented exception to the "everything-through-chat" rule — see CLAUDE.md.
class HermesMemoryConfig: ObservableObject {
    static let shared = HermesMemoryConfig()

    @Published var currentProvider: String = ""           // "" = built-in only
    @Published var installedPluginIDs: Set<String> = []   // discovered on disk
    @Published var pluginEnvRequirements: [String: [String]] = [:]  // plugin id → required env vars

    /// Static metadata for display copy. The actual env requirements come from plugin.yaml.
    static let knownProviders: [MemoryProviderInfo] = [
        .init(id: "", displayName: "Built-in only",
              tagline: "MEMORY.md + USER.md, fully local",
              isLocal: true,
              docURL: URL(string: "https://hermes-agent.nousresearch.com/docs/user-guide/features/memory")!),
        .init(id: "hindsight", displayName: "Hindsight",
              tagline: "Knowledge graph, entity resolution, local",
              isLocal: true,
              docURL: URL(string: "https://hermes-agent.nousresearch.com/docs/user-guide/features/memory-providers#hindsight")!),
        .init(id: "holographic", displayName: "Holographic",
              tagline: "Local SQLite, FTS5 + HRR algebra",
              isLocal: true,
              docURL: URL(string: "https://hermes-agent.nousresearch.com/docs/user-guide/features/memory-providers#holographic")!),
        .init(id: "mem0", displayName: "Mem0",
              tagline: "Cloud LLM fact extraction",
              isLocal: false,
              docURL: URL(string: "https://hermes-agent.nousresearch.com/docs/user-guide/features/memory-providers#mem0")!),
        .init(id: "supermemory", displayName: "Supermemory",
              tagline: "Cloud, profile-scoped containers",
              isLocal: false,
              docURL: URL(string: "https://hermes-agent.nousresearch.com/docs/user-guide/features/memory-providers#supermemory")!),
        .init(id: "honcho", displayName: "Honcho",
              tagline: "Dialectic user modeling",
              isLocal: false,
              docURL: URL(string: "https://hermes-agent.nousresearch.com/docs/user-guide/features/memory-providers#honcho")!),
        .init(id: "openviking", displayName: "OpenViking",
              tagline: "Tiered retrieval (custom endpoint)",
              isLocal: false,
              docURL: URL(string: "https://hermes-agent.nousresearch.com/docs/user-guide/features/memory-providers#openviking")!),
        .init(id: "retaindb", displayName: "RetainDB",
              tagline: "Cloud hybrid search, 7 memory types",
              isLocal: false,
              docURL: URL(string: "https://hermes-agent.nousresearch.com/docs/user-guide/features/memory-providers#retaindb")!),
        .init(id: "byterover", displayName: "ByteRover",
              tagline: "Persistent knowledge tree (brv CLI)",
              isLocal: false,
              docURL: URL(string: "https://hermes-agent.nousresearch.com/docs/user-guide/features/memory-providers#byterover")!),
    ]

    /// Built-in is always shown. External providers shown only when their plugin.yaml exists.
    var availableProviders: [MemoryProviderInfo] {
        Self.knownProviders.compactMap { info in
            if info.id.isEmpty { return info }
            guard installedPluginIDs.contains(info.id) else { return nil }
            var copy = info
            copy.requiresEnv = pluginEnvRequirements[info.id] ?? []
            return copy
        }
    }

    init() {
        loadCurrentProvider()
        scanInstalledPlugins()
    }

    func loadCurrentProvider() {
        let configPath = "\(hermesHome)/config.yaml"
        guard let content = try? String(contentsOfFile: configPath, encoding: .utf8),
              let yaml = (try? Yams.load(yaml: content)) as? [String: Any],
              let memory = yaml["memory"] as? [String: Any],
              let provider = memory["provider"] as? String else {
            currentProvider = ""
            return
        }
        currentProvider = provider
    }

    func scanInstalledPlugins() {
        let pluginsDir = "\(hermesHome)/hermes-agent/plugins/memory"
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: pluginsDir) else {
            installedPluginIDs = []
            pluginEnvRequirements = [:]
            return
        }
        var ids = Set<String>()
        var requirements: [String: [String]] = [:]
        for entry in entries
        where !entry.hasPrefix(".") && entry != "__pycache__" && entry != "__init__.py" {
            let yamlPath = "\(pluginsDir)/\(entry)/plugin.yaml"
            guard FileManager.default.fileExists(atPath: yamlPath),
                  let content = try? String(contentsOfFile: yamlPath, encoding: .utf8),
                  let parsed = (try? Yams.load(yaml: content)) as? [String: Any] else { continue }
            ids.insert(entry)
            if let envs = parsed["requires_env"] as? [String] {
                requirements[entry] = envs
            } else {
                requirements[entry] = []
            }
        }
        installedPluginIDs = ids
        pluginEnvRequirements = requirements
    }

    func info(for providerID: String) -> MemoryProviderInfo? {
        availableProviders.first { $0.id == providerID }
    }

    /// Switch provider via direct config write. Caller must have already set the env vars
    /// via HermesConfig.shared.writeRawEnv(...) if the provider needs cloud creds.
    func switchTo(_ providerID: String) {
        HermesConfig.shared.setImmediate("memory.provider", value: providerID)
        currentProvider = providerID
    }

    /// True if every required env var has a non-empty value in ~/.hermes/.env.
    func hasRequiredEnv(for providerID: String) -> Bool {
        let required = pluginEnvRequirements[providerID] ?? []
        guard !required.isEmpty else { return true }
        let envPath = "\(hermesHome)/.env"
        guard let content = try? String(contentsOfFile: envPath, encoding: .utf8) else { return false }
        return required.allSatisfy { key in
            let pattern = "(?m)^\(NSRegularExpression.escapedPattern(for: key))=.+$"
            return (try? NSRegularExpression(pattern: pattern))?
                .firstMatch(in: content, range: NSRange(content.startIndex..., in: content)) != nil
        }
    }

    private var hermesHome: String {
        ProcessInfo.processInfo.environment["HERMES_HOME"]
            ?? "\(NSHomeDirectory())/.hermes"
    }
}

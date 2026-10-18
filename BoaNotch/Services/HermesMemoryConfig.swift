import Foundation
import Combine
import os
import Yams

struct MemoryProviderInfo: Identifiable {
    let id: String              // "" = built-in only, otherwise the name Hermes matches memory.provider against
    let displayName: String
    let tagline: String?        // French one-liner, providers listed in knownProviders only
    let isLocal: Bool           // false = cloud provider (the view shows the pip-deps hint)
    let docURL: URL
    var requiresEnv: [String] = []   // from plugin.yaml at scan time
    var isMissing = false            // memory.provider names it, but Hermes would find it nowhere on disk
}

/// Read/write Hermes memory provider configuration via direct config.yaml + .env writes.
/// Documented exception to the "everything-through-chat" rule — see CLAUDE.md.
class HermesMemoryConfig: ObservableObject {
    static let shared = HermesMemoryConfig()

    @Published var currentProvider: String = ""                           // "" = built-in only
    @Published private(set) var installedProviders: [MemoryProviderInfo] = []  // discovered on disk

    private static let providersPage = "https://hermes-agent.nousresearch.com/docs/user-guide/features/memory-providers"

    /// French copy for the providers documented by Hermes (each id is an anchor of `providersPage`).
    /// Display only: which providers exist comes from disk, see `scanInstalledPlugins`.
    private static let knownProviders: [String: (tagline: String, isLocal: Bool)] = [
        "hindsight": ("Graphe de connaissances, en local ou dans le cloud", true),
        "holographic": ("SQLite en local, recherche plein texte et algèbre HRR", true),
        "mem0": ("Extraction des faits par un LLM, dans le cloud", false),
        "supermemory": ("Cloud, conteneurs séparés par profil", false),
        "honcho": ("Modélise l'utilisateur au fil des échanges", false),
        "openviking": ("Recherche par niveaux, sur ton propre serveur", false),
        "retaindb": ("Recherche hybride dans le cloud, 7 types de mémoire", false),
        "byterover": ("Arbre de connaissances persistant (outil brv)", false),
        "memori": ("Mémoire structurée dans le cloud", false),
    ]

    static let builtIn = MemoryProviderInfo(
        id: "", displayName: "Intégrée seule",
        tagline: "MEMORY.md et USER.md, tout reste sur ce Mac",
        isLocal: true, docURL: URL(string: providersPage)!)

    /// Built-in first, then every provider Hermes would discover. The configured provider stays
    /// listed (`isMissing`) even when it's nowhere on disk: the picker is never blank while Hermes
    /// has one set.
    var availableProviders: [MemoryProviderInfo] {
        var list = [Self.builtIn] + installedProviders
        if !currentProvider.isEmpty, !installedProviders.contains(where: { $0.id == currentProvider }) {
            var missing = Self.makeInfo(id: currentProvider, label: nil)
            missing.isMissing = true
            list.append(missing)
        }
        return list
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
        // Hermes reads these names as "built-in only" (CORE_MEMORY_PROVIDER_SENTINELS, agent/memory_provider.py).
        let builtInNames: Set<String> = ["", "default", "builtin", "built-in", "none"]
        currentProvider = builtInNames.contains(provider.trimmingCharacters(in: .whitespaces).lowercased())
            ? "" : provider
    }

    /// Same discovery as Hermes (`_iter_provider_dirs`, plugins/memory/__init__.py, v0.22.2), on disk only:
    /// 1. bundled `hermes-agent/plugins/memory/<name>/`: any directory with an `__init__.py`;
    /// 2. user `$HERMES_HOME/plugins/<name>/` (plugin catalog installs, Hindsight since v0.21): only
    ///    when it looks like a memory provider, so platform plugins (homeassistant) stay out.
    /// Names starting with `_` or `.` are skipped; on a name clash the bundled one wins.
    /// Not mirrored: project `./.hermes/plugins/` (opt-in via HERMES_ENABLE_PROJECT_PLUGINS, relative to
    /// the gateway's working directory, which NotchNotch can't know) and pip entry points
    /// (`hermes_agent.memory_providers`, only listable through Python's importlib.metadata).
    func scanInstalledPlugins() {
        let fm = FileManager.default
        var found: [MemoryProviderInfo] = []
        var seen = Set<String>()
        let sources = [(dir: "\(hermesHome)/hermes-agent/plugins/memory", bundled: true),
                       (dir: "\(hermesHome)/plugins", bundled: false)]
        for source in sources {
            guard let entries = try? fm.contentsOfDirectory(atPath: source.dir) else { continue }
            for name in entries.sorted()
            where !name.hasPrefix("_") && !name.hasPrefix(".") && !seen.contains(name) {
                let dir = "\(source.dir)/\(name)"
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: dir, isDirectory: &isDir), isDir.boolValue,
                      fm.fileExists(atPath: "\(dir)/__init__.py"),
                      source.bundled || Self.looksLikeMemoryProvider(dir) else { continue }
                seen.insert(name)
                let manifest = (try? String(contentsOfFile: "\(dir)/plugin.yaml", encoding: .utf8))
                    .flatMap { (try? Yams.load(yaml: $0)) as? [String: Any] } ?? [:]
                var info = Self.makeInfo(id: name, label: manifest["label"] as? String)
                info.requiresEnv = Self.envNames(manifest["requires_env"])
                found.append(info)
            }
        }
        installedProviders = found.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
        os_log("[notchnotch] memory providers on disk: %{public}@ (memory.provider: %{public}@)", type: .info,
               installedProviders.map { "\($0.id)\($0.requiresEnv.isEmpty ? "" : " " + $0.requiresEnv.joined(separator: "+"))" }
                   .joined(separator: ", "),
               currentProvider.isEmpty ? "built-in" : currentProvider)
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
        let required = info(for: providerID)?.requiresEnv ?? []
        guard !required.isEmpty else { return true }
        let envPath = "\(hermesHome)/.env"
        guard let content = try? String(contentsOfFile: envPath, encoding: .utf8) else { return false }
        return required.allSatisfy { key in
            let pattern = "(?m)^\(NSRegularExpression.escapedPattern(for: key))=.+$"
            return (try? NSRegularExpression(pattern: pattern))?
                .firstMatch(in: content, range: NSRange(content.startIndex..., in: content)) != nil
        }
    }

    private static func makeInfo(id: String, label: String?) -> MemoryProviderInfo {
        let known = knownProviders[id]
        // Without a plugin.yaml label, Hermes's dashboard titles the name the same way.
        let name = label.flatMap { $0.isEmpty ? nil : $0 }
            ?? id.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ").capitalized
        return MemoryProviderInfo(
            id: id, displayName: name, tagline: known?.tagline, isLocal: known?.isLocal ?? true,
            docURL: URL(string: known == nil ? providersPage : "\(providersPage)#\(id)")!)
    }

    /// `_is_memory_provider_dir`: the first 8192 characters of `__init__.py` name
    /// `register_memory_provider` or `MemoryProvider`. Failing that, Hermes parses the top-level
    /// modules (`_defines_memory_provider`); here the same two shapes are matched as text
    /// (a `register_memory_provider(` call, a class deriving from `MemoryProvider` or an
    /// `import MemoryProvider as X` alias), so a commented-out one counts here and not in Hermes.
    private static func looksLikeMemoryProvider(_ dir: String) -> Bool {
        let fm = FileManager.default
        guard let initData = fm.contents(atPath: "\(dir)/__init__.py") else { return false }
        let head = String(String(decoding: initData, as: UTF8.self).prefix(8192))
        if head.contains("register_memory_provider") || head.contains("MemoryProvider") { return true }
        let modules = ((try? fm.contentsOfDirectory(atPath: dir)) ?? []).filter { $0.hasSuffix(".py") }
        return modules.contains { module in
            guard let data = fm.contents(atPath: "\(dir)/\(module)") else { return false }
            let source = String(decoding: data, as: UTF8.self)
            let range = NSRange(source.startIndex..., in: source)
            let aliases = (try? NSRegularExpression(pattern: #"\bMemoryProvider\s+as\s+(\w+)"#))?
                .matches(in: source, range: range)
                .compactMap { Range($0.range(at: 1), in: source).map { String(source[$0]) } } ?? []
            let bases = (["MemoryProvider"] + aliases).joined(separator: "|")
            let shape = try? NSRegularExpression(
                pattern: #"register_memory_provider\s*\(|^\s*class\s+\w+\s*\([^)]*\b(\#(bases))\b"#,
                options: .anchorsMatchLines)
            return shape?.firstMatch(in: source, range: range) != nil
        }
    }

    /// `requires_env` entries are bare names or `{name, description, prompt, password}` objects
    /// (`_missing_env_specs`, hermes_cli/plugins_cmd.py); entries without a name are dropped.
    private static func envNames(_ raw: Any?) -> [String] {
        ((raw as? [Any]) ?? []).compactMap { entry in
            let name = (entry as? String) ?? ((entry as? [String: Any])?["name"] as? String)
            return name?.isEmpty == false ? name : nil
        }
    }

    private var hermesHome: String {
        ProcessInfo.processInfo.environment["HERMES_HOME"]
            ?? "\(NSHomeDirectory())/.hermes"
    }
}

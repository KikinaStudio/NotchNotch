import Foundation
import CryptoKit

struct SkillInfo: Identifiable {
    let id: String
    let name: String
    let description: String
    let category: String
    let content: String
}

enum MemorySource: String {
    case user
    case learned
}

struct MemoryBlock: Identifiable {
    let id: String
    let title: String
    let content: String
    let category: String
    let source: MemorySource
}

struct MemoryCategoryGroup: Identifiable {
    let name: String
    let blocks: [MemoryBlock]
    var id: String { name }
    var count: Int { blocks.count }
}

struct WikiArticle: Identifiable {
    let id: String
    let title: String
    let content: String
    let isIndex: Bool
    let path: String
}

class BrainViewModel: ObservableObject {
    static let fallbackMemoryCategory = "Généralités"

    @Published var memoryBlocks: [MemoryBlock] = []
    @Published var userBlocks: [MemoryBlock] = []
    @Published var allMemoryBlocks: [MemoryBlock] = []
    @Published var skills: [SkillInfo] = []
    @Published var curatedSkillStates: [String: CuratedSkillState] = [:]
    @Published var wikiArticles: [WikiArticle] = []
    @Published var hasWiki = false
    @Published var wikiLastUpdated: Date?
    @Published var pendingRawCount: Int = 0
    @Published var isIngesting: Bool = false
    @Published var hasLoaded = false
    @Published var activeTab: BrainTab = .brain

    /// Hermes skills not represented by a curated card. Drives zone 2 of the
    /// Skills tab.
    var technicalSkills: [SkillInfo] {
        skills.filter { !CuratedSkillCatalog.mappedSkillIDs.contains($0.id) }
    }

    var memoryCategories: [MemoryCategoryGroup] {
        let grouped = Dictionary(grouping: allMemoryBlocks, by: \.category)
        return grouped
            .map { MemoryCategoryGroup(name: $0.key, blocks: $0.value) }
            .sorted { a, b in
                if a.name == Self.fallbackMemoryCategory { return false }
                if b.name == Self.fallbackMemoryCategory { return true }
                return a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
    }

    private var hermesHome: String {
        ProcessInfo.processInfo.environment["HERMES_HOME"]
            ?? "\(NSHomeDirectory())/.hermes"
    }

    func loadIfNeeded() {
        guard !hasLoaded else { return }
        hasLoaded = true
        reload()
    }

    func reload() {
        loadMemory()
        loadSkills()
        loadWiki()
        refreshLightMetrics()
    }

    func refreshLightMetrics() {
        pendingRawCount = countPendingRawFiles()
        wikiLastUpdated = computeWikiLastUpdated()
        resolveCuratedStates()
    }

    // MARK: - Curated skill detection

    /// Recompute the connection state of every entry in `CuratedSkillCatalog`
    /// against on-disk Hermes state. Cheap to call (small file reads, no
    /// network), safe on the 60s `refreshLightMetrics` cadence.
    func resolveCuratedStates() {
        var states: [String: CuratedSkillState] = [:]
        let envValues = readEnvFile()
        let googleScopes = readGoogleScopes()
        let googleEmail = UserDefaults.standard.string(forKey: "googleConnectedEmail")
        let hermesProviders = readHermesAuthProviders()

        for skill in CuratedSkillCatalog.all {
            switch skill.detection {
            case .envVar(let name):
                let value = envValues[name] ?? ""
                states[skill.id] = value.isEmpty ? .available : .connected(detail: nil)
            case .googleScope(let scope):
                let connected = googleScopes.contains { $0.contains(scope) }
                states[skill.id] = connected
                    ? .connected(detail: googleEmail)
                    : .available
            case .hermesAuthProvider(let id):
                states[skill.id] = hermesProviders.contains(id)
                    ? .connected(detail: nil)
                    : .available
            }
        }
        curatedSkillStates = states
    }

    private func readEnvFile() -> [String: String] {
        let envPath = (hermesHome as NSString).appendingPathComponent(".env")
        guard let raw = readFileIfExists(envPath) else { return [:] }
        var result: [String: String] = [:]
        for line in raw.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            guard let eq = trimmed.firstIndex(of: "=") else { continue }
            let key = String(trimmed[..<eq]).trimmingCharacters(in: .whitespaces)
            var value = String(trimmed[trimmed.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2 {
                value = String(value.dropFirst().dropLast())
            }
            if value.hasPrefix("'") && value.hasSuffix("'") && value.count >= 2 {
                value = String(value.dropFirst().dropLast())
            }
            result[key] = value
        }
        return result
    }

    private func readGoogleScopes() -> [String] {
        let path = (hermesHome as NSString).appendingPathComponent("google_token.json")
        guard let data = FileManager.default.contents(atPath: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let scopes = json["scopes"] as? [String]
        else { return [] }
        return scopes
    }

    private func readHermesAuthProviders() -> Set<String> {
        let path = (hermesHome as NSString).appendingPathComponent("auth.json")
        guard let data = FileManager.default.contents(atPath: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let providers = json["providers"] as? [String: Any]
        else { return [] }
        // Treat any non-null provider entry as connected.
        var ids: Set<String> = []
        for (key, value) in providers {
            if !(value is NSNull) { ids.insert(key) }
        }
        return ids
    }

    // MARK: - Memory

    private func loadMemory() {
        let memoriesDir = (hermesHome as NSString).appendingPathComponent("memories")
        let memoryPath = (memoriesDir as NSString).appendingPathComponent("MEMORY.md")
        let userPath = (memoriesDir as NSString).appendingPathComponent("USER.md")

        memoryBlocks = readFileIfExists(memoryPath).map { parseMemoryBlocks($0, source: .learned) } ?? []
        userBlocks = readFileIfExists(userPath).map { parseMemoryBlocks($0, source: .user) } ?? []
        allMemoryBlocks = userBlocks + memoryBlocks
    }

    private func parseMemoryBlocks(_ raw: String, source: MemorySource) -> [MemoryBlock] {
        raw.components(separatedBy: "§")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { block in
                let lines = block.components(separatedBy: "\n")
                    .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                let firstLine = lines.first ?? ""
                let title: String
                let category: String

                if firstLine.hasPrefix("**") && firstLine.contains("**") {
                    let stripped = firstLine.replacingOccurrences(of: "**", with: "")
                    let label = stripped.components(separatedBy: ":").first ?? "Note"
                    let clean = label.trimmingCharacters(in: .whitespaces)
                    title = clean
                    category = clean
                } else if firstLine.hasPrefix("- ") && firstLine.contains(":") {
                    let after = String(firstLine.dropFirst(2))
                    let rawLabel = after.components(separatedBy: ":").first ?? "Note"
                    title = rawLabel.trimmingCharacters(in: .whitespaces)
                    category = rawLabel
                        .replacingOccurrences(of: "**", with: "")
                        .trimmingCharacters(in: .whitespaces)
                } else if firstLine.hasPrefix("## ") {
                    let heading = String(firstLine.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    title = heading
                    category = heading
                } else {
                    title = String(firstLine.prefix(40))
                    category = Self.fallbackMemoryCategory
                }

                return MemoryBlock(
                    id: Self.contentHashId(for: block),
                    title: title,
                    content: block,
                    category: category,
                    source: source
                )
            }
    }

    /// SHA-256 hash of normalized content (trimmed, whitespace runs collapsed to
    /// single space), truncated to 16 hex chars. Case-preserving. Stable across
    /// reloads so pin state survives small formatting edits.
    private static func contentHashId(for content: String) -> String {
        let normalized = content
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let digest = SHA256.hash(data: Data(normalized.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return String(hex.prefix(16))
    }

    // MARK: - Skills

    private func loadSkills() {
        let skillsDir = (hermesHome as NSString).appendingPathComponent("skills")
        let fm = FileManager.default
        guard fm.fileExists(atPath: skillsDir) else { skills = []; return }

        var result: [SkillInfo] = []
        guard let categories = try? fm.contentsOfDirectory(atPath: skillsDir) else { skills = []; return }

        for category in categories {
            guard !category.hasPrefix(".") else { continue }
            let categoryPath = (skillsDir as NSString).appendingPathComponent(category)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: categoryPath, isDirectory: &isDir), isDir.boolValue else { continue }

            guard let skillDirs = try? fm.contentsOfDirectory(atPath: categoryPath) else { continue }
            for skillDir in skillDirs {
                guard !skillDir.hasPrefix(".") else { continue }
                let skillPath = (categoryPath as NSString).appendingPathComponent(skillDir)
                let skillMd = (skillPath as NSString).appendingPathComponent("SKILL.md")
                guard let raw = readFileIfExists(skillMd) else { continue }

                let (meta, body) = parseFrontmatter(raw)
                let name = meta["name"] ?? skillDir
                let description = meta["description"] ?? ""

                result.append(SkillInfo(
                    id: "\(category)/\(skillDir)",
                    name: name,
                    description: description,
                    category: category,
                    content: body
                ))
            }
        }

        skills = result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - Wiki

    // TODO: lint-report integration — once .lint-report.json format is
    // stable, read it here for wiki health status and surface via BrainView.

    private func loadWiki() {
        let fm = FileManager.default
        let paths = [
            (hermesHome as NSString).appendingPathComponent("brain/wiki"),
            (hermesHome as NSString).appendingPathComponent("wiki")
        ]
        guard let wikiDir = paths.first(where: { fm.fileExists(atPath: $0) }) else {
            hasWiki = false
            wikiArticles = []
            return
        }
        hasWiki = true

        guard let files = try? fm.contentsOfDirectory(atPath: wikiDir) else {
            wikiArticles = []
            return
        }

        let mdFiles = files.filter { $0.hasSuffix(".md") }.prefix(50)
        var articles: [WikiArticle] = []

        for file in mdFiles {
            let path = (wikiDir as NSString).appendingPathComponent(file)
            guard var content = readFileIfExists(path) else { continue }
            if content.utf8.count > 50_000 {
                content = String(content.prefix(50_000))
            }
            let baseName = (file as NSString).deletingPathExtension
            let title = extractFirstHeading(content) ?? baseName
            let isIndex = baseName.lowercased() == "index"

            articles.append(WikiArticle(id: baseName, title: title, content: content, isIndex: isIndex, path: path))
        }

        wikiLastUpdated = computeWikiLastUpdated()

        wikiArticles = articles.sorted {
            if $0.isIndex != $1.isIndex { return $0.isIndex }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    private func computeWikiLastUpdated() -> Date? {
        let fm = FileManager.default
        let paths = [
            (hermesHome as NSString).appendingPathComponent("brain/wiki"),
            (hermesHome as NSString).appendingPathComponent("wiki")
        ]
        guard let wikiDir = paths.first(where: { fm.fileExists(atPath: $0) }) else { return nil }
        guard let files = try? fm.contentsOfDirectory(atPath: wikiDir) else { return nil }
        return files.filter { $0.hasSuffix(".md") }.compactMap { file -> Date? in
            let path = (wikiDir as NSString).appendingPathComponent(file)
            return (try? fm.attributesOfItem(atPath: path))?[.modificationDate] as? Date
        }.max()
    }

    // MARK: - Pending raw count

    private func countPendingRawFiles() -> Int {
        let fm = FileManager.default
        let rawDir = (hermesHome as NSString).appendingPathComponent("brain/raw")
        let logPath = (hermesHome as NSString).appendingPathComponent("brain/wiki/log.md")

        let logMtime = (try? fm.attributesOfItem(atPath: logPath))?[.modificationDate] as? Date
        let subdirs = ["articles", "papers", "transcripts"]
        var count = 0

        for subdir in subdirs {
            let subdirPath = (rawDir as NSString).appendingPathComponent(subdir)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: subdirPath, isDirectory: &isDir), isDir.boolValue else { continue }
            guard let enumerator = fm.enumerator(atPath: subdirPath) else { continue }

            for case let relPath as String in enumerator {
                let baseName = (relPath as NSString).lastPathComponent
                guard baseName.hasSuffix(".md"), !baseName.hasPrefix(".") else { continue }
                let fullPath = (subdirPath as NSString).appendingPathComponent(relPath)

                if let logTime = logMtime {
                    if let fileMtime = (try? fm.attributesOfItem(atPath: fullPath))?[.modificationDate] as? Date,
                       fileMtime > logTime {
                        count += 1
                    }
                } else {
                    count += 1
                }
            }
        }

        return count
    }

    // MARK: - Helpers

    private func readFileIfExists(_ path: String) -> String? {
        guard FileManager.default.fileExists(atPath: path),
              let data = FileManager.default.contents(atPath: path),
              let str = String(data: data, encoding: .utf8),
              !str.isEmpty else { return nil }
        return str
    }

    private func parseFrontmatter(_ raw: String) -> (meta: [String: String], body: String) {
        guard raw.hasPrefix("---") else { return ([:], raw) }
        let lines = raw.components(separatedBy: "\n")
        guard lines.count > 2 else { return ([:], raw) }

        var endIndex: Int?
        for i in 1..<lines.count {
            if lines[i].trimmingCharacters(in: .whitespaces) == "---" {
                endIndex = i
                break
            }
        }
        guard let end = endIndex else { return ([:], raw) }

        var meta: [String: String] = [:]
        for i in 1..<end {
            let line = lines[i]
            guard let colonRange = line.range(of: ": ") else { continue }
            let key = String(line[line.startIndex..<colonRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            let value = String(line[colonRange.upperBound...]).trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty, !key.hasPrefix(" ") else { continue }
            meta[key] = value
        }

        let body = lines.dropFirst(end + 1).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return (meta, body)
    }

    private func extractFirstHeading(_ content: String) -> String? {
        for line in content.components(separatedBy: "\n") {
            if line.hasPrefix("# ") {
                return String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }
}

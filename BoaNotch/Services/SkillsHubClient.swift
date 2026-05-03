import Foundation

/// One row from the Hermes Skills Hub catalogue. The hub helper
/// (`hermes_cli.skills_hub.browse_skills`) returns name/description/source/trust
/// but no `identifier` — that is resolved later by `inspect()` when the user
/// drills into preview.
struct HubSkill: Identifiable, Hashable {
    let name: String
    let description: String
    let source: String
    let trust: String

    /// We use `<source>:<name>` so identical names from different sources don't
    /// collapse in `Identifiable`. The actual install identifier comes from
    /// `inspect()` (Hermes resolves short names server-side).
    var id: String { "\(source):\(name)" }
}

struct HubSkillDetail: Equatable {
    let identifier: String
    let name: String
    let description: String
    let source: String
    let trust: String
    let tags: [String]
    let skillMdPreview: String
    let requiresEnv: [String]
}

enum SkillsHubError: Error, LocalizedError {
    case hermesUnreachable
    case rateLimited
    case dangerous
    case alreadyInstalled
    case generic(String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .hermesUnreachable:
            return "Impossible de joindre ton agent, vérifie qu'il tourne."
        case .rateLimited:
            return "Trop de requêtes vers GitHub, réessaie dans quelques minutes."
        case .dangerous:
            return "Cette capacité a été refusée pour des raisons de sécurité."
        case .alreadyInstalled:
            return "Cette capacité est déjà ajoutée à ton agent."
        case .generic(let msg):
            return "Une erreur est survenue : \(msg)"
        case .decoding(let msg):
            return "Réponse de ton agent illisible : \(msg)"
        }
    }
}

/// Direct bridge to the Hermes Skills Hub. See CLAUDE.md "Documented exception
/// — Skills Hub" : we deliberately bypass chat for browse/inspect/install
/// because chat-mediated catalogue browsing would route through the LLM, cost
/// time/money, and be model-dependent. The trade-off is tight coupling to the
/// internal layout of `~/.hermes/hermes-agent`.
///
/// All paths are resolved at call time via `FileManager.default.homeDirectoryForCurrentUser`
/// — never hardcoded.
final class SkillsHubClient {
    static let shared = SkillsHubClient()

    // MARK: - Browse

    /// Single-page catalogue dump (size 100). The helper already deduplicates by
    /// name preferring higher trust (official > trusted > community) and sorts
    /// "official first". We filter to `{official, skills-sh}` callers-side.
    func browse() async throws -> [HubSkill] {
        let raw = try await runPythonHelper(
            extraEnv: [:],
            script: """
            import os, sys, json
            sys.path.insert(0, os.environ['HERMES_AGENT_DIR'])
            try:
                from hermes_cli.skills_hub import browse_skills
            except Exception as e:
                print(json.dumps({'error': 'import_failed', 'detail': str(e)}))
                sys.exit(0)
            try:
                res = browse_skills(page=1, page_size=100, source='all')
                print(json.dumps(res, ensure_ascii=False))
            except Exception as e:
                print(json.dumps({'error': 'call_failed', 'detail': str(e)}))
            """,
            timeout: 30
        )
        guard let data = raw.data(using: .utf8) else {
            throw SkillsHubError.decoding("not utf8")
        }
        guard let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SkillsHubError.decoding("not an object")
        }
        if let err = decoded["error"] as? String {
            let detail = (decoded["detail"] as? String) ?? ""
            throw SkillsHubError.generic("\(err): \(detail)")
        }
        guard let items = decoded["items"] as? [[String: Any]] else {
            throw SkillsHubError.decoding("missing items")
        }
        return items.compactMap { item -> HubSkill? in
            guard let name = item["name"] as? String,
                  let description = item["description"] as? String,
                  let source = item["source"] as? String,
                  let trust = item["trust"] as? String else { return nil }
            return HubSkill(name: name, description: description, source: source, trust: trust)
        }
    }

    // MARK: - Inspect

    /// Fetches the full description, identifier, and 50-line `SKILL.md` preview
    /// for a given short name (e.g. "1password"). Hermes's
    /// `_resolve_short_name` performs the lookup; if the name is ambiguous
    /// across multiple sources, the helper returns `None` (we map to a generic
    /// "introuvable" error).
    func inspect(name: String) async throws -> HubSkillDetail {
        let raw = try await runPythonHelper(
            extraEnv: ["SKILL_NAME": name],
            script: """
            import os, sys, json
            sys.path.insert(0, os.environ['HERMES_AGENT_DIR'])
            try:
                from hermes_cli.skills_hub import inspect_skill
            except Exception as e:
                print(json.dumps({'error': 'import_failed', 'detail': str(e)}))
                sys.exit(0)
            try:
                r = inspect_skill(os.environ['SKILL_NAME'])
                if r:
                    print(json.dumps(r, ensure_ascii=False))
                else:
                    print(json.dumps({'error': 'not_found'}))
            except Exception as e:
                print(json.dumps({'error': 'call_failed', 'detail': str(e)}))
            """,
            timeout: 45
        )
        guard let data = raw.data(using: .utf8) else {
            throw SkillsHubError.decoding("not utf8")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SkillsHubError.decoding("not an object")
        }
        if let err = json["error"] as? String {
            if err == "not_found" {
                throw SkillsHubError.generic("Capacité introuvable.")
            }
            let detail = (json["detail"] as? String) ?? ""
            throw SkillsHubError.generic("\(err): \(detail)")
        }
        let identifier = (json["identifier"] as? String) ?? name
        let displayName = (json["name"] as? String) ?? name
        let description = (json["description"] as? String) ?? ""
        let source = (json["source"] as? String) ?? ""
        let tags = (json["tags"] as? [String]) ?? []
        let preview = (json["skill_md_preview"] as? String) ?? ""
        return HubSkillDetail(
            identifier: identifier,
            name: displayName,
            description: description,
            source: source,
            trust: "",
            tags: tags,
            skillMdPreview: preview,
            requiresEnv: parseRequiresEnv(from: preview)
        )
    }

    // MARK: - Install

    /// CLI subprocess: `venv/bin/python3 hermes skills install <id> --yes`.
    /// `--yes` corresponds to `skip_confirm=True` in `do_install`, suppressing
    /// the disclaimer prompt that would otherwise hang waiting for stdin.
    /// Note: even on success, "Installation blocked" can appear in stdout when
    /// the post-fetch security scan returns `dangerous` — the Python function
    /// `return`s without raising, so exit code is 0. We belt-and-suspender by
    /// re-classifying a successful exit if the output flags a block.
    func install(identifier: String) async throws {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let pythonURL = homeDir.appendingPathComponent(".hermes/hermes-agent/venv/bin/python3")
        let scriptPath = homeDir.appendingPathComponent(".hermes/hermes-agent/hermes").path
        let cwdURL = homeDir.appendingPathComponent(".hermes/hermes-agent")
        let timeout: TimeInterval = 180

        // Quick sanity check before spawning.
        guard FileManager.default.isExecutableFile(atPath: pythonURL.path) else {
            throw SkillsHubError.hermesUnreachable
        }

        let result: (Int32, String) = try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = pythonURL
            process.arguments = [scriptPath, "skills", "install", identifier, "--yes"]
            process.currentDirectoryURL = cwdURL
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            do {
                try process.run()
            } catch {
                throw SkillsHubError.hermesUnreachable
            }
            let watchdog = DispatchWorkItem {
                if process.isRunning { process.terminate() }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
            process.waitUntilExit()
            watchdog.cancel()
            let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            return (process.terminationStatus, stdout + "\n" + stderr)
        }.value

        let (exit, output) = result
        let lower = output.lowercased()
        if exit == 0 {
            // Hermes prints "Installation blocked" on a dangerous verdict but
            // does not raise — so a 0 exit isn't a green light on its own.
            if lower.contains("installation blocked") {
                throw classifyError(output)
            }
            return
        }
        throw classifyError(output)
    }

    // MARK: - Error classification

    private func classifyError(_ output: String) -> SkillsHubError {
        let lower = output.lowercased()
        if lower.contains("60 requests/hour") || lower.contains("rate limit") || lower.contains("rate-limit") {
            return .rateLimited
        }
        if lower.contains("dangerous") || lower.contains("installation blocked") {
            return .dangerous
        }
        if lower.contains("already installed") {
            return .alreadyInstalled
        }
        if lower.contains("connection refused") || lower.contains("could not connect")
            || lower.contains("unable to connect") {
            return .hermesUnreachable
        }
        if lower.contains("modulenotfounderror") || lower.contains("no such file") {
            return .generic("ton agent semble mal configuré")
        }
        let firstLine = output
            .components(separatedBy: "\n")
            .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })?
            .trimmingCharacters(in: .whitespaces) ?? "détails indisponibles"
        return .generic(String(firstLine.prefix(120)))
    }

    // MARK: - SKILL.md frontmatter parsing (requires_env)

    private func parseRequiresEnv(from preview: String) -> [String] {
        guard preview.hasPrefix("---") else { return [] }
        let lines = preview.components(separatedBy: "\n")
        guard lines.count > 1 else { return [] }
        var inFrontmatter = true
        var index = 1
        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if trimmed == "---" { inFrontmatter = false; break }
            guard inFrontmatter else { break }
            if trimmed.hasPrefix("requires_env:") {
                let rhs = String(trimmed.dropFirst("requires_env:".count))
                    .trimmingCharacters(in: .whitespaces)
                if rhs.hasPrefix("[") && rhs.hasSuffix("]") {
                    let inner = String(rhs.dropFirst().dropLast())
                    return inner.components(separatedBy: ",")
                        .map { stripQuotes($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
                        .filter { !$0.isEmpty }
                }
                var entries: [String] = []
                var j = index + 1
                while j < lines.count {
                    let l = lines[j].trimmingCharacters(in: .whitespaces)
                    if l.hasPrefix("- ") {
                        entries.append(stripQuotes(String(l.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)))
                    } else if l.isEmpty {
                        j += 1
                        continue
                    } else {
                        break
                    }
                    j += 1
                }
                return entries
            }
            index += 1
        }
        return []
    }

    private func stripQuotes(_ s: String) -> String {
        var out = s
        if out.hasPrefix("\""), out.hasSuffix("\""), out.count >= 2 {
            out = String(out.dropFirst().dropLast())
        }
        if out.hasPrefix("'"), out.hasSuffix("'"), out.count >= 2 {
            out = String(out.dropFirst().dropLast())
        }
        return out
    }

    // MARK: - Subprocess helper

    /// Runs an inline Python snippet in the Hermes venv with `HERMES_AGENT_DIR`
    /// + caller-supplied env vars set. Returns the LAST non-empty stdout line
    /// (helpers occasionally print log noise before the JSON payload).
    private func runPythonHelper(extraEnv: [String: String], script: String, timeout: TimeInterval) async throws -> String {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let pythonURL = homeDir.appendingPathComponent(".hermes/hermes-agent/venv/bin/python3")
        let cwdURL = homeDir.appendingPathComponent(".hermes/hermes-agent")
        let agentDirPath = cwdURL.path

        guard FileManager.default.isExecutableFile(atPath: pythonURL.path) else {
            throw SkillsHubError.hermesUnreachable
        }

        var env = ProcessInfo.processInfo.environment
        env["HERMES_AGENT_DIR"] = agentDirPath
        for (k, v) in extraEnv { env[k] = v }

        return try await Task.detached(priority: .userInitiated) { () throws -> String in
            let process = Process()
            process.executableURL = pythonURL
            process.arguments = ["-c", script]
            process.currentDirectoryURL = cwdURL
            process.environment = env
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            do {
                try process.run()
            } catch {
                throw SkillsHubError.hermesUnreachable
            }
            let watchdog = DispatchWorkItem {
                if process.isRunning { process.terminate() }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
            process.waitUntilExit()
            watchdog.cancel()
            let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let trimmed = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                let stderrSnippet = String(stderr.prefix(120))
                throw SkillsHubError.decoding("réponse vide. stderr: \(stderrSnippet)")
            }
            // Helpers occasionally log to stdout before the JSON payload — the
            // payload is on the last non-empty line.
            let lastLine = trimmed
                .components(separatedBy: "\n")
                .reversed()
                .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? trimmed
            return lastLine
        }.value
    }
}

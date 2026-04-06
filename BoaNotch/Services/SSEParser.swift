import Foundation

enum SSEEvent {
    case delta(String)
    case thinking(String)
    case toolCall(String)
    case done
}

struct SSEParser {
    private var insideThink = false
    private var toolMode = false
    private var sawCleanResponse = false
    private var pendingRegular = ""

    mutating func parse(line: String) -> [SSEEvent] {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmed.hasPrefix("data: ") else { return [] }

        let data = String(trimmed.dropFirst(6))

        if data == "[DONE]" {
            // Flush any pending regular content before emitting done
            var events: [SSEEvent] = []
            if !pendingRegular.isEmpty {
                events.append(routeSingleContent(pendingRegular))
                pendingRegular = ""
            }
            insideThink = false
            toolMode = false
            sawCleanResponse = false
            events.append(.done)
            return events
        }

        guard let jsonData = data.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let delta = firstChoice["delta"] as? [String: Any]
        else {
            return []
        }

        // Explicit tool_calls in delta (OpenAI format)
        if let toolCalls = delta["tool_calls"] as? [[String: Any]] {
            toolMode = true
            sawCleanResponse = false
            var toolText = ""
            for tc in toolCalls {
                if let function = tc["function"] as? [String: Any] {
                    if let name = function["name"] as? String, !name.isEmpty {
                        toolText += "→ \(name) "
                    }
                    if let args = function["arguments"] as? String, !args.isEmpty {
                        toolText += args
                    }
                }
            }
            if !toolText.isEmpty { return [.toolCall(toolText)] }
        }

        guard let content = delta["content"] as? String, !content.isEmpty else {
            return []
        }

        // Route through think tag detection first
        return routeContent(content)
    }

    private mutating func routeContent(_ text: String) -> [SSEEvent] {
        var thinkBuf = ""
        var regularBuf = pendingRegular
        pendingRegular = ""
        var remaining = text

        while !remaining.isEmpty {
            if insideThink {
                if let endRange = remaining.range(of: "</think>") {
                    thinkBuf += String(remaining[remaining.startIndex..<endRange.lowerBound])
                    remaining = String(remaining[endRange.upperBound...])
                    insideThink = false
                } else {
                    thinkBuf += remaining
                    remaining = ""
                }
            } else {
                if let startRange = remaining.range(of: "<think>") {
                    regularBuf += String(remaining[remaining.startIndex..<startRange.lowerBound])
                    remaining = String(remaining[startRange.upperBound...])
                    insideThink = true
                } else {
                    regularBuf += remaining
                    remaining = ""
                }
            }
        }

        var events: [SSEEvent] = []

        if !thinkBuf.isEmpty {
            events.append(.thinking(thinkBuf))
        }

        if !regularBuf.isEmpty {
            events.append(routeSingleContent(regularBuf))
        }

        return events
    }

    /// Route a single piece of non-thinking content to the appropriate event type
    private mutating func routeSingleContent(_ regularBuf: String) -> SSEEvent {
        // Strong markers (emojis, XML tags) always enter tool mode, even after clean response
        if isStrongToolMarker(regularBuf) {
            toolMode = true
            sawCleanResponse = false
            return .toolCall(regularBuf)
        }

        // Once we've seen clean response, stay in delta (keywords in text won't re-trigger)
        if sawCleanResponse {
            return .delta(regularBuf)
        }

        // Weak heuristic tool detection (only before clean response)
        if looksLikeToolExecution(regularBuf) {
            toolMode = true
            return .toolCall(regularBuf)
        }

        if toolMode {
            if looksLikeCleanResponse(regularBuf) {
                toolMode = false
                sawCleanResponse = true
                return .delta(regularBuf)
            }
            return .toolCall(regularBuf)
        }

        return .delta(regularBuf)
    }

    // MARK: - Strong tool markers (emojis, XML tags — always trigger tool mode)

    private func isStrongToolMarker(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return false }

        // Hermes tool execution emojis
        if t.contains("💻") || t.contains("🔧") || t.contains("⚙️")
            || t.contains("🔎") || t.contains("🔍") || t.contains("📚")
            || t.contains("📋") || t.contains("📧") || t.contains("✍️") || t.contains("📖") { return true }

        // Hermes XML tags
        if t.contains("<tool_call>") || t.contains("</tool_call>") { return true }
        if t.contains("<tool_response>") || t.contains("</tool_response>") { return true }

        return false
    }

    // MARK: - Weak heuristic (shell patterns, command keywords — only before clean response)

    private func looksLikeToolExecution(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return toolMode }

        // Shell operators and redirects
        if t.contains("2>/dev/null") || t.contains("2>&1") { return true }
        if t.contains(" && ") || t.contains(" || ") { return true }
        if t.contains(" | head") || t.contains(" | tail") || t.contains(" | grep") { return true }

        // Variable assignments and references
        if t.contains("GAPI=") || t.contains("$GAPI") || t.contains("$HOME") { return true }

        // Command invocations
        if t.hasPrefix("python ") || t.hasPrefix("bash ") || t.hasPrefix("sh ") { return true }
        if t.contains(".py ") || t.contains(".py\"") || t.contains(".py`") { return true }
        if t.hasPrefix("find /") || t.hasPrefix("echo ") || t.hasPrefix("cat ") { return true }
        if t.hasPrefix("curl ") || t.hasPrefix("wget ") { return true }

        // Hermes skill paths
        if t.contains(".hermes/skills/") || t.contains(".hermes/cache/") { return true }

        // Command flags pattern
        if t.contains(" --max") || t.contains(" --format") || t.contains(" -name ") { return true }
        if t.contains(" --output") || t.contains(" --page-size") { return true }

        // Just a tilde (current dir indicator) or backtick blocks
        if t == "~" || t == "```" { return true }
        if t.hasPrefix("```") && t.count < 20 { return true }

        // chmod, mkdir type commands
        if t.hasPrefix("chmod ") || t.hasPrefix("mkdir ") || t.hasPrefix("cd ") { return true }

        return false
    }

    // MARK: - Clean response detection (transition out of tool mode)

    private func looksLikeCleanResponse(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return false }

        // French pronouns/determiners (handles small SSE tokens)
        let shortStarters = ["Tu", "Je", "Il", "On", "Ce", "Un", "Ça"]
        if shortStarters.contains(t) { return true }

        // Uppercase word (3+ chars, not ALL_CAPS like "SSH", "JSON", "GAPI")
        if let first = t.first, first.isLetter && first.isUppercase && t.count > 2 {
            let isAllCaps = t.allSatisfy { $0.isUppercase || $0 == "_" || $0 == "-" }
            if !isAllCaps && !t.contains("&&") && !t.contains("||") && !t.contains("2>")
                && !t.contains("$GAPI") && !t.contains("GAPI=") && !t.contains(".py") {
                return true
            }
        }

        // Numbered list (structured response: "1. Plus récent...", "2. ...")
        if let first = t.first, first.isNumber, t.count > 4, t.contains(". ") { return true }

        // Common French/English response patterns
        let patterns = ["Tu ", "Je ", "Il ", "Voici", "J'ai", "Il y a", "Le ", "La ", "Les ",
                        "Here", "I found", "You have", "No ", "Oui", "Non", "D'accord", "Bien",
                        "OK", "C'est", "Aucun", "Pas de", "Je n'ai", "Désolé", "Him"]
        for p in patterns {
            if t.hasPrefix(p) { return true }
        }

        return false
    }
}

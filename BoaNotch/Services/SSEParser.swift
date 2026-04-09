import Foundation

enum SSEEvent {
    case delta(String)
    case thinking(String)
    case toolCall(String)
    case done
}

struct SSEParser {
    private var insideThink = false

    mutating func parse(line: String) -> [SSEEvent] {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmed.hasPrefix("data: ") else { return [] }

        let data = String(trimmed.dropFirst(6))

        guard let jsonData = data.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let event = json["event"] as? String
        else {
            return []
        }

        switch event {
        case "message.delta":
            guard let delta = json["delta"] as? String, !delta.isEmpty else { return [] }
            return routeContent(delta)

        case "tool.started":
            let tool = json["tool"] as? String ?? "tool"
            let preview = json["preview"] as? String
            let text = preview != nil ? "→ \(tool) \(preview!)" : "→ \(tool)"
            return [.toolCall(text + "\n")]

        case "tool.completed":
            let tool = json["tool"] as? String ?? "tool"
            let duration = json["duration"] as? Double ?? 0
            let isError = json["error"] as? Bool ?? false
            let symbol = isError ? "✗" : "✓"
            let text = "\(symbol) \(tool) (\(String(format: "%.1f", duration))s)"
            return [.toolCall(text + "\n")]

        case "run.completed", "run.failed":
            return [.done]

        default:
            return []
        }
    }

    // MARK: - Think tag routing (simple, reliable — not heuristic)

    private mutating func routeContent(_ text: String) -> [SSEEvent] {
        var events: [SSEEvent] = []
        var remaining = text

        while !remaining.isEmpty {
            if insideThink {
                if let endRange = remaining.range(of: "</think>") {
                    let thinkText = String(remaining[remaining.startIndex..<endRange.lowerBound])
                    if !thinkText.isEmpty { events.append(.thinking(thinkText)) }
                    remaining = String(remaining[endRange.upperBound...])
                    insideThink = false
                } else {
                    events.append(.thinking(remaining))
                    remaining = ""
                }
            } else {
                if let startRange = remaining.range(of: "<think>") {
                    let regularText = String(remaining[remaining.startIndex..<startRange.lowerBound])
                    if !regularText.isEmpty { events.append(.delta(regularText)) }
                    remaining = String(remaining[startRange.upperBound...])
                    insideThink = true
                } else {
                    events.append(.delta(remaining))
                    remaining = ""
                }
            }
        }

        return events
    }
}

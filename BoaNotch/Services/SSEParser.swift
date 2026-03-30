import Foundation

enum SSEEvent {
    case delta(String)
    case done
}

struct SSEParser {
    func parse(line: String) -> SSEEvent? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmed.hasPrefix("data: ") else { return nil }

        let data = String(trimmed.dropFirst(6))

        if data == "[DONE]" {
            return .done
        }

        guard let jsonData = data.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let delta = firstChoice["delta"] as? [String: Any],
              let content = delta["content"] as? String
        else {
            return nil
        }

        return .delta(content)
    }
}

import Foundation

class HermesClient {
    private let baseURL = "http://localhost:8642"

    /// The current NotchNotch session ID. Persisted across launches so each
    /// conversation maps to a single session row in Hermes's state.db.
    var sessionId: String? {
        didSet {
            if let id = sessionId, !id.isEmpty {
                UserDefaults.standard.set(id, forKey: "notchnotchSessionId")
            } else {
                UserDefaults.standard.removeObject(forKey: "notchnotchSessionId")
            }
        }
    }

    init() {
        self.sessionId = UserDefaults.standard.string(forKey: "notchnotchSessionId")
    }

    /// Ensure a session ID exists before sending a request. Generates a fresh
    /// `notchnotch-<uuid>` if none is set so every chat lands in a single row.
    func ensureSessionId() -> String {
        if let id = sessionId, !id.isEmpty { return id }
        let fresh = "notchnotch-\(UUID().uuidString.lowercased())"
        sessionId = fresh
        return fresh
    }

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300
        config.timeoutIntervalForResource = 600
        return URLSession(configuration: config)
    }()

    // MARK: - Server-side conversation persistence

    var conversationId: String {
        get {
            if let id = UserDefaults.standard.string(forKey: "hermesConversationId") {
                return id
            }
            let id = UUID().uuidString
            UserDefaults.standard.set(id, forKey: "hermesConversationId")
            return id
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "hermesConversationId")
        }
    }

    func resetConversation() {
        conversationId = UUID().uuidString
    }

    // MARK: - Non-streaming conversation via /v1/responses

    struct ResponseResult {
        let content: String
        let thinkingContent: String
        let toolCalls: String
        let promptTokens: Int?
        let completionTokens: Int?
    }

    func sendResponse(input: String, systemContext: String? = nil) async throws -> ResponseResult {
        guard let url = URL(string: "\(baseURL)/v1/responses") else {
            throw HermesError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Always send a session header so all turns of one NotchNotch
        // conversation accumulate in a single state.db row.
        request.setValue(ensureSessionId(), forHTTPHeaderField: "X-Hermes-Session-Id")

        let inputValue: Any
        if let systemContext {
            inputValue = [
                ["role": "system", "content": systemContext],
                ["role": "user", "content": input]
            ]
        } else {
            inputValue = input
        }

        let body: [String: Any] = [
            "model": "hermes-agent",
            "input": inputValue,
            "conversation": conversationId,
            "store": true,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HermesError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            let bodyString = String(data: data, encoding: .utf8) ?? ""
            if bodyString.isEmpty {
                throw HermesError.httpError(httpResponse.statusCode)
            }
            throw HermesError.httpErrorWithBody(httpResponse.statusCode, bodyString)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let output = json["output"] as? [[String: Any]] else {
            throw HermesError.invalidResponse
        }

        let parsed = parseOutput(output)

        var promptTokens: Int? = nil
        var completionTokens: Int? = nil
        if let usage = json["usage"] as? [String: Any] {
            promptTokens = usage["input_tokens"] as? Int
            completionTokens = usage["output_tokens"] as? Int
        }

        return ResponseResult(
            content: parsed.content,
            thinkingContent: parsed.thinkingContent,
            toolCalls: parsed.toolCalls,
            promptTokens: promptTokens,
            completionTokens: completionTokens
        )
    }

    private func parseOutput(_ output: [[String: Any]]) -> ResponseResult {
        var content = ""
        var thinkingContent = ""
        var toolCalls = ""
        // Map call_id → tool name for formatting tool outputs
        var callNames: [String: String] = [:]

        for item in output {
            guard let type = item["type"] as? String else { continue }
            switch type {
            case "function_call":
                let name = item["name"] as? String ?? "tool"
                let callId = item["call_id"] as? String ?? ""
                callNames[callId] = name
                let args = item["arguments"] as? String ?? ""
                let preview = String(args.prefix(60))
                toolCalls += "→ \(name) \(preview)\n"
            case "function_call_output":
                let callId = item["call_id"] as? String ?? ""
                let name = callNames[callId] ?? "tool"
                toolCalls += "✓ \(name)\n"
            case "reasoning":
                thinkingContent = item["text"] as? String ?? ""
            case "message":
                if let contentArray = item["content"] as? [[String: Any]] {
                    for part in contentArray {
                        if part["type"] as? String == "output_text" {
                            content += part["text"] as? String ?? ""
                        }
                    }
                }
            default:
                print("[notchnotch] Unknown output item type: \(type)")
                break
            }
        }

        return ResponseResult(content: content, thinkingContent: thinkingContent, toolCalls: toolCalls, promptTokens: nil, completionTokens: nil)
    }

    // MARK: - Non-streaming via /v1/responses (brain saves)

    func sendCompletion(messages: [[String: String]]) async throws {
        guard let url = URL(string: "\(baseURL)/v1/responses") else {
            throw HermesError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": "hermes-agent",
            "input": messages,
            "store": false,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HermesError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            let bodyString = String(data: data, encoding: .utf8) ?? ""
            if bodyString.isEmpty {
                throw HermesError.httpError(httpResponse.statusCode)
            }
            throw HermesError.httpErrorWithBody(httpResponse.statusCode, bodyString)
        }
    }

    // MARK: - Title generation (ChatGPT-style auto-name)

    /// Ask Hermes to summarize the first exchange into a 3-7 word title.
    /// Bypasses session/conversation chaining (`store: false`, no headers) so
    /// the call is purely transactional and never pollutes chat history.
    /// Returns nil on any failure — title generation is best-effort.
    func generateTitle(userMessage: String, assistantResponse: String) async -> String? {
        guard let url = URL(string: "\(baseURL)/v1/responses") else { return nil }

        let userSnippet = String(userMessage.prefix(500))
        let assistantSnippet = String(assistantResponse.prefix(500))
        let prompt = """
        Generate a short, descriptive title (3-7 words) for a conversation that starts with the following exchange. \
        The title should capture the main topic or intent. \
        Return ONLY the title text, nothing else. No quotes, no punctuation at the end, no prefixes.

        User: \(userSnippet)

        Assistant: \(assistantSnippet)
        """

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let body: [String: Any] = [
            "model": "hermes-agent",
            "input": prompt,
            "store": false,
        ]
        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        request.httpBody = httpBody

        do {
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let output = json["output"] as? [[String: Any]] else { return nil }
            let parsed = parseOutput(output)
            return cleanTitle(parsed.content)
        } catch {
            return nil
        }
    }

    /// Strip quotes/trailing punctuation/whitespace and clamp length.
    private func cleanTitle(_ raw: String) -> String? {
        var t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Drop wrapping quotes if present.
        let quoteSet = CharacterSet(charactersIn: "\"'`“”‘’«»")
        t = t.trimmingCharacters(in: quoteSet)
        // Drop trailing punctuation.
        while let last = t.last, ".!?;,".contains(last) { t.removeLast() }
        t = t.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        if t.count > 80 { t = String(t.prefix(80)) }
        return t
    }

    // MARK: - Health check

    func healthCheck() async -> Bool {
        guard let url = URL(string: "\(baseURL)/health") else { return false }
        do {
            let (data, response) = try await session.data(from: url)
            let ok = (response as? HTTPURLResponse)?.statusCode == 200
            if !ok {
                let body = String(data: data, encoding: .utf8) ?? "empty"
                print("[notchnotch] Health check failed: status=\((response as? HTTPURLResponse)?.statusCode ?? -1) body=\(body)")
            } else {
                print("[notchnotch] Health check OK")
            }
            return ok
        } catch {
            print("[notchnotch] Health check error: \(error)")
            return false
        }
    }
}

enum HermesError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(Int)
    case httpErrorWithBody(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid API URL"
        case .invalidResponse: return "Bad response"
        case .httpError(let code): return "HTTP \(code)"
        case .httpErrorWithBody(let code, let body): return "HTTP \(code): \(body)"
        }
    }
}

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

        let parsed = Self.postProcessResult(parseOutput(output))

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

    // MARK: - Streaming conversation via /v1/responses (SSE)

    /// Live event surfaced by `streamResponse` to the caller. Text and
    /// thinking deltas are opaque string chunks (can be a single char or
    /// a full paragraph depending on provider). Tool events fire once
    /// per tool lifecycle (`started` on the function_call added event,
    /// `completed` on the function_call_output added event). `completed`
    /// fires exactly once with final usage; `failed` fires on
    /// `response.failed` and `streamResponse` then throws.
    enum StreamEvent {
        case textDelta(String)
        case thinkingDelta(String)
        /// Fired when an opening `<think>` tag is detected in the output
        /// text stream. The bubble uses this to switch to a live thinking
        /// preview until `thinkingEnded` arrives.
        case thinkingStarted
        case thinkingEnded
        case toolCallStarted(id: String, name: String, argsPreview: String)
        case toolCallCompleted(id: String, name: String, resultPreview: String)
        case completed(promptTokens: Int?, completionTokens: Int?)
        case failed(String)
    }

    /// Streaming equivalent of `sendResponse`. Subscribes to Hermes's
    /// OpenAI-Responses SSE stream, forwards live events to `onEvent`,
    /// and returns the same `ResponseResult` the non-streaming path
    /// would. If the server replies with `application/json` instead of
    /// `text/event-stream` (older Hermes builds silently ignore
    /// `stream: true`), falls back to batch parsing and emits a single
    /// synthetic `.completed`.
    func streamResponse(
        input: String,
        systemContext: String? = nil,
        onEvent: @escaping (StreamEvent) -> Void
    ) async throws -> ResponseResult {
        guard let url = URL(string: "\(baseURL)/v1/responses") else {
            throw HermesError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
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
            "stream": true,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await session.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HermesError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            var accum = Data()
            for try await byte in bytes {
                accum.append(byte)
                if accum.count > 16_384 { break }
            }
            let bodyString = String(data: accum, encoding: .utf8) ?? ""
            if bodyString.isEmpty {
                throw HermesError.httpError(httpResponse.statusCode)
            }
            throw HermesError.httpErrorWithBody(httpResponse.statusCode, bodyString)
        }

        let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? ""
        let isSSE = contentType.lowercased().contains("text/event-stream")

        if !isSSE {
            // Server ignored stream:true — batch-parse and emit a single completed.
            var accum = Data()
            for try await byte in bytes {
                accum.append(byte)
            }
            guard let json = try? JSONSerialization.jsonObject(with: accum) as? [String: Any],
                  let output = json["output"] as? [[String: Any]] else {
                throw HermesError.invalidResponse
            }
            let parsed = Self.postProcessResult(parseOutput(output))
            var promptTokens: Int? = nil
            var completionTokens: Int? = nil
            if let usage = json["usage"] as? [String: Any] {
                promptTokens = usage["input_tokens"] as? Int
                completionTokens = usage["output_tokens"] as? Int
            }
            onEvent(.completed(promptTokens: promptTokens, completionTokens: completionTokens))
            return ResponseResult(
                content: parsed.content,
                thinkingContent: parsed.thinkingContent,
                toolCalls: parsed.toolCalls,
                promptTokens: promptTokens,
                completionTokens: completionTokens
            )
        }

        // SSE path — accumulate live state while forwarding events.
        var content = ""
        var thinkingContent = ""
        var toolCallsAccumulated = ""
        var callNames: [String: String] = [:]
        var promptTokens: Int? = nil
        var completionTokens: Int? = nil
        // Splits <think>...</think> blocks embedded in output_text deltas
        // into distinct text / thinking streams so the bubble never shows
        // raw reasoning tags.
        var thinkSplitter = ThinkTagSplitter()

        for try await event in SSEStream(bytes: bytes) {
            guard let payloadData = event.data.data(using: .utf8),
                  let payload = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any]
            else {
                continue
            }

            switch event.name ?? "" {
            case "response.output_text.delta":
                if let delta = payload["delta"] as? String, !delta.isEmpty {
                    let routed = thinkSplitter.feed(delta)
                    for tagEvent in routed.events {
                        switch tagEvent {
                        case .thinkingStarted: onEvent(.thinkingStarted)
                        case .thinkingEnded: onEvent(.thinkingEnded)
                        }
                    }
                    if !routed.text.isEmpty {
                        content += routed.text
                        onEvent(.textDelta(routed.text))
                    }
                    if !routed.thinking.isEmpty {
                        thinkingContent += routed.thinking
                        onEvent(.thinkingDelta(routed.thinking))
                    }
                }

            case "response.reasoning_text.delta",
                 "response.reasoning_summary_text.delta":
                if let delta = payload["delta"] as? String, !delta.isEmpty {
                    thinkingContent += delta
                    onEvent(.thinkingDelta(delta))
                }

            case "response.output_item.added":
                guard let item = payload["item"] as? [String: Any],
                      let type = item["type"] as? String else { break }
                switch type {
                case "function_call":
                    let name = item["name"] as? String ?? "tool"
                    let callId = item["call_id"] as? String ?? ""
                    let args = item["arguments"] as? String ?? ""
                    let preview = Self.toolArgsPreview(toolName: name, rawArgs: args)
                    callNames[callId] = name
                    let line = preview.isEmpty ? "→ \(name)\n" : "→ \(name) \(preview)\n"
                    toolCallsAccumulated += line
                    onEvent(.toolCallStarted(id: callId, name: name, argsPreview: preview))
                case "function_call_output":
                    let callId = item["call_id"] as? String ?? ""
                    let name = callNames[callId] ?? "tool"
                    let resultPreview = joinOutputParts(item["output"])
                    toolCallsAccumulated += "✓ \(name)\n"
                    onEvent(.toolCallCompleted(id: callId, name: name, resultPreview: String(resultPreview.prefix(60))))
                default:
                    break
                }

            case "response.completed":
                // Drain any chars still held back by the tag splitter
                // (e.g. trailing ambiguous fragment that never completed).
                let flushed = thinkSplitter.flush()
                if !flushed.text.isEmpty { content += flushed.text; onEvent(.textDelta(flushed.text)) }
                if !flushed.thinking.isEmpty { thinkingContent += flushed.thinking; onEvent(.thinkingDelta(flushed.thinking)) }
                if thinkSplitter.insideThink { onEvent(.thinkingEnded) }

                if let responseObj = payload["response"] as? [String: Any] {
                    if let usage = responseObj["usage"] as? [String: Any] {
                        promptTokens = usage["input_tokens"] as? Int
                        completionTokens = usage["output_tokens"] as? Int
                    }
                    if let output = responseObj["output"] as? [[String: Any]] {
                        let parsed = Self.postProcessResult(parseOutput(output))
                        if !parsed.content.isEmpty { content = parsed.content }
                        if !parsed.thinkingContent.isEmpty { thinkingContent = parsed.thinkingContent }
                        if !parsed.toolCalls.isEmpty { toolCallsAccumulated = parsed.toolCalls }
                    }
                }
                onEvent(.completed(promptTokens: promptTokens, completionTokens: completionTokens))
                return ResponseResult(
                    content: content,
                    thinkingContent: thinkingContent,
                    toolCalls: toolCallsAccumulated,
                    promptTokens: promptTokens,
                    completionTokens: completionTokens
                )

            case "response.failed":
                let message: String
                if let responseObj = payload["response"] as? [String: Any],
                   let error = responseObj["error"] as? [String: Any],
                   let m = error["message"] as? String {
                    message = m
                } else {
                    message = "Hermes returned a failed response"
                }
                onEvent(.failed(message))
                throw HermesError.httpErrorWithBody(500, message)

            case "response.output_item.done",
                 "response.output_text.done",
                 "response.created":
                // Redundant with other events; no client action needed.
                break

            case "":
                break

            default:
                print("[SSE] unknown event: \(event.name ?? "")")
            }
        }

        // Stream closed without response.completed — still produce a final.
        onEvent(.completed(promptTokens: promptTokens, completionTokens: completionTokens))
        return ResponseResult(
            content: content,
            thinkingContent: thinkingContent,
            toolCalls: toolCallsAccumulated,
            promptTokens: promptTokens,
            completionTokens: completionTokens
        )
    }

    /// function_call_output.output is `[{"type":"input_text","text":"..."}, ...]`.
    /// Join the `text` fields for preview purposes.
    private func joinOutputParts(_ raw: Any?) -> String {
        guard let parts = raw as? [[String: Any]] else { return "" }
        return parts.compactMap { $0["text"] as? String }.joined(separator: "\n")
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
                let preview = Self.toolArgsPreview(toolName: name, rawArgs: args)
                toolCalls += preview.isEmpty ? "→ \(name)\n" : "→ \(name) \(preview)\n"
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

// MARK: - Output hygiene

extension HermesClient {
    /// Post-process a parsed ResponseResult: extract any leftover
    /// `<think>...</think>` blocks from `content` and fold them into
    /// `thinkingContent`, so the visible response never contains raw
    /// reasoning tags. The streaming path also does this live via
    /// `ThinkTagSplitter`; this helper covers the batch/non-streaming
    /// reconciliation paths.
    static func postProcessResult(_ result: ResponseResult) -> ResponseResult {
        let (cleanContent, extracted) = stripThinkTags(result.content)
        let mergedThinking: String
        if result.thinkingContent.isEmpty {
            mergedThinking = extracted
        } else if extracted.isEmpty {
            mergedThinking = result.thinkingContent
        } else {
            mergedThinking = result.thinkingContent + "\n\n" + extracted
        }
        return ResponseResult(
            content: cleanContent,
            thinkingContent: mergedThinking,
            toolCalls: result.toolCalls,
            promptTokens: result.promptTokens,
            completionTokens: result.completionTokens
        )
    }

    /// Split a string on `<think>...</think>` boundaries, returning the
    /// cleaned text and the concatenated thinking blocks. Unclosed
    /// `<think>` tags (stream cut mid-reasoning) are treated as
    /// thinking content through end of string.
    static func stripThinkTags(_ text: String) -> (text: String, thinking: String) {
        var cleaned = ""
        var thinking = ""
        var remaining = Substring(text)
        while let startRange = remaining.range(of: "<think>") {
            cleaned += remaining[..<startRange.lowerBound]
            let afterStart = remaining[startRange.upperBound...]
            if let endRange = afterStart.range(of: "</think>") {
                if !thinking.isEmpty { thinking += "\n\n" }
                thinking += afterStart[..<endRange.lowerBound]
                remaining = afterStart[endRange.upperBound...]
            } else {
                if !thinking.isEmpty { thinking += "\n\n" }
                thinking += afterStart
                remaining = ""
                break
            }
        }
        cleaned += remaining
        return (
            text: cleaned.trimmingCharacters(in: .whitespacesAndNewlines),
            thinking: thinking.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    /// Produce a short, safe-to-display summary of a tool call's JSON
    /// argument string. Strips secret-like patterns (env-var assignments,
    /// `sk-…` keys, bearer tokens) and truncates aggressively. For shell
    /// tools the raw command often embeds API keys as env vars, so we
    /// collapse to a generic label instead of risking leakage.
    static func toolArgsPreview(toolName: String, rawArgs: String) -> String {
        let trimmed = rawArgs.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let shellTools: Set<String> = ["terminal", "bash", "shell", "run_shell", "execute_shell"]
        if shellTools.contains(toolName) { return "running command" }

        if let data = trimmed.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let priority = ["query", "prompt", "path", "url", "message", "text", "name", "file_path", "pattern"]
            for key in priority {
                if let val = json[key] {
                    let valStr = String(describing: val)
                    return truncateAndScrub(valStr)
                }
            }
            if let firstKey = json.keys.sorted().first, let val = json[firstKey] {
                let valStr = String(describing: val)
                return "\(firstKey): \(truncateAndScrub(valStr))"
            }
        }
        return truncateAndScrub(trimmed)
    }

    private static func truncateAndScrub(_ s: String) -> String {
        var out = scrubSecrets(s)
        // Collapse whitespace for cleaner previews.
        out = out.replacingOccurrences(of: "\n", with: " ")
        if out.count > 40 { out = String(out.prefix(40)) + "…" }
        return out
    }

    private static func scrubSecrets(_ s: String) -> String {
        var r = s
        let subs: [(pattern: String, template: String)] = [
            (#"([A-Z][A-Z0-9_]{2,})=\"[^\"]{8,}\""#, "$1=***"),
            (#"([A-Z][A-Z0-9_]{2,})=[^\s\"]{20,}"#, "$1=***"),
            (#"sk-[A-Za-z0-9\-_]{16,}"#, "sk-***"),
            (#"(Bearer\s+)[A-Za-z0-9\-_\.]{20,}"#, "$1***"),
        ]
        for sub in subs {
            if let regex = try? NSRegularExpression(pattern: sub.pattern) {
                let range = NSRange(r.startIndex..., in: r)
                r = regex.stringByReplacingMatches(in: r, range: range, withTemplate: sub.template)
            }
        }
        return r
    }
}

/// Stateful splitter that routes a live `<think>...</think>`-laced text
/// stream into separate text and thinking channels. Handles tag markers
/// that straddle delta boundaries by holding back the shortest ambiguous
/// suffix until the next delta arrives (or `flush()` is called at end of
/// stream). Callers fire the returned tag events at the moment each tag
/// is consumed, so UI can toggle "currently thinking" state precisely.
struct ThinkTagSplitter {
    enum TagEvent { case thinkingStarted, thinkingEnded }

    var insideThink: Bool = false
    private var buffer: String = ""

    mutating func feed(_ delta: String) -> (text: String, thinking: String, events: [TagEvent]) {
        buffer += delta
        var text = ""
        var thinking = ""
        var events: [TagEvent] = []

        while true {
            let target = insideThink ? "</think>" : "<think>"
            if let range = buffer.range(of: target) {
                let before = buffer[..<range.lowerBound]
                if insideThink { thinking += before } else { text += before }
                events.append(insideThink ? .thinkingEnded : .thinkingStarted)
                insideThink.toggle()
                buffer = String(buffer[range.upperBound...])
                continue
            }
            // No complete tag in buffer. Hold back the longest suffix that
            // could still be the start of the tag we're searching for.
            var holdBack = 0
            let maxCheck = min(buffer.count, target.count - 1)
            if maxCheck > 0 {
                for i in stride(from: maxCheck, through: 1, by: -1) {
                    let tail = String(buffer.suffix(i))
                    if target.hasPrefix(tail) {
                        holdBack = i
                        break
                    }
                }
            }
            let drainLen = buffer.count - holdBack
            if drainLen > 0 {
                let splitIdx = buffer.index(buffer.startIndex, offsetBy: drainLen)
                let safe = buffer[..<splitIdx]
                if insideThink { thinking += safe } else { text += safe }
                buffer = String(buffer[splitIdx...])
            }
            break
        }
        return (text, thinking, events)
    }

    /// Drain anything still in the buffer. Call once at end of stream.
    mutating func flush() -> (text: String, thinking: String) {
        guard !buffer.isEmpty else { return ("", "") }
        var text = ""
        var thinking = ""
        if insideThink { thinking = buffer } else { text = buffer }
        buffer = ""
        return (text, thinking)
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

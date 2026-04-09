import Foundation

class HermesClient {
    private let baseURL = "http://localhost:8642"
    var sessionId: String?

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300
        config.timeoutIntervalForResource = 600
        return URLSession(configuration: config)
    }()

    // MARK: - Streaming via /v1/runs

    func streamCompletion(input: String, conversationHistory: [[String: String]]) -> AsyncThrowingStream<SSEEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let runId = try await self.startRun(input: input, conversationHistory: conversationHistory)

                    guard let eventsURL = URL(string: "\(self.baseURL)/v1/runs/\(runId)/events") else {
                        continuation.finish(throwing: HermesError.invalidURL)
                        return
                    }

                    let request = URLRequest(url: eventsURL)
                    let (bytes, response) = try await self.session.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        continuation.finish(throwing: HermesError.invalidResponse)
                        return
                    }

                    guard httpResponse.statusCode == 200 else {
                        continuation.finish(throwing: HermesError.httpError(httpResponse.statusCode))
                        return
                    }

                    var parser = SSEParser()

                    for try await line in bytes.lines {
                        guard !Task.isCancelled else { break }

                        let events = parser.parse(line: line)
                        for event in events {
                            if case .done = event { break }
                            continuation.yield(event)
                        }
                        if events.contains(where: { if case .done = $0 { return true }; return false }) {
                            break
                        }
                    }

                    continuation.finish()
                } catch {
                    print("[notchnotch] Stream error: \(error)")
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func startRun(input: String, conversationHistory: [[String: String]]) async throws -> String {
        guard let url = URL(string: "\(baseURL)/v1/runs") else {
            throw HermesError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = ["input": input]
        if !conversationHistory.isEmpty {
            body["conversation_history"] = conversationHistory
        }
        if let sessionId = sessionId, !sessionId.isEmpty {
            body["session_id"] = sessionId
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HermesError.invalidResponse
        }
        guard httpResponse.statusCode == 202 else {
            throw HermesError.httpError(httpResponse.statusCode)
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let runId = json["run_id"] as? String else {
            throw HermesError.invalidResponse
        }
        return runId
    }

    // MARK: - Non-streaming via /v1/responses

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
        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HermesError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            throw HermesError.httpError(httpResponse.statusCode)
        }
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

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid API URL"
        case .invalidResponse: return "Bad response"
        case .httpError(let code): return "HTTP \(code)"
        }
    }
}

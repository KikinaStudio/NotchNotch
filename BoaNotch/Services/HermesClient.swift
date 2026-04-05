import Foundation

class HermesClient {
    private let baseURL = "http://localhost:8642/v1/chat/completions"
    var sessionId: String?

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300
        config.timeoutIntervalForResource = 600
        return URLSession(configuration: config)
    }()

    func streamCompletion(messages: [[String: String]]) -> AsyncThrowingStream<SSEEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let url = URL(string: self.baseURL) else {
                        continuation.finish(throwing: HermesError.invalidURL)
                        return
                    }

                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    if let sessionId = self.sessionId, !sessionId.isEmpty {
                        request.setValue(sessionId, forHTTPHeaderField: "X-Hermes-Session-Id")
                    }

                    let body: [String: Any] = [
                        "model": "hermes-agent",
                        "messages": messages,
                        "stream": true
                    ]
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)

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

                        if let event = parser.parse(line: line) {
                            if case .done = event { break }
                            continuation.yield(event)
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

    func healthCheck() async -> Bool {
        guard let url = URL(string: "http://localhost:8642/health") else { return false }
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

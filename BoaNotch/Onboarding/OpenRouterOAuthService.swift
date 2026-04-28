import Foundation
import CryptoKit
import Network
import AppKit

/// OpenRouter OAuth 2.0 PKCE flow with loopback HTTP redirect.
///
/// On success:
/// - Writes `OPENROUTER_API_KEY=<key>` into `~/.hermes/.env`
/// - Sets `model.provider: openrouter` and `model.base_url:
///   https://openrouter.ai/api/v1` in `~/.hermes/config.yaml`
/// - Picks a tool-capable free model via `GET /v1/models` and writes
///   `model.default` (fallback `stepfun/step-3.5-flash:free` if the fetch fails)
final class OpenRouterOAuthService {
    static let shared = OpenRouterOAuthService()

    /// Server held during an in-flight `connect()` so the UI can interrupt
    /// the wait (e.g. user hits Cancel, OpenRouter consent dialog errors out).
    /// Mutated on MainActor only.
    @MainActor private var inflightServer: LoopbackServer?

    private init() {}

    /// Aborts an in-flight OAuth flow. Resumes any pending continuation with
    /// `.userCancelled`, which the caller's `catch` swallows silently.
    @MainActor
    func cancelInFlight() {
        inflightServer?.stop()
        inflightServer = nil
    }

    // MARK: - Errors

    enum OAuthError: LocalizedError {
        case userCancelled
        case exchangeFailed(String)
        case invalidResponse
        case stateMismatch
        case timeout
        case listenerFailed(String)

        var errorDescription: String? {
            switch self {
            case .userCancelled: return "Sign-in cancelled"
            case .exchangeFailed(let m): return "Token exchange failed: \(m)"
            case .invalidResponse: return "Invalid response from OpenRouter"
            case .stateMismatch: return "OAuth state mismatch (possible CSRF)"
            case .timeout: return "Sign-in timed out"
            case .listenerFailed(let m): return "Local server failed: \(m)"
            }
        }
    }

    // MARK: - Preferred free model order (best-for-agentic first)

    private let preferredFreeIDs: [String] = [
        "stepfun/step-3.5-flash:free",
        "deepseek/deepseek-chat-v3.1:free",
        "qwen/qwen-2.5-coder-32b-instruct:free",
        "meta-llama/llama-3.3-70b-instruct:free",
        "google/gemini-2.0-flash-exp:free",
    ]

    private let fallbackFreeID = "stepfun/step-3.5-flash:free"

    // MARK: - Public API

    /// Runs the full OAuth flow. Returns the chosen free model ID on success
    /// (already written into `config.yaml`).
    func connect() async throws -> String {
        let verifier = Self.generateCodeVerifier()
        let challenge = Self.codeChallenge(from: verifier)
        let state = UUID().uuidString

        let server = LoopbackServer(expectedState: state)
        let port = try await server.start()
        let redirectURI = "http://localhost:\(port)"

        await MainActor.run { self.inflightServer = server }
        defer {
            server.stop()
            Task { @MainActor in self.inflightServer = nil }
        }

        let authURL = buildAuthorizationURL(
            challenge: challenge,
            state: state,
            redirectURI: redirectURI
        )

        await MainActor.run {
            _ = NSWorkspace.shared.open(authURL)
        }

        let code = try await withTimeout(seconds: 120) {
            try await server.waitForCode()
        }

        let key = try await exchangeCode(
            code: code,
            verifier: verifier,
            redirectURI: redirectURI
        )

        // Persist key + provider config
        HermesConfig.shared.writeRawEnv(key: "OPENROUTER_API_KEY", value: key)
        HermesConfig.shared.setImmediate("model.provider", value: "openrouter")
        HermesConfig.shared.setImmediate(
            "model.base_url",
            value: "https://openrouter.ai/api/v1"
        )

        // Pick a tool-capable :free model from the live catalog
        let chosenModel = await pickFreeModel()
        HermesConfig.shared.setImmediate("model.default", value: chosenModel)

        return chosenModel
    }

    // MARK: - PKCE

    private static func generateCodeVerifier() -> String {
        let unreserved = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return String((0..<64).map { _ in unreserved.randomElement()! })
    }

    private static func codeChallenge(from verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // MARK: - Authorization URL

    private func buildAuthorizationURL(challenge: String, state: String, redirectURI: String) -> URL {
        var components = URLComponents(string: "https://openrouter.ai/auth")!
        components.queryItems = [
            URLQueryItem(name: "callback_url", value: redirectURI),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
        ]
        return components.url!
    }

    // MARK: - Code exchange

    private func exchangeCode(code: String, verifier: String, redirectURI: String) async throws -> String {
        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/auth/keys")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = [
            "code": code,
            "code_verifier": verifier,
            "code_challenge_method": "S256",
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: request)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let bodyStr = String(data: data, encoding: .utf8) ?? "unknown"
            throw OAuthError.exchangeFailed(bodyStr)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let key = json["key"] as? String else {
            throw OAuthError.invalidResponse
        }
        return key
    }

    // MARK: - Free model picker (inline /v1/models)

    /// Picks the highest-priority preferred free model that's currently listed
    /// as `pricing.prompt == "0"` AND supports `tools` in OpenRouter's catalog.
    /// Falls back optimistically to `fallbackFreeID` on any failure.
    private func pickFreeModel() async -> String {
        guard let url = URL(string: "https://openrouter.ai/api/v1/models") else {
            return fallbackFreeID
        }
        do {
            let (data, resp) = try await URLSession.shared.data(from: url)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let listed = json["data"] as? [[String: Any]] else {
                return fallbackFreeID
            }

            // Build a set of (id) that are free + tool-capable
            var qualified = Set<String>()
            for entry in listed {
                guard let id = entry["id"] as? String else { continue }
                let pricing = entry["pricing"] as? [String: Any]
                let promptPrice = (pricing?["prompt"] as? String) ?? ""
                guard promptPrice == "0" else { continue }
                let supported = entry["supported_parameters"] as? [String] ?? []
                guard supported.contains("tools") else { continue }
                qualified.insert(id)
            }

            for preferred in preferredFreeIDs where qualified.contains(preferred) {
                return preferred
            }
            return fallbackFreeID
        } catch {
            return fallbackFreeID
        }
    }
}

// MARK: - Async timeout helper

private func withTimeout<T: Sendable>(
    seconds: TimeInterval,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw OpenRouterOAuthService.OAuthError.timeout
        }
        guard let result = try await group.next() else {
            throw OpenRouterOAuthService.OAuthError.timeout
        }
        group.cancelAll()
        return result
    }
}

// MARK: - Loopback HTTP server
//
// Single-shot local HTTP server: OS-assigned port, accepts one GET callback
// from OpenRouter, replies with a styled HTML page, surfaces the `code`.
//
// @unchecked Sendable: all mutable state is mutated via `queue`, a serial
// DispatchQueue, so cross-thread access is safe by construction.
private final class LoopbackServer: @unchecked Sendable {
    private var listener: NWListener?
    private let expectedState: String

    private var portContinuation: CheckedContinuation<UInt16, Error>?
    private var codeContinuation: CheckedContinuation<String, Error>?

    private let queue = DispatchQueue(label: "notchnotch.openrouteroauth.loopback")

    init(expectedState: String) {
        self.expectedState = expectedState
    }

    func start() async throws -> UInt16 {
        try await withCheckedThrowingContinuation { cont in
            queue.async {
                self.portContinuation = cont
                do {
                    let listener = try NWListener(using: .tcp)
                    self.listener = listener

                    listener.stateUpdateHandler = { [weak self] state in
                        self?.queue.async { self?.handleState(state) }
                    }
                    listener.newConnectionHandler = { [weak self] conn in
                        self?.queue.async { self?.handleConnection(conn) }
                    }
                    listener.start(queue: self.queue)
                } catch {
                    cont.resume(throwing: OpenRouterOAuthService.OAuthError.listenerFailed(error.localizedDescription))
                    self.portContinuation = nil
                }
            }
        }
    }

    func waitForCode() async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            queue.async {
                self.codeContinuation = cont
            }
        }
    }

    func stop() {
        queue.async { [weak self] in
            self?.listener?.cancel()
            self?.listener = nil
            if let cont = self?.codeContinuation {
                cont.resume(throwing: OpenRouterOAuthService.OAuthError.userCancelled)
                self?.codeContinuation = nil
            }
        }
    }

    private func handleState(_ state: NWListener.State) {
        switch state {
        case .ready:
            guard let port = listener?.port?.rawValue else {
                portContinuation?.resume(throwing: OpenRouterOAuthService.OAuthError.listenerFailed("no port after ready"))
                portContinuation = nil
                return
            }
            portContinuation?.resume(returning: port)
            portContinuation = nil
        case .failed(let error):
            portContinuation?.resume(throwing: OpenRouterOAuthService.OAuthError.listenerFailed(error.localizedDescription))
            portContinuation = nil
        default:
            break
        }
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, _ in
            guard let self = self, let data = data, let raw = String(data: data, encoding: .utf8) else {
                connection.cancel()
                return
            }
            self.queue.async {
                self.parseAndRespond(raw: raw, connection: connection)
            }
        }
    }

    private func parseAndRespond(raw: String, connection: NWConnection) {
        let firstLine = raw.components(separatedBy: "\r\n").first ?? ""
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2, parts[0] == "GET" else {
            respond(connection: connection, html: Self.errorHTML("Bad request"))
            return
        }

        let path = String(parts[1])
        guard let url = URL(string: "http://localhost" + path),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            respond(connection: connection, html: Self.errorHTML("Invalid URL"))
            return
        }

        var params: [String: String] = [:]
        for item in components.queryItems ?? [] {
            params[item.name] = item.value
        }

        if let err = params["error"] {
            respond(connection: connection, html: Self.errorHTML("OpenRouter: \(err)"))
            codeContinuation?.resume(throwing: OpenRouterOAuthService.OAuthError.userCancelled)
            codeContinuation = nil
            return
        }

        guard params["state"] == expectedState else {
            respond(connection: connection, html: Self.errorHTML("State mismatch"))
            codeContinuation?.resume(throwing: OpenRouterOAuthService.OAuthError.stateMismatch)
            codeContinuation = nil
            return
        }

        guard let code = params["code"] else {
            respond(connection: connection, html: Self.errorHTML("Missing code"))
            codeContinuation?.resume(throwing: OpenRouterOAuthService.OAuthError.invalidResponse)
            codeContinuation = nil
            return
        }

        respond(connection: connection, html: Self.successHTML())
        codeContinuation?.resume(returning: code)
        codeContinuation = nil
    }

    private func respond(connection: NWConnection, html: String) {
        let response = """
        HTTP/1.1 200 OK\r
        Content-Type: text/html; charset=utf-8\r
        Content-Length: \(html.utf8.count)\r
        Cache-Control: no-store\r
        Connection: close\r
        \r
        \(html)
        """
        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private static func successHTML() -> String {
        """
        <!DOCTYPE html>
        <html>
        <head><meta charset="utf-8"><title>NotchNotch · Connected</title>
        <style>
        html,body{margin:0;padding:0;height:100%;}
        body{font-family:-apple-system,system-ui,sans-serif;background:#0a0a0a;color:#eee;display:flex;align-items:center;justify-content:center;flex-direction:column;gap:0.6rem;}
        h1{font-weight:500;font-size:1.25rem;margin:0;}
        p{color:#888;margin:0;font-size:0.95rem;}
        .dot{width:8px;height:8px;border-radius:50%;background:#9adfff;margin-bottom:0.3rem;}
        </style>
        </head>
        <body>
        <div class="dot"></div>
        <h1>Connected to NotchNotch</h1>
        <p>You can close this window.</p>
        </body>
        </html>
        """
    }

    private static func errorHTML(_ reason: String) -> String {
        let escaped = reason
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        return """
        <!DOCTYPE html>
        <html>
        <head><meta charset="utf-8"><title>NotchNotch · Failed</title>
        <style>
        html,body{margin:0;padding:0;height:100%;}
        body{font-family:-apple-system,system-ui,sans-serif;background:#0a0a0a;color:#eee;display:flex;align-items:center;justify-content:center;flex-direction:column;gap:0.5rem;}
        h1{font-weight:500;font-size:1.25rem;margin:0;color:#ff8080;}
        p{color:#888;margin:0;font-size:0.9rem;font-family:ui-monospace,monospace;}
        </style>
        </head>
        <body>
        <h1>Sign-in failed</h1>
        <p>\(escaped)</p>
        </body>
        </html>
        """
    }
}

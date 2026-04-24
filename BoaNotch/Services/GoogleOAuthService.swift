import Foundation
import CryptoKit
import Network
import AppKit

/// Google Desktop OAuth 2.0 flow with PKCE + loopback redirect.
///
/// Writes a token JSON matching `google.oauth2.credentials.Credentials.to_json()`
/// to `~/.hermes/google_token.json` so the Hermes `google-workspace` skill can
/// read it via `Credentials.from_authorized_user_file`.
final class GoogleOAuthService {
    static let shared = GoogleOAuthService()

    // 8 scopes matching the Google Cloud OAuth consent screen configuration.
    static let scopes: [String] = [
        "openid",
        "https://www.googleapis.com/auth/userinfo.email",
        "https://www.googleapis.com/auth/gmail.modify",
        "https://www.googleapis.com/auth/calendar",
        "https://www.googleapis.com/auth/drive",
        "https://www.googleapis.com/auth/spreadsheets",
        "https://www.googleapis.com/auth/documents",
        "https://www.googleapis.com/auth/contacts.readonly",
    ]

    private let config: OAuthConfig

    private init() {
        self.config = Self.loadConfig()
    }

    // MARK: - Config

    private struct OAuthConfig: Decodable {
        struct Installed: Decodable {
            let client_id: String
            let client_secret: String
            let auth_uri: String
            let token_uri: String
        }
        let installed: Installed
    }

    private static func loadConfig() -> OAuthConfig {
        guard let resourceURL = Bundle.main.resourceURL?
            .appendingPathComponent("google_oauth_config.json"),
              let data = try? Data(contentsOf: resourceURL),
              let decoded = try? JSONDecoder().decode(OAuthConfig.self, from: data)
        else {
            fatalError("[notchnotch] google_oauth_config.json missing or malformed — rebuild the app")
        }
        return decoded
    }

    // MARK: - Public API

    enum GoogleOAuthError: LocalizedError {
        case userCancelled
        case exchangeFailed(String)
        case invalidResponse
        case fileWriteFailed(String)
        case stateMismatch
        case timeout
        case listenerFailed(String)

        var errorDescription: String? {
            switch self {
            case .userCancelled: return "Connection cancelled"
            case .exchangeFailed(let m): return "Token exchange failed: \(m)"
            case .invalidResponse: return "Invalid response from Google"
            case .fileWriteFailed(let m): return "Could not save token: \(m)"
            case .stateMismatch: return "OAuth state mismatch (possible CSRF)"
            case .timeout: return "Authorization timed out"
            case .listenerFailed(let m): return "Local server failed: \(m)"
            }
        }
    }

    /// Runs the full OAuth flow. Returns the connected user's email on success.
    func connect() async throws -> String {
        let verifier = Self.generateCodeVerifier()
        let challenge = Self.codeChallenge(from: verifier)
        let state = UUID().uuidString

        let server = LoopbackServer(expectedState: state)
        let port = try await server.start()
        let redirectURI = "http://localhost:\(port)"

        // Always stop the server at the end (success or failure)
        defer { server.stop() }

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

        let token = try await exchangeCode(
            code: code,
            verifier: verifier,
            redirectURI: redirectURI
        )

        let email = try await fetchUserEmail(accessToken: token.accessToken)

        try writeTokenFile(token: token)

        UserDefaults.standard.set(email, forKey: "googleConnectedEmail")
        return email
    }

    /// Deletes the token file and clears UserDefaults.
    func disconnect() {
        let path = Self.tokenFilePath()
        try? FileManager.default.removeItem(atPath: path)
        UserDefaults.standard.removeObject(forKey: "googleConnectedEmail")
    }

    /// True if `~/.hermes/google_token.json` exists on disk.
    static func tokenFileExists() -> Bool {
        FileManager.default.fileExists(atPath: tokenFilePath())
    }

    // MARK: - PKCE

    private static func generateCodeVerifier() -> String {
        let unreserved = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        let length = 64
        return String((0..<length).map { _ in unreserved.randomElement()! })
    }

    private static func codeChallenge(from verifier: String) -> String {
        let data = Data(verifier.utf8)
        let hash = SHA256.hash(data: data)
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // MARK: - Authorization URL

    private func buildAuthorizationURL(challenge: String, state: String, redirectURI: String) -> URL {
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: config.installed.client_id),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: Self.scopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
            URLQueryItem(name: "state", value: state),
        ]
        return components.url!
    }

    // MARK: - Token exchange

    private struct TokenResponse {
        let accessToken: String
        let refreshToken: String?
        let expiresIn: Int
        let scope: String
        let tokenType: String
    }

    private func exchangeCode(code: String, verifier: String, redirectURI: String) async throws -> TokenResponse {
        var request = URLRequest(url: URL(string: config.installed.token_uri)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let params: [String: String] = [
            "code": code,
            "client_id": config.installed.client_id,
            "client_secret": config.installed.client_secret,
            "code_verifier": verifier,
            "grant_type": "authorization_code",
            "redirect_uri": redirectURI,
        ]
        request.httpBody = Self.formEncode(params).data(using: .utf8)

        let (data, resp) = try await URLSession.shared.data(for: request)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "unknown"
            throw GoogleOAuthError.exchangeFailed(body)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String,
              let expiresIn = json["expires_in"] as? Int
        else {
            throw GoogleOAuthError.invalidResponse
        }

        return TokenResponse(
            accessToken: accessToken,
            refreshToken: json["refresh_token"] as? String,
            expiresIn: expiresIn,
            scope: json["scope"] as? String ?? "",
            tokenType: json["token_type"] as? String ?? "Bearer"
        )
    }

    private static func formEncode(_ params: [String: String]) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=")
        return params
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0.value)" }
            .joined(separator: "&")
    }

    // MARK: - User info

    private func fetchUserEmail(accessToken: String) async throws -> String {
        var request = URLRequest(url: URL(string: "https://www.googleapis.com/oauth2/v2/userinfo")!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: request)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let email = json["email"] as? String
        else {
            throw GoogleOAuthError.invalidResponse
        }
        return email
    }

    // MARK: - Token file write

    private static func hermesHome() -> String {
        ProcessInfo.processInfo.environment["HERMES_HOME"]
            ?? "\(NSHomeDirectory())/.hermes"
    }

    private static func tokenFilePath() -> String {
        "\(hermesHome())/google_token.json"
    }

    private func writeTokenFile(token: TokenResponse) throws {
        // Match google-auth-library's `Credentials.to_json()` format exactly.
        // The skill reads this via `Credentials.from_authorized_user_file` which
        // parses `expiry` with strptime("%Y-%m-%dT%H:%M:%S.%f") after stripping Z.
        let expiryDate = Date().addingTimeInterval(TimeInterval(token.expiresIn))
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let expiryStr = formatter.string(from: expiryDate) + ".000000Z"

        // Prefer the scope list Google actually granted over our requested list.
        let grantedScopes: [String] = token.scope.isEmpty
            ? Self.scopes
            : token.scope.split(separator: " ").map(String.init)

        let payload: [String: Any] = [
            "token": token.accessToken,
            "refresh_token": token.refreshToken ?? "",
            "token_uri": config.installed.token_uri,
            "client_id": config.installed.client_id,
            "client_secret": config.installed.client_secret,
            "scopes": grantedScopes,
            "universe_domain": "googleapis.com",
            "account": "",
            "expiry": expiryStr,
        ]

        guard let data = try? JSONSerialization.data(
            withJSONObject: payload,
            options: [.prettyPrinted, .sortedKeys]
        ) else {
            throw GoogleOAuthError.fileWriteFailed("JSON encode failed")
        }

        let home = Self.hermesHome()
        let path = Self.tokenFilePath()

        try? FileManager.default.createDirectory(
            atPath: home,
            withIntermediateDirectories: true
        )

        do {
            try data.write(to: URL(fileURLWithPath: path), options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: path
            )
        } catch {
            throw GoogleOAuthError.fileWriteFailed(error.localizedDescription)
        }

        print("[notchnotch] Google token written to \(path)")
    }
}

// MARK: - Async timeout helper

private func withTimeout<T: Sendable>(
    seconds: TimeInterval,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw GoogleOAuthService.GoogleOAuthError.timeout
        }
        guard let result = try await group.next() else {
            throw GoogleOAuthService.GoogleOAuthError.timeout
        }
        group.cancelAll()
        return result
    }
}

// MARK: - Loopback HTTP server

/// Single-shot local HTTP server that listens on an OS-assigned port, accepts
/// one GET callback from Google's consent redirect, replies with a styled HTML
/// page, and surfaces the `code` back to the async caller.
///
/// @unchecked Sendable: all mutable state is mutated only via `queue`, a serial
/// DispatchQueue, so cross-thread access is safe by construction.
private final class LoopbackServer: @unchecked Sendable {
    private var listener: NWListener?
    private let expectedState: String

    private var portContinuation: CheckedContinuation<UInt16, Error>?
    private var codeContinuation: CheckedContinuation<String, Error>?

    private let queue = DispatchQueue(label: "notchnotch.googleoauth.loopback")

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
                    cont.resume(throwing: GoogleOAuthService.GoogleOAuthError.listenerFailed(error.localizedDescription))
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
                cont.resume(throwing: GoogleOAuthService.GoogleOAuthError.userCancelled)
                self?.codeContinuation = nil
            }
        }
    }

    private func handleState(_ state: NWListener.State) {
        switch state {
        case .ready:
            guard let port = listener?.port?.rawValue else {
                portContinuation?.resume(throwing: GoogleOAuthService.GoogleOAuthError.listenerFailed("no port after ready"))
                portContinuation = nil
                return
            }
            portContinuation?.resume(returning: port)
            portContinuation = nil
        case .failed(let error):
            portContinuation?.resume(throwing: GoogleOAuthService.GoogleOAuthError.listenerFailed(error.localizedDescription))
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
            respond(connection: connection, html: Self.errorHTML("Google: \(err)"))
            codeContinuation?.resume(throwing: GoogleOAuthService.GoogleOAuthError.userCancelled)
            codeContinuation = nil
            return
        }

        guard params["state"] == expectedState else {
            respond(connection: connection, html: Self.errorHTML("State mismatch"))
            codeContinuation?.resume(throwing: GoogleOAuthService.GoogleOAuthError.stateMismatch)
            codeContinuation = nil
            return
        }

        guard let code = params["code"] else {
            respond(connection: connection, html: Self.errorHTML("Missing code"))
            codeContinuation?.resume(throwing: GoogleOAuthService.GoogleOAuthError.invalidResponse)
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
        <h1>Connection failed</h1>
        <p>\(escaped)</p>
        </body>
        </html>
        """
    }
}

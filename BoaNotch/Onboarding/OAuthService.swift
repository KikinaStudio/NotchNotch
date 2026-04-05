import Foundation
import CryptoKit

enum OAuthService {
    /// Generate a PKCE code verifier (43-128 random characters from unreserved set)
    static func generateCodeVerifier() -> String {
        let unreserved = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        let length = Int.random(in: 43...128)
        return String((0..<length).map { _ in unreserved.randomElement()! })
    }

    /// Derive the PKCE code challenge from a verifier (SHA256 + base64url)
    static func codeChallenge(from verifier: String) -> String {
        let data = Data(verifier.utf8)
        let hash = SHA256.hash(data: data)
        let base64 = Data(hash).base64EncodedString()
        // base64url: replace +/ with -_, strip trailing =
        return base64
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Build the OpenRouter authorization URL
    static func authorizationURL(codeChallenge: String) -> URL {
        var components = URLComponents(string: "https://openrouter.ai/auth")!
        components.queryItems = [
            URLQueryItem(name: "callback_url", value: "boanotch://oauth/callback"),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]
        return components.url!
    }

    /// Exchange the authorization code for an API key
    static func exchangeCode(_ code: String, verifier: String) async throws -> String {
        let url = URL(string: "https://openrouter.ai/api/v1/auth/keys")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = [
            "code": code,
            "code_verifier": verifier,
            "code_challenge_method": "S256",
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw OAuthError.exchangeFailed(msg)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let key = json["key"] as? String else {
            throw OAuthError.invalidResponse
        }

        return key
    }

    enum OAuthError: LocalizedError {
        case exchangeFailed(String)
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .exchangeFailed(let msg): return "Token exchange failed: \(msg)"
            case .invalidResponse: return "Invalid response from OpenRouter"
            }
        }
    }
}

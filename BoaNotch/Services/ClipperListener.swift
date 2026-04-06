import Foundation
import Network

/// Tiny HTTP server on port 19944 that receives toast notifications from the NotchNotch Clipper Chrome extension.
/// POST /clip  { "title": "Page Title", "url": "https://..." }
/// Returns 200 OK and triggers a pacman toast in the notch.
class ClipperListener {
    private var listener: NWListener?
    var onClip: ((String, String) -> Void)?  // (title, url)

    func start() {
        do {
            let params = NWParameters.tcp
            listener = try NWListener(using: params, on: 19944)
        } catch {
            print("[notchnotch] ClipperListener failed to create listener: \(error)")
            return
        }

        listener?.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }

        listener?.stateUpdateHandler = { state in
            switch state {
            case .ready:
                print("[notchnotch] ClipperListener ready on port 19944")
            case .failed(let error):
                print("[notchnotch] ClipperListener failed: \(error)")
            default:
                break
            }
        }

        listener?.start(queue: .global(qos: .utility))
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .utility))

        // Read up to 64KB
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, error in
            guard let data = data, error == nil else {
                connection.cancel()
                return
            }
            guard let raw = String(data: data, encoding: .utf8) else { return }

            // Parse HTTP request — extract JSON body after the blank line
            let parts = raw.components(separatedBy: "\r\n\r\n")
            guard parts.count >= 2 else {
                Self.respond(connection: connection, status: 400, body: "Bad request")
                return
            }

            let headers = parts[0]

            // CORS preflight
            if headers.hasPrefix("OPTIONS") {
                Self.respond(connection: connection, status: 204, body: "", cors: true)
                return
            }

            guard headers.contains("POST") else {
                Self.respond(connection: connection, status: 405, body: "Method not allowed")
                return
            }

            let body = parts.dropFirst().joined(separator: "\r\n\r\n")
            guard let jsonData = body.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                  let title = json["title"] as? String
            else {
                Self.respond(connection: connection, status: 400, body: "Invalid JSON")
                return
            }

            let url = json["url"] as? String ?? ""

            DispatchQueue.main.async {
                self?.onClip?(title, url)
            }

            Self.respond(connection: connection, status: 200, body: "{\"ok\":true}", cors: true)
        }
    }

    private static func respond(connection: NWConnection, status: Int, body: String, cors: Bool = false) {
        let statusText = status == 200 ? "OK" : status == 204 ? "No Content" : "Error"
        var headers = "HTTP/1.1 \(status) \(statusText)\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\n"
        if cors {
            headers += "Access-Control-Allow-Origin: *\r\nAccess-Control-Allow-Methods: POST, OPTIONS\r\nAccess-Control-Allow-Headers: Content-Type\r\n"
        }
        headers += "Connection: close\r\n\r\n"
        let response = headers + body
        connection.send(content: response.data(using: .utf8), completion: .contentProcessed({ _ in
            connection.cancel()
        }))
    }
}

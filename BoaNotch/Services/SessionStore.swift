import Foundation
import SQLite3

struct SessionSummary: Identifiable {
    let id: String
    let source: String
    let title: String?
    let model: String?
    let startedAt: Date?
    let messageCount: Int
    let firstUserMessage: String?
    let inputTokens: Int
    let outputTokens: Int

    var sourceIcon: String {
        switch source {
        case "telegram": return "paperplane.fill"
        case "cli": return "terminal.fill"
        case "discord": return "bubble.left.fill"
        case "api_server": return "bubble.left.and.bubble.right.fill"
        default: return "ellipsis.bubble.fill"
        }
    }

    /// Truncated preview of the first user message, used as a title fallback.
    func messagePreview(maxChars: Int = 45) -> String? {
        guard let raw = firstUserMessage?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        let oneLine = raw.replacingOccurrences(of: "\n", with: " ")
        if oneLine.count <= maxChars { return oneLine }
        return String(oneLine.prefix(maxChars)).trimmingCharacters(in: .whitespaces) + "…"
    }
}

struct SessionMessage {
    let role: String
    let content: String
    let timestamp: Date?
}

class SessionStore: ObservableObject {
    /// The Telegram DM session ID, auto-detected from Hermes state.db
    @Published var selectedSessionId: String? {
        didSet { UserDefaults.standard.set(selectedSessionId, forKey: "hermesSessionId") }
    }

    /// Whether a session was found
    @Published var isLinked = false

    /// Recent sessions for conversation history
    @Published var recentSessions: [SessionSummary] = []

    private let dbPath: String

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        self.dbPath = "\(home)/.hermes/state.db"

        // Restore from UserDefaults first
        self.selectedSessionId = UserDefaults.standard.string(forKey: "hermesSessionId")
        self.isLinked = selectedSessionId != nil

        // Then try to auto-detect from DB
        autoLinkTelegram()
    }

    /// Auto-detect the Telegram user ID from Hermes state.db
    func autoLinkTelegram() {
        guard let db = openDB() else { return }
        defer { sqlite3_close(db) }

        // Find the Telegram user_id (chat_id) — this is what X-Hermes-Session-Id expects,
        // not the internal session ID. Using the session ID causes Hermes to resume a
        // closed session and return empty responses.
        var stmt: OpaquePointer?
        let sql = "SELECT user_id FROM sessions WHERE source = 'telegram' AND user_id IS NOT NULL ORDER BY started_at DESC LIMIT 1"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        if sqlite3_step(stmt) == SQLITE_ROW {
            // Prefix with "notchnotch-" to avoid collision with existing session IDs
            // in the Hermes DB that may share the same raw user_id value
            let userId = String(cString: sqlite3_column_text(stmt, 0))
            let prefixed = "notchnotch-\(userId)"
            if selectedSessionId != prefixed {
                selectedSessionId = prefixed
            }
            isLinked = true
        }
    }

    /// Load recent sessions from Hermes state.db (max 30, newest first).
    /// Excludes one-shot stubs (`message_count < 2`) and stale sessions older than 60 days.
    /// Pulls the first user message in the same query so the history view can
    /// fall back to a message preview when no title exists.
    func loadRecentSessions() {
        guard let db = openDB() else {
            recentSessions = []
            return
        }
        defer { sqlite3_close(db) }

        // started_at is REAL (Unix epoch). Sixty days ago = now - 60*86400.
        let cutoff = Date().timeIntervalSince1970 - (60 * 86_400)

        var stmt: OpaquePointer?
        let sql = """
            SELECT s.id, s.source, s.title, s.model, s.started_at,
                   s.message_count, s.input_tokens, s.output_tokens,
                   (SELECT m.content FROM messages m
                    WHERE m.session_id = s.id AND m.role = 'user'
                    ORDER BY m.timestamp ASC LIMIT 1) AS first_user_msg
            FROM sessions s
            WHERE s.message_count >= 2
              AND s.started_at >= ?
              AND s.source != 'cron'
            ORDER BY s.started_at DESC
            LIMIT 30
            """
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            recentSessions = []
            return
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_double(stmt, 1, cutoff)

        var results: [SessionSummary] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = String(cString: sqlite3_column_text(stmt, 0))
            let source = String(cString: sqlite3_column_text(stmt, 1))
            let title: String? = sqlite3_column_type(stmt, 2) != SQLITE_NULL
                ? String(cString: sqlite3_column_text(stmt, 2)) : nil
            let model: String? = sqlite3_column_type(stmt, 3) != SQLITE_NULL
                ? String(cString: sqlite3_column_text(stmt, 3)) : nil
            let startedAt: Date? = sqlite3_column_type(stmt, 4) != SQLITE_NULL
                ? Date(timeIntervalSince1970: sqlite3_column_double(stmt, 4)) : nil
            let messageCount = Int(sqlite3_column_int64(stmt, 5))
            let inputTokens = Int(sqlite3_column_int64(stmt, 6))
            let outputTokens = Int(sqlite3_column_int64(stmt, 7))
            let firstUserMessage: String? = sqlite3_column_type(stmt, 8) != SQLITE_NULL
                ? String(cString: sqlite3_column_text(stmt, 8)) : nil

            results.append(SessionSummary(
                id: id, source: source, title: title, model: model,
                startedAt: startedAt, messageCount: messageCount,
                firstUserMessage: firstUserMessage,
                inputTokens: inputTokens, outputTokens: outputTokens
            ))
        }
        recentSessions = results
    }

    /// Load messages for a specific session (user + assistant only, oldest first)
    func messagesForSession(sessionId: String) -> [SessionMessage] {
        guard let db = openDB() else { return [] }
        defer { sqlite3_close(db) }

        var stmt: OpaquePointer?
        let sql = """
            SELECT role, content, timestamp FROM messages
            WHERE session_id = ? AND role IN ('user', 'assistant')
            ORDER BY timestamp ASC
            """
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (sessionId as NSString).utf8String, -1, nil)

        var results: [SessionMessage] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let role = String(cString: sqlite3_column_text(stmt, 0))
            let content = sqlite3_column_type(stmt, 1) != SQLITE_NULL
                ? String(cString: sqlite3_column_text(stmt, 1)) : ""
            let timestamp: Date? = sqlite3_column_type(stmt, 2) != SQLITE_NULL
                ? Date(timeIntervalSince1970: sqlite3_column_double(stmt, 2)) : nil
            results.append(SessionMessage(role: role, content: content, timestamp: timestamp))
        }
        return results
    }

    private func openDB() -> OpaquePointer? {
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return nil }
        return db
    }
}

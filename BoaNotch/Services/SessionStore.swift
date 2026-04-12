import Foundation
import SQLite3

struct SessionSummary: Identifiable {
    let id: String
    let source: String
    let title: String?
    let model: String?
    let updatedAt: Date?
    let inputTokens: Int
    let outputTokens: Int

    var displayTitle: String { title ?? "Untitled" }

    var sourceIcon: String {
        switch source {
        case "telegram": return "paperplane.fill"
        case "cli": return "terminal.fill"
        case "discord": return "bubble.left.fill"
        default: return "bubble.left.and.bubble.right.fill"
        }
    }
}

struct SessionMessage {
    let role: String
    let content: String
    let createdAt: Date?
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
    private let dateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

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

    /// Load recent sessions from Hermes state.db (max 30, newest first)
    func loadRecentSessions() {
        guard let db = openDB() else {
            recentSessions = []
            return
        }
        defer { sqlite3_close(db) }

        var stmt: OpaquePointer?
        let sql = """
            SELECT id, source, title, model, updated_at, input_tokens, output_tokens
            FROM sessions
            WHERE ended_at IS NULL OR ended_at > datetime('now', '-30 days')
            ORDER BY updated_at DESC
            LIMIT 30
            """
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            recentSessions = []
            return
        }
        defer { sqlite3_finalize(stmt) }

        var results: [SessionSummary] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = String(cString: sqlite3_column_text(stmt, 0))
            let source = String(cString: sqlite3_column_text(stmt, 1))
            let title: String? = sqlite3_column_type(stmt, 2) != SQLITE_NULL
                ? String(cString: sqlite3_column_text(stmt, 2)) : nil
            let model: String? = sqlite3_column_type(stmt, 3) != SQLITE_NULL
                ? String(cString: sqlite3_column_text(stmt, 3)) : nil
            let updatedAt: Date? = sqlite3_column_type(stmt, 4) != SQLITE_NULL
                ? parseDate(String(cString: sqlite3_column_text(stmt, 4))) : nil
            let inputTokens = Int(sqlite3_column_int64(stmt, 5))
            let outputTokens = Int(sqlite3_column_int64(stmt, 6))

            results.append(SessionSummary(
                id: id, source: source, title: title, model: model,
                updatedAt: updatedAt, inputTokens: inputTokens, outputTokens: outputTokens
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
            SELECT role, content, created_at FROM messages
            WHERE session_id = ? AND role IN ('user', 'assistant')
            ORDER BY created_at ASC
            """
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (sessionId as NSString).utf8String, -1, nil)

        var results: [SessionMessage] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let role = String(cString: sqlite3_column_text(stmt, 0))
            let content = sqlite3_column_type(stmt, 1) != SQLITE_NULL
                ? String(cString: sqlite3_column_text(stmt, 1)) : ""
            let createdAt: Date? = sqlite3_column_type(stmt, 2) != SQLITE_NULL
                ? parseDate(String(cString: sqlite3_column_text(stmt, 2))) : nil
            results.append(SessionMessage(role: role, content: content, createdAt: createdAt))
        }
        return results
    }

    private func parseDate(_ string: String) -> Date? {
        dateFormatter.date(from: string)
    }

    private func openDB() -> OpaquePointer? {
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return nil }
        return db
    }
}

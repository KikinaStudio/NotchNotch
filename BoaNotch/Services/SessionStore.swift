import Foundation
import SQLite3

struct SessionSummary: Identifiable {
    let id: String
    let source: String
    let title: String?
    let model: String?
    /// Last message, else the session start. Sorts the history and shows its relative date.
    let lastActiveAt: Date?
    let messageCount: Int
    let firstUserMessage: String?
    let inputTokens: Int
    let outputTokens: Int
    /// NotchNotch's `notchnotch-<uuid>` for this row (`sessions.session_key` on v0.21.6+, the row
    /// id on older gateways), else the row id. Keys TitleStore and the active-session match.
    let conversationKey: String

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

    /// Load recent sessions from Hermes state.db (max 30, most recently active first).
    /// Excludes one-shot stubs (`message_count < 2`) and sessions idle for more than 60 days.
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
        // Newest activity first (last message, else the start): a resumed conversation moves
        // back to the top instead of staying at the date it was opened.
        func sql(notchnotchKey: String) -> String { """
            SELECT s.id, s.source, s.title, s.model, a.last_active,
                   s.message_count, s.input_tokens, s.output_tokens,
                   (SELECT m.content FROM messages m
                    WHERE m.session_id = s.id AND m.role = 'user'
                    ORDER BY m.timestamp ASC LIMIT 1) AS first_user_msg,
                   COALESCE(\(notchnotchKey), s.id) AS conversation_key
            FROM (SELECT s2.id AS sid,
                         COALESCE((SELECT MAX(m.timestamp) FROM messages m WHERE m.session_id = s2.id),
                                  s2.started_at) AS last_active
                  FROM sessions s2
                  WHERE s2.message_count >= 2 AND s2.source != 'cron') a
            JOIN sessions s ON s.id = a.sid
            WHERE a.last_active >= ?
            ORDER BY a.last_active DESC
            LIMIT 30
            """ }
        // The key is the raw `session_key` (v0.21.6–v0.22.2), the tail of the v0.22.5+ route
        // (`agent:main:api_server:dm:notchnotch-…`), or, for a conversation whose row id is not
        // the key, Hermes's key registry (matched on `chat_id`, which compression children keep).
        // Older schemas drop the registry, then `session_key` (pre-mid-2026), and use the row id.
        let routeKey = """
            CASE WHEN s.session_key LIKE 'notchnotch-%' THEN s.session_key
                 WHEN s.session_key LIKE '%:notchnotch-%'
                 THEN substr(s.session_key, instr(s.session_key, ':notchnotch-') + 1) END
            """
        let registryKey = """
            (SELECT substr(m.key, \(Self.declaredKeyPrefix.count + 1)) FROM state_meta m
             WHERE m.key LIKE '\(Self.declaredKeyPrefix)notchnotch-%' AND m.value IN (s.id, s.chat_id) LIMIT 1)
            """
        let keyExpressions = ["COALESCE(\(routeKey), \(registryKey))", routeKey, "NULL"]
        guard keyExpressions.contains(where: {
            sqlite3_prepare_v2(db, sql(notchnotchKey: $0), -1, &stmt, nil) == SQLITE_OK
        }) else {
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
            let lastActiveAt: Date? = sqlite3_column_type(stmt, 4) != SQLITE_NULL
                ? Date(timeIntervalSince1970: sqlite3_column_double(stmt, 4)) : nil
            let messageCount = Int(sqlite3_column_int64(stmt, 5))
            let inputTokens = Int(sqlite3_column_int64(stmt, 6))
            let outputTokens = Int(sqlite3_column_int64(stmt, 7))
            let firstUserMessage: String? = sqlite3_column_type(stmt, 8) != SQLITE_NULL
                ? String(cString: sqlite3_column_text(stmt, 8)) : nil
            let conversationKey = String(cString: sqlite3_column_text(stmt, 9))

            results.append(SessionSummary(
                id: id, source: source, title: title, model: model,
                lastActiveAt: lastActiveAt, messageCount: messageCount,
                firstUserMessage: firstUserMessage,
                inputTokens: inputTokens, outputTokens: outputTokens,
                conversationKey: conversationKey
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

    /// Hermes v0.22.5+ registry of conversation keys: `state_meta` row `<prefix><key>` → session id.
    /// Filled when /v1/responses names a conversation, or when an older row stamped with the raw key
    /// is adopted (its `session_key` then becomes the route of its own id and loses our key).
    private static let declaredKeyPrefix = "gateway.api.conversation.v1."

    /// Id of the state.db row a conversation key continues on (read-only), nil if none or if the
    /// schema predates `session_key`. /v1/chat/completions addresses rows by id. In order: Hermes's
    /// key registry (v0.22.5+, the server follows compression from it), else the most recent row
    /// whose `session_key` is the key (v0.21.6–v0.22.2) or ends with `:<key>` (v0.22.5+ route
    /// `agent:<profile>:api_server:dm:<id>`, where the id is the key for a chat-born conversation).
    static func latestRowId(sessionKey: String) -> String? {
        let path = FileManager.default.homeDirectoryForCurrentUser.path + "/.hermes/state.db"
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return nil
        }
        defer { sqlite3_close(db) }
        let queries = [
            "SELECT s.id FROM state_meta m JOIN sessions s ON s.id = m.value WHERE m.key = '\(declaredKeyPrefix)' || ?1",
            "SELECT id FROM sessions WHERE session_key = ?1 OR session_key LIKE '%:' || ?1 ORDER BY started_at DESC LIMIT 1",
        ]
        for sql in queries {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { continue }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, (sessionKey as NSString).utf8String, -1, nil)
            if sqlite3_step(stmt) == SQLITE_ROW, let text = sqlite3_column_text(stmt, 0) {
                return String(cString: text)
            }
        }
        return nil
    }

    private func openDB() -> OpaquePointer? {
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return nil }
        return db
    }
}

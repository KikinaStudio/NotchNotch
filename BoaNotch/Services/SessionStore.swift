import Foundation
import SQLite3

class SessionStore: ObservableObject {
    /// The Telegram DM session ID, auto-detected from Hermes state.db
    @Published var selectedSessionId: String? {
        didSet { UserDefaults.standard.set(selectedSessionId, forKey: "hermesSessionId") }
    }

    /// Whether a session was found
    @Published var isLinked = false

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

    private func openDB() -> OpaquePointer? {
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return nil }
        return db
    }
}

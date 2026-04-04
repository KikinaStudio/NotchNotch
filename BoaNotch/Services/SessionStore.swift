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

    /// Auto-detect the Telegram DM session from Hermes state.db
    func autoLinkTelegram() {
        guard let db = openDB() else { return }
        defer { sqlite3_close(db) }

        // Find the most recent Telegram session (the user's DM with the bot)
        var stmt: OpaquePointer?
        let sql = "SELECT id FROM sessions WHERE source = 'telegram' ORDER BY started_at DESC LIMIT 1"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        if sqlite3_step(stmt) == SQLITE_ROW {
            let sessionId = String(cString: sqlite3_column_text(stmt, 0))
            if selectedSessionId != sessionId {
                selectedSessionId = sessionId
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

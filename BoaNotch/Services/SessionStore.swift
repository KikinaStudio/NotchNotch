import Foundation
import SQLite3

struct HermesSession: Identifiable, Hashable {
    let id: String
    let source: String
    let title: String
    let startedAt: Date
    let messageCount: Int
}

class SessionStore: ObservableObject {
    @Published var sources: [String] = []
    @Published var sessions: [HermesSession] = []
    @Published var selectedSource: String? = nil {
        didSet { loadSessions() }
    }
    @Published var selectedSessionId: String? {
        didSet { UserDefaults.standard.set(selectedSessionId, forKey: "hermesSessionId") }
    }

    private let dbPath: String

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        self.dbPath = "\(home)/.hermes/state.db"
        self.selectedSessionId = UserDefaults.standard.string(forKey: "hermesSessionId")
        refresh()
    }

    func refresh() {
        loadSources()
        loadSessions()
    }

    func disconnect() {
        selectedSessionId = nil
        selectedSource = nil
        sessions = []
    }

    private func loadSources() {
        guard let db = openDB() else { return }
        defer { sqlite3_close(db) }

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT DISTINCT source FROM sessions WHERE source != 'api_server' ORDER BY source", -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        var result: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let cStr = sqlite3_column_text(stmt, 0) {
                result.append(String(cString: cStr))
            }
        }
        sources = result
    }

    private func loadSessions() {
        guard let source = selectedSource, let db = openDB() else {
            sessions = []
            return
        }
        defer { sqlite3_close(db) }

        var stmt: OpaquePointer?
        let sql = "SELECT id, source, title, started_at, message_count FROM sessions WHERE source = ? ORDER BY started_at DESC LIMIT 20"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (source as NSString).utf8String, -1, nil)

        var result: [HermesSession] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = String(cString: sqlite3_column_text(stmt, 0))
            let src = String(cString: sqlite3_column_text(stmt, 1))
            let title = sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? ""
            let startedAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 3))
            let msgCount = Int(sqlite3_column_int(stmt, 4))
            result.append(HermesSession(id: id, source: src, title: title, startedAt: startedAt, messageCount: msgCount))
        }
        sessions = result
    }

    private func openDB() -> OpaquePointer? {
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return nil }
        return db
    }
}

import Foundation

/// Persistent cache of LLM-generated titles for NotchNotch sessions.
/// Stored at ~/Library/Application Support/NotchNotch/session_titles.json.
/// Used because Hermes does not auto-title `/v1/responses` sessions.
class TitleStore: ObservableObject {
    @Published private(set) var titles: [String: String] = [:]

    private let fileURL: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = support.appendingPathComponent("NotchNotch", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("session_titles.json")
        load()
    }

    func title(for sessionId: String) -> String? {
        titles[sessionId]
    }

    func setTitle(_ title: String, for sessionId: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        titles[sessionId] = trimmed
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else {
            return
        }
        titles = dict
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(titles) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

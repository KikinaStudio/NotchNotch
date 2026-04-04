import Foundation

struct SearchMatch: Identifiable {
    let id = UUID()
    let messageId: UUID
    let range: Range<String.Index>
}

class SearchViewModel: ObservableObject {
    @Published var query: String = "" {
        didSet { search() }
    }
    @Published var matches: [SearchMatch] = []
    @Published var currentMatchIndex: Int = 0

    weak var chatVM: ChatViewModel?

    var totalMatches: Int { matches.count }

    var currentMessageId: UUID? {
        guard !matches.isEmpty else { return nil }
        return matches[currentMatchIndex].messageId
    }

    func nextMatch() {
        guard !matches.isEmpty else { return }
        currentMatchIndex = (currentMatchIndex + 1) % matches.count
    }

    func previousMatch() {
        guard !matches.isEmpty else { return }
        currentMatchIndex = (currentMatchIndex - 1 + matches.count) % matches.count
    }

    func close() {
        query = ""
        matches = []
        currentMatchIndex = 0
    }

    private func search() {
        guard let chatVM, !query.isEmpty else {
            matches = []
            currentMatchIndex = 0
            return
        }

        let q = query.lowercased()
        var result: [SearchMatch] = []

        for message in chatVM.messages {
            let content = message.content.lowercased()
            var searchStart = content.startIndex
            while let range = content.range(of: q, range: searchStart..<content.endIndex) {
                result.append(SearchMatch(messageId: message.id, range: range))
                searchStart = range.upperBound
            }
        }

        matches = result
        currentMatchIndex = result.isEmpty ? 0 : max(0, min(currentMatchIndex, result.count - 1))
    }
}

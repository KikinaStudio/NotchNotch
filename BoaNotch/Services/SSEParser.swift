import Foundation

/// Raw SSE event emitted by the tokenizer. Carries only what the wire
/// format preserves — the name (from `event:` lines) and the JSON `data:`
/// payload concatenated with newlines per the SSE spec. Hermes semantics
/// live inside `HermesClient.streamResponse`, not here.
struct SSEEvent {
    let name: String?
    let data: String
}

/// AsyncSequence wrapping `URLSession.AsyncBytes`. Yields one `SSEEvent`
/// per blank-line-terminated block. Comment lines (`:`), `id:`, and
/// `retry:` lines are ignored.
struct SSEStream: AsyncSequence {
    typealias Element = SSEEvent
    let bytes: URLSession.AsyncBytes

    func makeAsyncIterator() -> Iterator {
        Iterator(lines: bytes.lines.makeAsyncIterator())
    }

    struct Iterator: AsyncIteratorProtocol {
        var lines: AsyncLineSequence<URLSession.AsyncBytes>.AsyncIterator
        var done = false

        mutating func next() async throws -> SSEEvent? {
            if done { return nil }
            var name: String? = nil
            var dataLines: [String] = []

            while let line = try await lines.next() {
                if line.isEmpty {
                    if !dataLines.isEmpty || name != nil {
                        return SSEEvent(name: name, data: dataLines.joined(separator: "\n"))
                    }
                    continue
                }
                if line.hasPrefix(":") {
                    continue
                }
                if line.hasPrefix("event:") {
                    name = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                } else if line.hasPrefix("data:") {
                    var v = String(line.dropFirst(5))
                    if v.hasPrefix(" ") { v.removeFirst() }
                    dataLines.append(v)
                }
            }

            done = true
            if !dataLines.isEmpty || name != nil {
                return SSEEvent(name: name, data: dataLines.joined(separator: "\n"))
            }
            return nil
        }
    }
}

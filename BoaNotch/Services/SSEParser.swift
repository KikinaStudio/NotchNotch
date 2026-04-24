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
///
/// Implementation note: we read raw bytes rather than `bytes.lines`
/// because `AsyncLineSequence<URLSession.AsyncBytes>` silently drops
/// empty lines, which are exactly the event separators in SSE. Lining
/// up events manually on `\n` lets us see blank lines and terminate
/// events correctly.
struct SSEStream: AsyncSequence {
    typealias Element = SSEEvent
    let bytes: URLSession.AsyncBytes

    func makeAsyncIterator() -> Iterator {
        Iterator(bytes: bytes.makeAsyncIterator())
    }

    struct Iterator: AsyncIteratorProtocol {
        var bytes: URLSession.AsyncBytes.AsyncIterator
        var done = false
        // Bytes buffered for the line currently being read (up to but not
        // including the terminating `\n`). Trailing `\r` is stripped when
        // the line is finalised so we tolerate CRLF servers too.
        var currentLine: [UInt8] = []
        // Event state persisted across lines until a blank line fires the
        // yield. Cleared before returning so the next `next()` call starts
        // fresh.
        var eventName: String? = nil
        var eventData: [String] = []

        mutating func next() async throws -> SSEEvent? {
            if done { return nil }

            while true {
                guard let byte = try await bytes.next() else {
                    done = true
                    // Stream closed — flush any partially read line, then
                    // yield the pending event if we have one.
                    if !currentLine.isEmpty {
                        flushCurrentLine()
                    }
                    if !eventData.isEmpty || eventName != nil {
                        let event = SSEEvent(name: eventName, data: eventData.joined(separator: "\n"))
                        eventName = nil
                        eventData.removeAll()
                        return event
                    }
                    return nil
                }

                if byte == 0x0A { // LF — line terminator
                    if currentLine.last == 0x0D { currentLine.removeLast() }
                    let line = String(bytes: currentLine, encoding: .utf8) ?? ""
                    currentLine.removeAll()

                    if line.isEmpty {
                        // Blank line = event boundary. Yield and reset.
                        if !eventData.isEmpty || eventName != nil {
                            let event = SSEEvent(name: eventName, data: eventData.joined(separator: "\n"))
                            eventName = nil
                            eventData.removeAll()
                            return event
                        }
                        // Stray blank before any event data — keep reading.
                    } else {
                        processLine(line)
                    }
                } else {
                    currentLine.append(byte)
                }
            }
        }

        mutating func flushCurrentLine() {
            if currentLine.last == 0x0D { currentLine.removeLast() }
            if let line = String(bytes: currentLine, encoding: .utf8), !line.isEmpty {
                processLine(line)
            }
            currentLine.removeAll()
        }

        mutating func processLine(_ line: String) {
            if line.hasPrefix(":") { return }
            if line.hasPrefix("event:") {
                eventName = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("data:") {
                var v = String(line.dropFirst(5))
                if v.hasPrefix(" ") { v.removeFirst() }
                eventData.append(v)
            }
            // `id:`, `retry:`, and any other field names are ignored per spec.
        }
    }
}

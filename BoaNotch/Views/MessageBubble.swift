import SwiftUI
import AppKit

struct MessageBubble: View {
    let message: ChatMessage
    var searchQuery: String? = nil
    var onSaveToBrain: (() -> Void)? = nil

    private var isUser: Bool { message.role == .user }

    @State private var showThinking = false
    @State private var showToolCalls = false
    @State private var brainHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Attachment pills
            if !message.attachments.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(message.attachments) { att in
                        attachmentCard(att)
                    }
                }
            }

            // Collapsible thinking section
            if !message.thinkingContent.isEmpty {
                thinkingToggle
            }

            // Collapsible tool calling section
            if !message.toolCallContent.isEmpty {
                toolCallToggle
            }

            // Message content with clickable file paths (final response only)
            if !displayContent.isEmpty {
                filePathAwareContent
                    .overlay(alignment: .bottomTrailing) {
                        if !isUser && !message.isStreaming && onSaveToBrain != nil {
                            Button { onSaveToBrain?() } label: {
                                Image(systemName: "brain.head.profile")
                                    .font(.system(size: 12))
                                    .foregroundStyle(brainHovered ? .blue : .gray)
                                    .opacity(brainHovered ? 1.0 : 0.5)
                            }
                            .buttonStyle(.plain)
                            .onHover { brainHovered = $0 }
                            .pointingHandCursor()
                            .offset(x: 4, y: 4)
                        }
                    }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    // MARK: - Thinking toggle

    private var thinkingToggle: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showThinking.toggle() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: showThinking ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                    if message.isStreaming && message.content.isEmpty {
                        Text("Thinking...")
                            .italic()
                    } else {
                        let duration = Int(message.thinkingDuration ?? 0)
                        Text("Thought for \(duration)s")
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.35))
            }
            .buttonStyle(.plain)
            .pointingHandCursor()

            if showThinking {
                Text(message.thinkingContent)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.25))
                    .textSelection(.enabled)
                    .padding(.top, 4)
                    .padding(.leading, 13)
                    .transition(.opacity)
            }
        }
    }

    // MARK: - Tool call toggle

    private var toolCallToggle: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showToolCalls.toggle() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: showToolCalls ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                    Image(systemName: "wrench.and.screwdriver")
                        .font(.system(size: 10))
                    if message.isStreaming && message.content.isEmpty {
                        Text("Using tools...")
                            .italic()
                    } else {
                        Text("Used tools")
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.35))
            }
            .buttonStyle(.plain)
            .pointingHandCursor()

            if showToolCalls {
                Text(message.toolCallContent)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.25))
                    .textSelection(.enabled)
                    .padding(.top, 4)
                    .padding(.leading, 13)
                    .transition(.opacity)
            }
        }
    }

    // MARK: - Content with clickable file paths

    @ViewBuilder
    private var filePathAwareContent: some View {
        let blocks = splitIntoBlocks(displayContent)
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { idx, block in
                switch block {
                case .code(let lang, let code):
                    codeBlock(language: lang, code: code)
                case .text(let text):
                    let parts = splitByFilePaths(text)
                    ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                        if part.isPath {
                            fileCard(part.text)
                        } else if !part.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            HStack(alignment: .lastTextBaseline, spacing: 0) {
                                Text(markdownString(part.text))
                                    .font(.system(size: 14))
                                    .foregroundStyle(isUser ? AppColors.accent : .white.opacity(0.88))
                                    .textSelection(.enabled)

                                if message.isStreaming && idx == blocks.count - 1 && part == parts.last {
                                    Text("▊")
                                        .font(.system(size: 13))
                                        .foregroundStyle(.white.opacity(0.3))
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Code block rendering

    private func codeBlock(language: String, code: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if !language.isEmpty {
                Text(language)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.35))
                    .padding(.horizontal, 10)
                    .padding(.top, 6)
                    .padding(.bottom, 2)
            }
            Text(code)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.white.opacity(0.8))
                .textSelection(.enabled)
                .padding(.horizontal, 10)
                .padding(.vertical, language.isEmpty ? 8 : 4)
                .padding(.bottom, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Block parsing (code blocks vs text)

    enum ContentBlock {
        case text(String)
        case code(String, String) // (language, code)
    }

    private func splitIntoBlocks(_ text: String) -> [ContentBlock] {
        var blocks: [ContentBlock] = []
        var remaining = text

        while let openRange = remaining.range(of: "```") {
            // Text before the code block
            let before = String(remaining[remaining.startIndex..<openRange.lowerBound])
            if !before.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                blocks.append(.text(before))
            }

            let afterOpen = remaining[openRange.upperBound...]
            // Extract language hint (first line after ```)
            var lang = ""
            if let newline = afterOpen.firstIndex(of: "\n") {
                lang = String(afterOpen[afterOpen.startIndex..<newline]).trimmingCharacters(in: .whitespaces)
                let codeStart = afterOpen.index(after: newline)

                if let closeRange = afterOpen[codeStart...].range(of: "```") {
                    let code = String(afterOpen[codeStart..<closeRange.lowerBound])
                        .trimmingCharacters(in: .newlines)
                    blocks.append(.code(lang, code))
                    remaining = String(afterOpen[closeRange.upperBound...])
                } else {
                    // Unclosed code block (still streaming) — treat rest as code
                    let code = String(afterOpen[codeStart...]).trimmingCharacters(in: .newlines)
                    blocks.append(.code(lang, code))
                    remaining = ""
                }
            } else {
                // No newline after ``` — still streaming the opening
                remaining = String(afterOpen)
            }
        }

        if !remaining.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            blocks.append(.text(remaining))
        }

        return blocks.isEmpty ? [.text(text)] : blocks
    }

    // MARK: - File card (white pill + path below)

    private func fileCard(_ path: String) -> some View {
        let expanded = (path as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded)
        let fileName = url.lastPathComponent
        let ext = url.pathExtension.lowercased()
        let shortPath = shortenPath(expanded)

        return Button {
            revealInFinder(path)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Image(systemName: sfIconForFileType(ext))
                        .font(.system(size: 12))
                    Text(fileName)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                }
                .foregroundStyle(.black.opacity(0.85))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.white.opacity(0.92))
                .clipShape(RoundedRectangle(cornerRadius: 10))

                Text(shortPath)
                    .font(.system(size: 11, design: .monospaced))
                    .italic()
                    .foregroundStyle(.white.opacity(0.35))
                    .lineLimit(1)
                    .padding(.horizontal, 4)
            }
            .frame(maxWidth: 300)
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }

    // MARK: - Attachment card (same style, subtler)

    private func attachmentCard(_ att: Attachment) -> some View {
        HStack(spacing: 7) {
            Image(systemName: sfIconForFileType(att.fileType))
                .font(.system(size: 11))
            Text(att.fileName)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(.white.opacity(0.5))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Streaming dots

    private var streamingDots: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                StreamingDot(delay: Double(i) * 0.15)
            }
        }
        .frame(height: 18)
    }

    // MARK: - Path parsing

    struct ContentPart: Equatable {
        let text: String
        let isPath: Bool
    }

    private func splitByFilePaths(_ text: String) -> [ContentPart] {
        let pattern = #"(?:~/|/(?:Users|tmp|var|opt|Library|Applications|Volumes|Downloads|Documents|Desktop)[^\s,;:\"')\]}>]*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return [ContentPart(text: text, isPath: false)]
        }

        var parts: [ContentPart] = []
        var lastEnd = text.startIndex
        let nsText = text as NSString

        for match in regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)) {
            guard let range = Range(match.range, in: text) else { continue }
            if lastEnd < range.lowerBound {
                let before = String(text[lastEnd..<range.lowerBound])
                parts.append(ContentPart(text: before, isPath: false))
            }
            var pathStr = String(text[range])
            while pathStr.hasSuffix(".") || pathStr.hasSuffix(",") || pathStr.hasSuffix(":") {
                pathStr = String(pathStr.dropLast())
            }
            parts.append(ContentPart(text: pathStr, isPath: true))
            lastEnd = range.upperBound
        }
        if lastEnd < text.endIndex {
            parts.append(ContentPart(text: String(text[lastEnd...]), isPath: false))
        }

        return parts.isEmpty ? [ContentPart(text: text, isPath: false)] : parts
    }

    private func shortenPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            let relative = String(path.dropFirst(home.count))
            return "~" + relative
        }
        return path
    }

    private func revealInFinder(_ path: String) {
        let expanded = (path as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded)
        if FileManager.default.fileExists(atPath: expanded) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            let parent = url.deletingLastPathComponent()
            if FileManager.default.fileExists(atPath: parent.path) {
                NSWorkspace.shared.open(parent)
            }
        }
    }

    // MARK: - Helpers

    private var displayContent: String {
        var text = message.content
        // Strip attachment markers
        while let startRange = text.range(of: "[Attached:") {
            if let endRange = text.range(of: "[End attachment]", range: startRange.lowerBound..<text.endIndex) {
                let removeEnd = text.index(endRange.upperBound, offsetBy: 1, limitedBy: text.endIndex) ?? endRange.upperBound
                text.removeSubrange(startRange.lowerBound..<removeEnd)
            } else { break }
        }
        // Ensure line breaks around visual separators (⸻, ——, ---)
        text = text.replacingOccurrences(of: "⸻", with: "\n\n⸻\n\n")
        text = text.replacingOccurrences(of: "———", with: "\n\n———\n\n")
        text = text.replacingOccurrences(of: "---", with: "\n\n---\n\n")
        // Clean up excessive newlines
        while text.contains("\n\n\n\n") { text = text.replacingOccurrences(of: "\n\n\n\n", with: "\n\n") }
        // Strip orphan ** markers (unmatched bold that can't render)
        let boldParts = text.components(separatedBy: "**")
        if boldParts.count > 1 && boldParts.count % 2 == 0 {
            if let orphan = text.range(of: "**", options: .backwards) {
                text.removeSubrange(orphan)
            }
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func markdownString(_ text: String) -> AttributedString {
        var result = (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)

        // Apply search highlighting
        if let query = searchQuery, !query.isEmpty {
            let lower = String(result.characters).lowercased()
            let q = query.lowercased()
            var searchStart = lower.startIndex
            while let range = lower.range(of: q, range: searchStart..<lower.endIndex) {
                let attrStart = result.characters.index(result.startIndex, offsetBy: lower.distance(from: lower.startIndex, to: range.lowerBound))
                let attrEnd = result.characters.index(attrStart, offsetBy: q.count)
                result[attrStart..<attrEnd].backgroundColor = .purple.opacity(0.35)
                searchStart = range.upperBound
            }
        }

        return result
    }

}

// MARK: - Animated streaming dot

struct StreamingDot: View {
    let delay: Double
    @State private var animating = false

    var body: some View {
        Circle()
            .fill(.white.opacity(0.4))
            .frame(width: 5, height: 5)
            .offset(y: animating ? -3 : 1)
            .animation(
                .easeInOut(duration: 0.5)
                .repeatForever(autoreverses: true)
                .delay(delay),
                value: animating
            )
            .onAppear { animating = true }
    }
}

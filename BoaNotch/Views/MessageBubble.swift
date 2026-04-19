import SwiftUI
import AppKit

struct MessageBubble: View {
    let message: ChatMessage
    var searchQuery: String? = nil
    var onCopy: (() -> Void)? = nil
    var onRetry: (() -> Void)? = nil
    var onEdit: ((ChatMessage) -> Void)? = nil
    private var isUser: Bool { message.role == .user }

    @State private var showThinking = false
    @State private var showToolCalls = false
    @State private var showCopyConfirm = false
    @State private var isHoveredCopy = false
    @State private var isHoveredRetry = false
    @State private var isHovered = false

    @EnvironmentObject var appearanceSettings: AppearanceSettings

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            VStack(alignment: .leading, spacing: 8) {
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

                // Subagent indicator
                if !message.subagentActivity.isEmpty {
                    subagentIndicator
                }

                // Collapsible tool calling section
                if !message.toolCallContent.isEmpty {
                    toolCallToggle
                }

                // Message content with clickable file paths (final response only)
                if !displayContent.isEmpty {
                    filePathAwareContent
                        .padding(.top, (!message.thinkingContent.isEmpty || !message.toolCallContent.isEmpty) ? 4 : 0)
                }

                // Action buttons for completed assistant messages
                if !isUser && !message.isStreaming && !message.content.isEmpty {
                    HStack(spacing: 12) {
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(displayContent, forType: .string)
                            showCopyConfirm = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                showCopyConfirm = false
                            }
                        } label: {
                            Image(systemName: showCopyConfirm ? "checkmark" : "square.on.square")
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(isHoveredCopy ? 0.5 : 0.25))
                        }
                        .buttonStyle(.plain)
                        .pointingHandCursor()
                        .onHover { isHoveredCopy = $0 }

                        if let onRetry {
                            Button {
                                onRetry()
                            } label: {
                                Image(systemName: "arrow.counterclockwise")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.white.opacity(isHoveredRetry ? 0.5 : 0.25))
                            }
                            .buttonStyle(.plain)
                            .pointingHandCursor()
                            .onHover { isHoveredRetry = $0 }
                        }
                    }
                    .padding(.top, 2)
                }
            }
            .padding(.horizontal, isUser ? 12 : 0)
            .padding(.vertical, isUser ? 8 : 4)
            .frame(maxWidth: isUser ? nil : .infinity, alignment: isUser ? .trailing : .leading)
            .background {
                if isUser {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(red: 19/255.0, green: 19/255.0, blue: 19/255.0).opacity(0.8))
                }
            }

            // Action buttons below user bubble
            if isUser && !message.isStreaming && !message.content.isEmpty {
                HStack(spacing: 12) {
                    if let onEdit {
                        Button { onEdit(message) } label: {
                            Image(systemName: "pencil")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.white.opacity(isHovered ? 0.5 : 0.25))
                        }
                        .buttonStyle(.plain)
                        .pointingHandCursor()
                        .onHover { isHovered = $0 }
                    }

                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(displayContent, forType: .string)
                        showCopyConfirm = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            showCopyConfirm = false
                        }
                    } label: {
                        Image(systemName: showCopyConfirm ? "checkmark" : "square.on.square")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(isHoveredCopy ? 0.5 : 0.25))
                    }
                    .buttonStyle(.plain)
                    .pointingHandCursor()
                    .onHover { isHoveredCopy = $0 }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
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

    // MARK: - Subagent indicator

    private var subagentLabel: String {
        let parts = message.subagentActivity.components(separatedBy: "🤖").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if parts.count > 1 {
            return "\(parts.count) sub-tasks delegated"
        }
        if let desc = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines), !desc.isEmpty {
            return "Delegated: \(desc)"
        }
        return "Working with a sub-agent..."
    }

    private var subagentIndicator: some View {
        HStack(spacing: 5) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 9))
            Text(subagentLabel)
                .font(.system(size: 11))
        }
        .foregroundStyle(AppColors.accent.opacity(0.6))
        .padding(.vertical, 2)
    }

    // MARK: - Content with clickable file paths

    @ViewBuilder
    private var filePathAwareContent: some View {
        let blocks = splitIntoBlocks(displayContent)
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { idx, block in
                switch block {
                case .code(let lang, let code):
                    let codeParts = splitByFilePaths(code)
                    let hasPath = codeParts.contains(where: { $0.isPath })
                    // If the code block is just a path (possibly with a short command prefix), replace with file card/image
                    if hasPath && code.trimmingCharacters(in: .whitespacesAndNewlines).count < 300 {
                        ForEach(Array(codeParts.enumerated()), id: \.offset) { _, part in
                            if part.isPath {
                                let expanded = (part.text as NSString).expandingTildeInPath
                                let ext = URL(fileURLWithPath: expanded).pathExtension.lowercased()
                                if imageExtensions.contains(ext) {
                                    imagePreview(part.text)
                                } else {
                                    fileCard(part.text)
                                }
                            }
                        }
                    } else {
                        codeBlock(language: lang, code: code)
                    }
                case .blockquote(let text):
                    HStack(alignment: .top, spacing: 8) {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(.white.opacity(0.15))
                            .frame(width: 2)
                        Text(markdownString(text))
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.55))
                            .lineSpacing(3)
                            .italic()
                    }
                    .padding(.leading, 4)
                case .text(let text):
                    let parts = splitByFilePaths(text)
                    ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                        if part.isPath {
                            let expanded = (part.text as NSString).expandingTildeInPath
                            let ext = URL(fileURLWithPath: expanded).pathExtension.lowercased()
                            if imageExtensions.contains(ext) {
                                imagePreview(part.text)
                            } else {
                                fileCard(part.text)
                            }
                        } else if !part.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            HStack(alignment: .lastTextBaseline, spacing: 0) {
                                Text(markdownString(part.text))
                                    .font(.system(size: 14 * appearanceSettings.textSize.scale))
                                    .lineSpacing(isUser ? 0 : 4)
                                    .foregroundStyle(.white.opacity(0.82))
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
        case blockquote(String)
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

        // Post-process: extract blockquote lines from text blocks
        let raw = blocks.isEmpty ? [.text(text)] : blocks
        var final: [ContentBlock] = []
        for block in raw {
            guard case .text(let t) = block else { final.append(block); continue }
            let lines = t.components(separatedBy: "\n")
            var buf: [String] = []
            var inQuote = false
            for line in lines {
                if line.hasPrefix("> ") {
                    if !inQuote {
                        let joined = buf.joined(separator: "\n")
                        if !joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            final.append(.text(joined))
                        }
                        buf = []
                        inQuote = true
                    }
                    buf.append(String(line.dropFirst(2)))
                } else {
                    if inQuote {
                        final.append(.blockquote(buf.joined(separator: "\n")))
                        buf = []
                        inQuote = false
                    }
                    buf.append(line)
                }
            }
            if !buf.isEmpty {
                if inQuote {
                    final.append(.blockquote(buf.joined(separator: "\n")))
                } else {
                    let joined = buf.joined(separator: "\n")
                    if !joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        final.append(.text(joined))
                    }
                }
            }
        }
        return final.isEmpty ? [.text(text)] : final
    }

    private let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic", "svg", "tiff", "bmp"]

    // MARK: - Inline image preview

    @ViewBuilder
    private func imagePreview(_ path: String) -> some View {
        let expanded = (path as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded)
        let shortPath = shortenPath(expanded)

        if let nsImage = NSImage(contentsOf: url) {
            VStack(alignment: .leading, spacing: 3) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 280, maxHeight: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.1), lineWidth: 0.5))
                    .onTapGesture { NSWorkspace.shared.open(url) }
                    .contextMenu {
                        Button("Open in default app") { NSWorkspace.shared.open(url) }
                        Button("Reveal in Finder") { revealInFinder(path) }
                    }

                Text(shortPath)
                    .font(.system(size: 11, design: .monospaced))
                    .italic()
                    .foregroundStyle(.white.opacity(0.35))
                    .lineLimit(1)
                    .padding(.horizontal, 4)
            }
            .pointingHandCursor()
        } else {
            fileCard(path)
        }
    }

    // MARK: - File card (white pill + path below)

    private func fileCard(_ path: String) -> some View {
        let expanded = (path as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded)
        let fileName = url.lastPathComponent
        let ext = url.pathExtension.lowercased()
        let shortPath = shortenPath(expanded)
        let color = colorForFileType(ext)

        return Button {
            NSWorkspace.shared.open(url)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Image(systemName: sfIconForFileType(ext))
                        .font(.system(size: 12))
                    Text(fileName)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                }
                .foregroundStyle(color)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(color.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(color.opacity(0.25), lineWidth: 0.5))

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
        .contextMenu {
            Button("Reveal in Finder") { revealInFinder(path) }
        }
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

    // MARK: - Path parsing

    struct ContentPart: Equatable {
        let text: String
        let isPath: Bool
    }

    private func splitByFilePaths(_ text: String) -> [ContentPart] {
        // Two branches:
        // 1. Backtick-delimited paths (allows spaces): `~/path with spaces/file.ext`
        // 2. Bare paths (no spaces): ~/path/file.ext
        let pattern = #"`((?:~/|/(?:Users|tmp|var|opt|Library|Applications|Volumes|Downloads|Documents|Desktop))[^`]+)`|(?:~/|/(?:Users|tmp|var|opt|Library|Applications|Volumes|Downloads|Documents|Desktop))[^\s,;:\"')\]}>]*"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return [ContentPart(text: text, isPath: false)]
        }

        var parts: [ContentPart] = []
        var lastEnd = text.startIndex
        let nsText = text as NSString

        for match in regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)) {
            guard let fullRange = Range(match.range, in: text) else { continue }
            if lastEnd < fullRange.lowerBound {
                let before = String(text[lastEnd..<fullRange.lowerBound])
                parts.append(ContentPart(text: before, isPath: false))
            }
            // Group 1 = backtick-delimited path (without backticks), else full match
            var pathStr: String
            if match.range(at: 1).location != NSNotFound,
               let groupRange = Range(match.range(at: 1), in: text) {
                pathStr = String(text[groupRange])
            } else {
                pathStr = String(text[fullRange])
            }
            while pathStr.hasSuffix(".") || pathStr.hasSuffix(",") || pathStr.hasSuffix(":") {
                pathStr = String(pathStr.dropLast())
            }
            parts.append(ContentPart(text: pathStr, isPath: true))
            lastEnd = fullRange.upperBound
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

        // Reduce bold weight to semibold for dark-mode readability
        for run in result.runs {
            if let inlinePresentationIntent = run.inlinePresentationIntent,
               inlinePresentationIntent.contains(.stronglyEmphasized) {
                let range = run.range
                result[range].font = .system(size: 14, weight: .semibold)
            }
        }

        // Apply search highlighting
        if let query = searchQuery, !query.isEmpty {
            let lower = String(result.characters).lowercased()
            let q = query.lowercased()
            var searchStart = lower.startIndex
            while let range = lower.range(of: q, range: searchStart..<lower.endIndex) {
                let attrStart = result.characters.index(result.startIndex, offsetBy: lower.distance(from: lower.startIndex, to: range.lowerBound))
                let attrEnd = result.characters.index(attrStart, offsetBy: q.count)
                result[attrStart..<attrEnd].backgroundColor = NSColor(red: 0.15, green: 0.38, blue: 0.51, alpha: 0.35)
                searchStart = range.upperBound
            }
        }

        return result
    }

}

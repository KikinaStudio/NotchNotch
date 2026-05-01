import SwiftUI
import AppKit

struct MessageBubble: View {
    let message: ChatMessage
    var searchQuery: String? = nil
    var onCopy: (() -> Void)? = nil
    var onRetry: (() -> Void)? = nil
    var onEdit: ((ChatMessage) -> Void)? = nil
    var onRefine: ((String) -> Void)? = nil
    var isChatStreaming: Bool = false
    private var isUser: Bool { message.role == .user }

    @State private var showCopyConfirm = false
    @State private var isHoveredCopy = false
    @State private var isHoveredRetry = false
    @State private var isHoveredRefine = false
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

                // Unified agent activity timeline: thinking + tool calls
                // surface as a single live line during streaming and a
                // synthetic recap once finished. Self-contained: hides
                // itself when there's nothing to show.
                EventTimeline(message: message)

                // Message content with clickable file paths (final response only)
                if !displayContent.isEmpty {
                    filePathAwareContent
                        .padding(.top, message.hasEvents ? 4 : 0)
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
                                .font(DS.Text.caption)
                                // TODO(design): 0.28 idle — picked between quaternary (0.22) and tertiary (0.30) for icon visibility
                                .foregroundStyle(isHoveredCopy ? AnyShapeStyle(DS.Surface.secondary) : AnyShapeStyle(.white.opacity(0.28)))
                        }
                        .buttonStyle(.plain)
                        .pointingHandCursor()
                        .onHover { isHoveredCopy = $0 }

                        if let onRetry {
                            Button {
                                onRetry()
                            } label: {
                                Image(systemName: "arrow.counterclockwise")
                                    .font(DS.Text.caption)
                                    // TODO(design): 0.28 idle — picked between quaternary (0.22) and tertiary (0.30) for icon visibility
                                    .foregroundStyle(isHoveredRetry ? AnyShapeStyle(DS.Surface.secondary) : AnyShapeStyle(.white.opacity(0.28)))
                            }
                            .buttonStyle(.plain)
                            .pointingHandCursor()
                            .onHover { isHoveredRetry = $0 }
                        }

                        if let routineId = message.routineId, let onRefine {
                            Button {
                                onRefine(routineId)
                            } label: {
                                Image(systemName: "wand.and.stars")
                                    .font(DS.Text.caption)
                                    // TODO(design): 0.28 idle — same as Copy/Retry for consistency
                                    .foregroundStyle(isHoveredRefine ? AnyShapeStyle(DS.Surface.secondary) : AnyShapeStyle(.white.opacity(0.28)))
                            }
                            .buttonStyle(.plain)
                            .pointingHandCursor()
                            .onHover { isHoveredRefine = $0 }
                            .disabled(isChatStreaming)
                            .opacity(isChatStreaming ? 0.4 : 1.0)
                            .help(isChatStreaming ? "Hermes répond…" : "Affine cette routine")
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
                        .fill(Color.white.opacity(0.08))
                }
            }

            // Action buttons below user bubble
            if isUser && !message.isStreaming && !message.content.isEmpty {
                HStack(spacing: 12) {
                    if let onEdit {
                        Button { onEdit(message) } label: {
                            Image(systemName: "square.and.pencil")
                                .font(DS.Text.captionMedium)
                                // TODO(design): 0.28 idle — picked between quaternary (0.22) and tertiary (0.30) for icon visibility
                                .foregroundStyle(isHovered ? AnyShapeStyle(DS.Surface.secondary) : AnyShapeStyle(.white.opacity(0.28)))
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
                            .font(DS.Text.caption)
                            .foregroundStyle(isHoveredCopy ? DS.Surface.secondary : DS.Surface.quaternary)
                    }
                    .buttonStyle(.plain)
                    .pointingHandCursor()
                    .onHover { isHoveredCopy = $0 }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
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
                            // TODO(design): 0.15 fill bar — between DS.Stroke.hairline (0.06) and DS.Surface.quaternary (0.22); kept inline for visual fidelity
                            .fill(.white.opacity(0.15))
                            .frame(width: 2)
                        Text(markdownString(text))
                            .font(DS.Text.bodySmall)
                            .foregroundStyle(DS.Surface.secondary)
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
                                    // TODO(design): scaled by accessibility, fixed-size DS.Text.* not applicable
                                    .font(.system(size: messageBodySize))
                                    .lineSpacing(isUser ? 0 : 4)
                                    .foregroundStyle(DS.Surface.primary)
                                    .textSelection(.enabled)

                                if message.isStreaming && idx == blocks.count - 1 && part == parts.last {
                                    Text("▊")
                                        .font(DS.Text.bodySmall)
                                        .foregroundStyle(DS.Surface.tertiary)
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
                    .font(DS.Text.microMono)
                    .fontWeight(.medium)
                    .foregroundStyle(DS.Surface.tertiary)
                    .padding(.horizontal, 10)
                    .padding(.top, 6)
                    .padding(.bottom, 2)
            }
            Text(code)
                .font(DS.Text.codeBlock)
                .foregroundStyle(DS.Surface.primary)
                .textSelection(.enabled)
                .padding(.horizontal, 10)
                .padding(.vertical, language.isEmpty ? 8 : 4)
                .padding(.bottom, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Stroke.hairline)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.chip))
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
                    // TODO(design): 0.1 stroke — between DS.Stroke.hairline (0.06) and 0.15; kept inline for visual fidelity
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.1), lineWidth: DS.Hairline.standard))
                    .onTapGesture { NSWorkspace.shared.open(url) }
                    .contextMenu {
                        Button("Open in default app") { NSWorkspace.shared.open(url) }
                        Button("Reveal in Finder") { revealInFinder(path) }
                    }

                Text(shortPath)
                    .font(DS.Text.captionMono)
                    .italic()
                    .foregroundStyle(DS.Surface.tertiary)
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
                        .font(DS.Text.label)
                    Text(fileName)
                        .font(DS.Text.bodySmall)
                        .fontWeight(.medium)
                        .lineLimit(1)
                }
                .foregroundStyle(color)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(color.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(color.opacity(0.25), lineWidth: DS.Hairline.standard))

                Text(shortPath)
                    .font(DS.Text.captionMono)
                    .italic()
                    .foregroundStyle(DS.Surface.tertiary)
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
                .font(DS.Text.caption)
            Text(att.fileName)
                .font(DS.Text.labelMedium)
                .lineLimit(1)
        }
        .foregroundStyle(DS.Surface.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(DS.Stroke.hairline)
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

    private var messageBodySize: CGFloat {
        switch appearanceSettings.textSize {
        case .medium: return 12
        case .large:  return 15
        }
    }

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
                result[range].font = .system(size: messageBodySize, weight: .semibold)
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

// MARK: - Agent activity timeline
//
// Single-line surface for the message's `events` array. While streaming
// shows the most recent in-progress event with a spinner; once done shows
// a synthetic recap (`brain Thought for 3s and called 4 tools`). Tap the
// chevron to reveal the full ordered timeline. Each row in the expansion
// has its own per-event chevron to drill into the raw detail (tool args
// + result, or thinking text — clamped to 600 chars).
//
// Hides itself entirely when `message.events` is empty.

private struct EventTimeline: View {
    let message: ChatMessage
    @State private var isExpanded = false
    @State private var pulseOpacity: Double = 0.3

    var body: some View {
        if !message.hasEvents && !message.isStreaming {
            EmptyView()
        } else if !message.hasEvents && message.isStreaming {
            // Pre-first-event grace state: a fresh assistant message with
            // no events yet (e.g. the model is still warming up before
            // emitting any thinking or tool call). Show a soft "Thinking…"
            // pulse so the bubble isn't blank.
            HStack(spacing: 5) {
                Image(systemName: "brain")
                    .font(DS.Text.micro)
                Text("Thinking")
                    .italic()
                Text("…")
                    .opacity(pulseOpacity)
            }
            .font(DS.Text.caption)
            .foregroundStyle(DS.Surface.tertiary)
            .padding(.vertical, 2)
            .onAppear { startPulse() }
        } else if message.isStreaming && message.currentEvent == nil {
            // Between events (a thinking block just closed and the next
            // tool / reasoning block hasn't started yet, or text is rolling
            // out). The "Thought for Ns" recap belongs to the post-stream
            // state, not here — but the user is still waiting, so show a
            // soft "Thinking…" placeholder rather than letting the timeline
            // flicker in and out.
            HStack(spacing: 5) {
                Text("Thinking")
                    .italic()
                Text("…")
                    .opacity(pulseOpacity)
            }
            .font(DS.Text.caption)
            .foregroundStyle(DS.Surface.tertiary)
            .padding(.vertical, 2)
            .onAppear { startPulse() }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(DS.Motion.standard) { isExpanded.toggle() }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(DS.Icon.chevronBold)
                        headerContent
                    }
                    .font(DS.Text.caption)
                    .foregroundStyle(DS.Surface.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .pointingHandCursor()

                if isExpanded {
                    expandedList
                        .padding(.top, 4)
                        .padding(.leading, 13)
                }
            }
            .padding(.vertical, 2)
            .onAppear { startPulse() }
        }
    }

    // MARK: header (single live line OR recap)

    @ViewBuilder
    private var headerContent: some View {
        if message.isStreaming, let current = message.currentEvent {
            inProgressLine(current)
        } else {
            recapLine
        }
    }

    @ViewBuilder
    private func inProgressLine(_ event: AgentEvent) -> some View {
        switch event.kind {
        case .thinking:
            // Live thinking: show the streaming content itself, not just
            // a "Thinking…" placeholder. Pulsing dot signals liveness;
            // text wraps across lines so the user actually reads what
            // the model is reasoning about.
            if event.detail.isEmpty {
                HStack(spacing: 5) {
                    Image(systemName: "brain")
                        .font(DS.Text.micro)
                    Text("Thinking")
                        .italic()
                    Text("…")
                        .opacity(pulseOpacity)
                }
            } else {
                HStack(alignment: .top, spacing: 6) {
                    Circle()
                        .fill(DS.Surface.tertiary)
                        .frame(width: 4, height: 4)
                        .padding(.top, 5)
                        .opacity(pulseOpacity)
                    Text(event.detail)
                        .italic()
                        .lineSpacing(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        case .tool(let name, let argsPreview):
            HStack(spacing: 5) {
                let mapping = AgentEventStyle.verbMapping(toolName: name)
                Image(systemName: mapping.icon)
                    .font(DS.Text.micro)
                Text(mapping.present)
                    .italic()
                if !argsPreview.isEmpty {
                    Text(AgentEventStyle.truncate(argsPreview, max: 50))
                        .font(DS.Text.captionMono)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 6)
                BrailleSpinner(size: 9, color: .white.opacity(0.5))
            }
        }
    }

    @ViewBuilder
    private var recapLine: some View {
        let toolCount = message.toolCallCount
        let thinkingDuration = message.thinkingTotalDuration
        let hasThinking = thinkingDuration >= 0.5
        let hasTools = toolCount > 0
        let icon = hasThinking ? "brain" : "wrench.and.screwdriver"
        let durationLabel = "\(max(1, Int(thinkingDuration.rounded())))s"
        let toolsLabel = "\(toolCount) tool\(toolCount == 1 ? "" : "s")"

        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(DS.Text.micro)
            if hasThinking && hasTools {
                Text("Thought for \(durationLabel) and called \(toolsLabel)")
            } else if hasThinking {
                Text("Thought for \(durationLabel)")
            } else if hasTools {
                Text("Called \(toolsLabel)")
            } else {
                // Events exist but nothing surfaceable (e.g. only failed
                // before any duration was captured). Fall back to a count.
                Text("\(message.events.count) event\(message.events.count == 1 ? "" : "s")")
            }
        }
    }

    // MARK: expanded list

    @ViewBuilder
    private var expandedList: some View {
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: 2) {
                ForEach(message.events) { event in
                    EventLine(event: event)
                        .id(event.id)
                }
            }
            .onChange(of: message.events.count) { _, _ in
                guard let last = message.events.last else { return }
                withAnimation(DS.Motion.standard) {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    private func startPulse() {
        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
            pulseOpacity = 0.85
        }
    }
}

private struct EventLine: View {
    let event: AgentEvent
    @State private var isExpanded = false

    private var isThinking: Bool {
        if case .thinking = event.kind { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isThinking {
                // Thinking events skip both the toggle and the "Thought"
                // header label: when the parent timeline is expanded the
                // user wants to read the reasoning, not click through a
                // second container. Render the content directly.
                if !event.detail.isEmpty {
                    detailBody
                }
            } else {
                Button {
                    withAnimation(DS.Motion.standard) { isExpanded.toggle() }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(DS.Icon.chevronBold)
                        Image(systemName: AgentEventStyle.iconName(for: event))
                            .font(DS.Text.micro)
                        headerLabel
                        Spacer(minLength: 6)
                        durationLabel
                        statusIcon
                    }
                    .font(DS.Text.caption)
                    .foregroundStyle(rowForeground)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .pointingHandCursor()

                if isExpanded {
                    detailBody
                }
            }
        }
    }

    private var rowForeground: AnyShapeStyle {
        if case .failed = event.status {
            return AnyShapeStyle(Color.red.opacity(0.85))
        }
        return DS.Surface.tertiary
    }

    @ViewBuilder
    private var headerLabel: some View {
        switch event.kind {
        case .thinking:
            Text("Thought")
                .lineLimit(1)
        case .tool(let name, let argsPreview):
            HStack(spacing: 4) {
                Text(AgentEventStyle.verbMapping(toolName: name).past)
                if !argsPreview.isEmpty {
                    Text(AgentEventStyle.truncate(argsPreview, max: 50))
                        .font(DS.Text.captionMono)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
        }
    }

    @ViewBuilder
    private var durationLabel: some View {
        switch event.status {
        case .completed, .failed:
            Text(AgentEventStyle.formatDuration(event.duration))
                .font(DS.Text.captionMono)
                .foregroundStyle(DS.Surface.quaternary)
        case .inProgress:
            EmptyView()
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch event.status {
        case .completed:
            Image(systemName: "checkmark")
                .font(DS.Text.nano)
                .foregroundStyle(.green.opacity(0.9))
        case .failed:
            Image(systemName: "xmark.octagon.fill")
                .font(DS.Text.nano)
                .foregroundStyle(.red.opacity(0.9))
        case .inProgress:
            BrailleSpinner(size: 9, color: .white.opacity(0.5))
        }
    }

    @ViewBuilder
    private var detailBody: some View {
        HStack(alignment: .top, spacing: 8) {
            Rectangle()
                .fill(DS.Stroke.hairline)
                .frame(width: DS.Hairline.standard)
            VStack(alignment: .leading, spacing: 4) {
                if case .failed(let reason) = event.status, !reason.isEmpty {
                    Text(reason)
                        .font(DS.Text.micro)
                        .italic()
                        .foregroundStyle(.red.opacity(0.85))
                        .textSelection(.enabled)
                }
                if !event.detail.isEmpty {
                    let truncated = event.detail.count > 600
                        ? String(event.detail.prefix(600)) + "…"
                        : event.detail
                    Text(truncated)
                        .font(DS.Text.captionMono)
                        .foregroundStyle(DS.Surface.quaternary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.leading, 13)
        .padding(.top, 4)
        .padding(.bottom, 6)
    }
}

// MARK: - Verb / icon / format helpers (timeline-only)

private enum AgentEventStyle {
    /// Mapping from Hermes tool name → SF Symbol + present/past verbs.
    /// Fallback for unknown tool names is `wrench.and.screwdriver` /
    /// "Using" / "Used". `delegate_task` is included as a regular tool —
    /// no special UI for subagent activity (that distinction was the
    /// pre-refactor `subagentIndicator`, intentionally collapsed here).
    static func verbMapping(toolName: String) -> (icon: String, present: String, past: String) {
        switch toolName {
        case "terminal":      return ("terminal",               "Running",    "Ran")
        case "view":          return ("doc.text",               "Viewing",    "Viewed")
        case "str_replace":   return ("pencil",                 "Editing",    "Edited")
        case "create_file":   return ("doc.badge.plus",         "Creating",   "Created")
        case "web_search":    return ("magnifyingglass",        "Searching",  "Searched")
        case "web_fetch":     return ("globe",                  "Fetching",   "Fetched")
        case "delegate_task": return ("person.2",               "Delegating", "Delegated")
        default:              return ("wrench.and.screwdriver", "Using",      "Used")
        }
    }

    static func iconName(for event: AgentEvent) -> String {
        switch event.kind {
        case .thinking:                return "brain"
        case .tool(let name, _):       return verbMapping(toolName: name).icon
        }
    }

    static func truncate(_ s: String, max: Int) -> String {
        guard s.count > max else { return s }
        return String(s.prefix(max)) + "…"
    }

    /// Sub-second durations are rendered as `<1s` rather than `0s` so the
    /// fast tool calls don't read as "didn't run". Anything ≥1s rounds.
    static func formatDuration(_ d: TimeInterval) -> String {
        if d < 1.0 { return "<1s" }
        return "\(Int(d.rounded()))s"
    }
}

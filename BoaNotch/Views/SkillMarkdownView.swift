import SwiftUI

/// Block-aware markdown renderer for SKILL.md content (Brain · Tools · Section
/// 2 drill-down). The previous detail view used
/// `AttributedString(markdown: ..., interpretedSyntax: .inlineOnlyPreservingWhitespace)`
/// which leaves block-level markers (`##`, `- `, ` ``` `) as raw text — so
/// the user saw `## Setup` instead of "Setup" rendered as a heading.
///
/// SwiftUI's `Text(AttributedString)` only honors *inline* attributes even
/// when the string is parsed with `.full` syntax — paragraph-level styling
/// (heading sizes, list indents, code-block fonts) doesn't transfer. We split
/// the source into typed blocks and render each as its own `View` so each
/// gets its proper font / fill / structure. Inline markdown (bold, italic,
/// links, inline code) inside each block is still parsed via the standard
/// `AttributedString(markdown:)` path.
///
/// Supported blocks: heading (1-3), paragraph, bullet list, code block, blockquote.
/// Anything else falls through as a paragraph (graceful degradation).
struct SkillMarkdownView: View {
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                renderBlock(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var blocks: [Block] { Self.parseBlocks(content) }

    @ViewBuilder
    private func renderBlock(_ block: Block) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(inlineMarkdown(text))
                .font(headingFont(level: level))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, level == 1 ? 6 : 2)
                .textSelection(.enabled)

        case .paragraph(let text):
            Text(inlineMarkdown(text))
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

        case .bullet(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(items.indices, id: \.self) { i in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•")
                            .font(.system(size: 13))
                            .foregroundStyle(.tertiary)
                        Text(inlineMarkdown(items[i]))
                            .font(.system(size: 13))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                }
            }

        case .codeBlock(let code):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.quaternary.opacity(0.4))
            )

        case .quote(let text):
            HStack(alignment: .top, spacing: 8) {
                Rectangle()
                    .fill(AppColors.accent.opacity(0.5))
                    .frame(width: 2)
                Text(inlineMarkdown(text))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
    }

    private func headingFont(level: Int) -> Font {
        switch level {
        case 1: return .system(size: 17, weight: .semibold)
        case 2: return .system(size: 15, weight: .semibold)
        default: return .system(size: 13, weight: .semibold)
        }
    }

    /// Parses `**bold**`, `_italic_`, `[link](url)`, `` `code` `` etc. inside
    /// a block. `inlineOnlyPreservingWhitespace` keeps spaces but strips no
    /// block markers (we already removed those during block parsing).
    private func inlineMarkdown(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
    }

    // MARK: - Block model

    enum Block {
        case heading(level: Int, text: String)
        case paragraph(String)
        case bullet([String])
        case codeBlock(String)
        case quote(String)
    }

    /// Linear scan : headings (`#`/`##`/`###`), fenced code blocks (` ``` `),
    /// bullet lists (`- `, `* `), blockquotes (`> `). Everything else groups
    /// into paragraphs (consecutive non-empty non-special lines joined with
    /// a space, like CommonMark soft line breaks). Blank lines separate
    /// paragraphs.
    private static func parseBlocks(_ raw: String) -> [Block] {
        var result: [Block] = []
        let lines = raw.components(separatedBy: "\n")
        var i = 0
        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                i += 1
                continue
            }

            if trimmed.hasPrefix("### ") {
                result.append(.heading(level: 3, text: String(trimmed.dropFirst(4))))
                i += 1; continue
            }
            if trimmed.hasPrefix("## ") {
                result.append(.heading(level: 2, text: String(trimmed.dropFirst(3))))
                i += 1; continue
            }
            if trimmed.hasPrefix("# ") {
                result.append(.heading(level: 1, text: String(trimmed.dropFirst(2))))
                i += 1; continue
            }

            if trimmed.hasPrefix("```") {
                var code = ""
                i += 1
                while i < lines.count {
                    if lines[i].trimmingCharacters(in: .whitespaces) == "```" {
                        i += 1
                        break
                    }
                    if !code.isEmpty { code += "\n" }
                    code += lines[i]
                    i += 1
                }
                result.append(.codeBlock(code))
                continue
            }

            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                var items: [String] = []
                while i < lines.count {
                    let l = lines[i].trimmingCharacters(in: .whitespaces)
                    if l.hasPrefix("- ") {
                        items.append(String(l.dropFirst(2)))
                    } else if l.hasPrefix("* ") {
                        items.append(String(l.dropFirst(2)))
                    } else if l.isEmpty {
                        i += 1
                        continue
                    } else {
                        break
                    }
                    i += 1
                }
                result.append(.bullet(items))
                continue
            }

            if trimmed.hasPrefix("> ") {
                var quoteLines: [String] = [String(trimmed.dropFirst(2))]
                i += 1
                while i < lines.count {
                    let l = lines[i].trimmingCharacters(in: .whitespaces)
                    if l.hasPrefix("> ") {
                        quoteLines.append(String(l.dropFirst(2)))
                        i += 1
                    } else { break }
                }
                result.append(.quote(quoteLines.joined(separator: " ")))
                continue
            }

            // Paragraph : collect contiguous lines until empty / next block.
            var para = trimmed
            i += 1
            while i < lines.count {
                let l = lines[i].trimmingCharacters(in: .whitespaces)
                if l.isEmpty
                    || l.hasPrefix("#")
                    || l.hasPrefix("- ")
                    || l.hasPrefix("* ")
                    || l.hasPrefix("```")
                    || l.hasPrefix("> ") {
                    break
                }
                para += " " + l
                i += 1
            }
            result.append(.paragraph(para))
        }
        return result
    }
}

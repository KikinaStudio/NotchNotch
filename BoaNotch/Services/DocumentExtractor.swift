import Foundation
import PDFKit

struct DocumentExtractor {
    static let maxCharacters = 50_000

    static func extract(from url: URL) -> Attachment {
        let fileName = url.lastPathComponent
        let fileType = url.pathExtension.lowercased()

        let textContent: String

        switch fileType {
        case "txt", "md", "swift", "py", "js", "ts", "json", "csv", "yaml", "yml",
             "toml", "xml", "html", "css", "sh", "zsh", "bash", "rs", "go", "rb",
             "java", "kt", "c", "cpp", "h", "hpp", "m", "r", "sql", "log", "conf",
             "ini", "env", "gitignore", "dockerfile":
            textContent = readTextFile(url)

        case "pdf":
            textContent = readPDF(url)

        case "rtf", "rtfd":
            textContent = readRTF(url)

        default:
            textContent = "[Unsupported file type: \(fileType)]"
        }

        return Attachment(
            fileName: fileName,
            fileType: fileType,
            textContent: truncate(textContent),
            fileURL: url
        )
    }

    private static func readTextFile(_ url: URL) -> String {
        (try? String(contentsOf: url, encoding: .utf8)) ?? "[Could not read file]"
    }

    private static func readPDF(_ url: URL) -> String {
        guard let document = PDFDocument(url: url) else {
            return "[Could not read PDF]"
        }
        var text = ""
        for i in 0..<document.pageCount {
            if let page = document.page(at: i), let pageText = page.string {
                text += pageText + "\n"
            }
        }
        return text.isEmpty ? "[PDF contained no extractable text]" : text
    }

    private static func readRTF(_ url: URL) -> String {
        guard let attrString = try? NSAttributedString(
            url: url,
            options: [:],
            documentAttributes: nil
        ) else {
            return "[Could not read RTF]"
        }
        return attrString.string
    }

    private static func truncate(_ text: String) -> String {
        if text.count > maxCharacters {
            return String(text.prefix(maxCharacters)) + "\n[...truncated at \(maxCharacters) characters]"
        }
        return text
    }
}

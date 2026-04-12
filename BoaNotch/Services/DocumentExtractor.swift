import Foundation
import AppKit
import PDFKit

struct DocumentExtractor {
    static let maxCharacters = 50_000

    /// Hermes image cache directory — same location Telegram adapter uses
    static let hermesCacheDir: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let cacheDir = home.appendingPathComponent(".hermes/cache/images", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        return cacheDir
    }()

    static func extract(from url: URL) -> Attachment {
        let fileName = url.lastPathComponent
        let fileType = url.pathExtension.lowercased()

        let textContent: String

        switch fileType {
        // Images → copy to Hermes cache, reference by path so vision tool can see it
        case "png", "jpg", "jpeg", "gif", "webp", "heic", "tiff", "svg", "bmp":
            let cachedPath = copyToHermesCache(url, ext: fileType)
            if let cachedPath {
                textContent = "[Image attached at: \(cachedPath)]\nPlease analyze this image using your vision tool."
            } else {
                textContent = "[Failed to cache image for vision analysis]"
            }

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

    /// Save an NSImage from clipboard to Hermes cache, return an Attachment
    static func extractFromClipboardImage(_ image: NSImage) -> Attachment? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }

        let filename = "clipboard_\(UUID().uuidString.prefix(12).lowercased()).png"
        let dest = hermesCacheDir.appendingPathComponent(filename)

        do {
            try pngData.write(to: dest)
        } catch {
            return nil
        }

        let textContent = "[Image attached at: \(dest.path)]\nPlease analyze this image using your vision tool."

        return Attachment(
            fileName: filename,
            fileType: "png",
            textContent: textContent,
            fileURL: dest
        )
    }

    /// Copy image to ~/.hermes/cache/images/ so Hermes vision tool can access it
    private static func copyToHermesCache(_ url: URL, ext: String) -> String? {
        let filename = "img_\(UUID().uuidString.prefix(12).lowercased()).\(ext)"
        let dest = hermesCacheDir.appendingPathComponent(filename)
        do {
            try FileManager.default.copyItem(at: url, to: dest)
            return dest.path
        } catch {
            return nil
        }
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

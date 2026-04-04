import SwiftUI
import AppKit

// MARK: - Colors

enum AppColors {
    static let accent = Color(red: 0.75, green: 0.6, blue: 1.0)
    static let recordingDot = Color(red: 0.65, green: 0.3, blue: 1.0)
    static let recordingLabel = Color(red: 0.75, green: 0.5, blue: 1.0)
    static let kittViolet = Color(red: 0.55, green: 0.15, blue: 1.0)
    static let dropOverlay = Color(red: 0.45, green: 0.2, blue: 0.8)
}

// MARK: - File type icons

func sfIconForFileType(_ type: String) -> String {
    switch type {
    case "png", "jpg", "jpeg", "gif", "webp", "heic", "svg", "tiff", "bmp": return "photo"
    case "pdf": return "doc.richtext"
    case "txt", "md": return "doc.text"
    case "swift", "py", "js", "ts", "rs", "go", "c", "cpp", "h", "java", "rb": return "chevron.left.forwardslash.chevron.right"
    case "json", "yaml", "yml", "toml", "xml": return "curlybraces"
    case "csv": return "tablecells"
    case "mp3", "wav", "m4a", "aac", "ogg", "flac": return "waveform"
    case "mp4", "mov", "avi", "mkv": return "film"
    case "zip", "tar", "gz", "rar": return "archivebox"
    default: return "doc"
    }
}

// MARK: - Hover cursor modifier

struct PointingHandCursor: ViewModifier {
    func body(content: Content) -> some View {
        content.onHover { hovering in
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}

extension View {
    func pointingHandCursor() -> some View {
        modifier(PointingHandCursor())
    }
}

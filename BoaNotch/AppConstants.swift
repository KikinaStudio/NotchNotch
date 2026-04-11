import SwiftUI
import AppKit

// MARK: - Colors

enum AppColors {
    static let accent = Color(red: 0.75, green: 0.6, blue: 1.0)
    static let recordingDot = Color(red: 0.65, green: 0.3, blue: 1.0)
    static let recordingLabel = Color(red: 0.75, green: 0.5, blue: 1.0)
    static let kittViolet = Color(red: 0.55, green: 0.15, blue: 1.0)
    static let dropOverlay = Color(red: 0.45, green: 0.2, blue: 0.8)
    static let searchHighlight = Color(red: 0.75, green: 0.6, blue: 1.0).opacity(0.3)
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

// MARK: - Logo loading

func loadAppLogo() -> NSImage? {
    if let url = Bundle.module.url(forResource: "logo-white", withExtension: "png"),
       let img = NSImage(contentsOf: url) { return img }
    if let url = Bundle.main.resourceURL?.appendingPathComponent("logo-white.png"),
       let img = NSImage(contentsOf: url) { return img }
    if let execURL = Bundle.main.executableURL?.deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("Resources/logo-white.png"),
       let img = NSImage(contentsOf: execURL) { return img }
    return nil
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

import SwiftUI

struct ToastView: View {
    let message: String
    var notchWidth: CGFloat = 185

    var body: some View {
        Text(cleanForToast(message))
            .font(.system(size: 12))
            .foregroundStyle(.white.opacity(0.85))
            .lineLimit(2)
            .truncationMode(.tail)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(width: notchWidth)
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    /// Strip markdown syntax for clean toast display
    private func cleanForToast(_ text: String) -> String {
        var s = text
        // Remove code blocks
        while let start = s.range(of: "```") {
            if let end = s.range(of: "```", range: start.upperBound..<s.endIndex) {
                s.removeSubrange(start.lowerBound..<end.upperBound)
            } else {
                s.removeSubrange(start)
            }
        }
        // Remove bold/italic markers
        s = s.replacingOccurrences(of: "**", with: "")
        s = s.replacingOccurrences(of: "__", with: "")
        // Remove inline code
        s = s.replacingOccurrences(of: "`", with: "")
        // Remove heading markers
        s = s.replacingOccurrences(of: "### ", with: "")
        s = s.replacingOccurrences(of: "## ", with: "")
        s = s.replacingOccurrences(of: "# ", with: "")
        // Remove bullet markers
        s = s.replacingOccurrences(of: "- ", with: "")
        // Collapse whitespace
        while s.contains("  ") { s = s.replacingOccurrences(of: "  ", with: " ") }
        while s.contains("\n\n\n") { s = s.replacingOccurrences(of: "\n\n\n", with: "\n\n") }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

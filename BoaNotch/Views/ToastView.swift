import SwiftUI

struct ToastView: View {
    let message: String
    var notchWidth: CGFloat = 185
    var isClipperToast: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            if isClipperToast {
                PacmanView()
                    .frame(width: 18, height: 18)
            }
            Text(cleanForToast(message))
                .font(.callout)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .truncationMode(.tail)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: isClipperToast ? max(notchWidth, 280) : notchWidth)
        .nnGlass(in: RoundedRectangle(cornerRadius: 12))
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

// MARK: - Animated pacman (chomping circle)

struct PacmanView: View {
    @State private var chomping = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.05)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let cycle = t.truncatingRemainder(dividingBy: 0.4) / 0.4
            let mouthAngle = abs(cycle * 2 - 1) * 40  // 0→40→0 degrees

            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let radius = min(size.width, size.height) / 2

                var path = Path()
                let startAngle = Angle.degrees(mouthAngle)
                let endAngle = Angle.degrees(360 - mouthAngle)
                path.move(to: center)
                path.addArc(center: center, radius: radius,
                           startAngle: startAngle, endAngle: endAngle, clockwise: false)
                path.closeSubpath()

                context.fill(path, with: .color(AppColors.accent))
            }
        }
    }
}

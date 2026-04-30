import SwiftUI

/// Type sémantique d'un toast. Détermine icône + durée d'affichage.
/// Le mapping pointe vers les SVG pixelarticons bundlés
/// (`BoaNotch/Resources/PixelIcons/`). Si une icône est absente du
/// bundle, le fallback SF Symbol s'affiche.
enum ToastKind: Equatable {
    /// Toast générique (showToast par défaut).
    case info
    /// Confirmation (sauvegarde clipper, brain dump OK, etc.).
    case success
    /// Échec (transcription échouée, endpoint injoignable).
    case error
    /// Résultat d'une routine cron, tappable pour expansion en chat.
    case cron

    /// Nom canonique du SVG dans `Contents/Resources/`.
    var iconName: String {
        switch self {
        case .info:    return "notification"
        case .success: return "pacman"
        case .error:   return "alert"
        case .cron:    return "clock"
        }
    }

    /// SF Symbol utilisé si le SVG bundlé est absent.
    var fallbackSF: String {
        switch self {
        case .info:    return "bell.fill"
        case .success: return "checkmark.circle.fill"
        case .error:   return "exclamationmark.triangle.fill"
        case .cron:    return "clock.fill"
        }
    }

    /// Durée d'affichage par défaut, en secondes.
    var displayDuration: TimeInterval {
        switch self {
        case .info, .success, .error: return 3
        case .cron:                   return 5
        }
    }
}

struct ToastView: View {
    let message: String
    var notchWidth: CGFloat = 185
    var kind: ToastKind = .info

    var body: some View {
        HStack(spacing: 8) {
            PixelIcon.image(kind.iconName, fallback: kind.fallbackSF)
                .resizable()
                .renderingMode(.template)
                .interpolation(.none)
                .frame(width: 18, height: 18)
                .foregroundStyle(AppColors.accent)

            Text(cleanForToast(message))
                .font(.callout)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .truncationMode(.tail)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Asymmetric vertical padding: pixelarticons glyphs sit slightly low
        // in their 24×24 viewBox, and `.callout` text has cap-height empty
        // space at the top of its line box — both make a numerically
        // symmetric 12/12 padding read as top-heavy. 9pt on top compensates
        // visually so the icon + text appear vertically centered.
        .padding(EdgeInsets(top: 9, leading: 14, bottom: 12, trailing: 14))
        .frame(width: kind == .cron ? max(notchWidth, 280) : notchWidth)
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

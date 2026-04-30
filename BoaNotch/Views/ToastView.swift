import SwiftUI

/// Type sémantique d'un toast. Détermine icône, teinte et durée
/// d'affichage. Le mapping pointe vers les SVG pixelarticons bundlés
/// (`BoaNotch/Resources/PixelIcons/`). Si une icône est absente du
/// bundle, le fallback SF Symbol s'affiche.
enum ToastKind: Equatable {
    /// Avis système générique (showToast par défaut). Inclut les
    /// notifications de service NotchNotch (compression endpoint, etc.).
    case info
    /// Réponse rapide de l'agent quand la notch est fermée — la catégorie
    /// quotidienne, distincte des alertes système.
    case chat
    /// Confirmation (sauvegarde clipper, brain dump, mémoire édifiée).
    case success
    /// Échec (transcription échouée, endpoint injoignable).
    case error
    /// Résultat d'une routine cron, tappable pour expansion en chat.
    case cron

    /// Nom canonique du SVG dans `Contents/Resources/`.
    var iconName: String {
        switch self {
        case .info:    return "notification"
        case .chat:    return "chat"
        case .success: return "pacman"
        case .error:   return "alert"
        case .cron:    return "clock"
        }
    }

    /// SF Symbol utilisé si le SVG bundlé est absent.
    var fallbackSF: String {
        switch self {
        case .info:    return "bell.fill"
        case .chat:    return "bubble.left.fill"
        case .success: return "checkmark.circle.fill"
        case .error:   return "exclamationmark.triangle.fill"
        case .cron:    return "clock.fill"
        }
    }

    /// Teinte de l'icône. Sémantique par catégorie : la couleur porte le
    /// sens autant que la forme du glyph. Calibrée pour rester lisible
    /// sur le panel noir de la notch sans saturer.
    var tint: Color {
        switch self {
        case .info:    return Color(red: 0.78, green: 0.72, blue: 1.00)  // soft lavender — system notice
        case .chat:    return AppColors.accent                          // NotchNotch blue — agent voice
        case .success: return Color(red: 0.50, green: 0.85, blue: 0.55) // green — confirmation
        case .error:   return Color(red: 0.95, green: 0.45, blue: 0.45) // coral red — failure
        case .cron:    return Color(red: 0.97, green: 0.70, blue: 0.30) // amber — scheduled event
        }
    }

    /// Durée d'affichage par défaut, en secondes.
    var displayDuration: TimeInterval {
        switch self {
        case .info, .chat, .success, .error: return 3
        case .cron:                           return 5
        }
    }
}

struct ToastView: View {
    let message: String
    var notchWidth: CGFloat = 185
    var kind: ToastKind = .info

    var body: some View {
        HStack(spacing: 12) {
            PixelIcon.image(kind.iconName, fallback: kind.fallbackSF)
                .resizable()
                .renderingMode(.template)
                .interpolation(.none)
                .frame(width: 18, height: 18)
                .foregroundStyle(kind.tint)

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

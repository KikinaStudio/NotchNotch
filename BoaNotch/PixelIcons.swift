import SwiftUI
import AppKit

/// Loader unifié pour les icônes pixelarticons bundlées dans
/// `BoaNotch/Resources/PixelIcons/`. Les SVGs sont copiés à plat dans
/// `Contents/Resources/` par `scripts/run.sh` et `scripts/release.sh`,
/// donc `Bundle.main.url(forResource:withExtension:)` les trouve sans
/// préfixe de sous-dossier.
///
/// Pour ajouter une nouvelle icône au projet :
/// 1. Browser le catalogue (800 icônes free) sur https://pixelarticons.com.
/// 2. Trouver le nom kebab-case du repo halfmage (ex: `square-alert`).
/// 3. Télécharger en lui donnant le nom canonique souhaité côté code :
///    ```
///    curl -fSL https://raw.githubusercontent.com/halfmage/pixelarticons/master/svg/<halfmage-name>.svg \
///      -o BoaNotch/Resources/PixelIcons/<canonical-name>.svg
///    ```
/// 4. L'utiliser via `PixelIcon.image("<canonical-name>")`.
///
/// Licence MIT (pas d'attribution requise dans l'app).
/// Repo : https://github.com/halfmage/pixelarticons
enum PixelIcon {
    /// Charge un SVG pixelarticons bundlé en tant qu'`Image` teintable.
    /// - Parameters:
    ///   - name: nom kebab-case sans extension (ex: `"pacman"`, `"alert"`).
    ///   - fallback: nom SF Symbol utilisé si le SVG est absent du bundle.
    static func image(_ name: String, fallback: String = "questionmark") -> Image {
        guard let url = Bundle.main.url(forResource: name, withExtension: "svg"),
              let nsImage = NSImage(contentsOf: url) else {
            return Image(systemName: fallback)
        }
        nsImage.isTemplate = true
        return Image(nsImage: nsImage).renderingMode(.template)
    }
}

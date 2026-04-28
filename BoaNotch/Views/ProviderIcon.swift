import SwiftUI
import AppKit

/// Maps a NotchNotch LLM provider id to a lobehub icon slug or an SF Symbol fallback.
/// SVG files live flat at BoaNotch/Resources/provider_<slug>.svg — same pattern as
/// the existing call_bell.svg Phosphor icons. Refresh via
/// `bash scripts/fetch-provider-icons.sh --force`.
enum ProviderIconCatalog {
    /// Returns the SVG slug if a bundled lobehub icon exists for this provider.
    static func slug(for providerID: String) -> String? {
        switch providerID {
        case "openai": return "openai"
        case "anthropic": return "claude"
        case "gemini": return "gemini"
        case "minimax": return "minimax"
        case "openrouter": return "openrouter"
        case "huggingface": return "huggingface"
        case "zai": return "zai"
        case "kimi-coding": return "kimi"
        case "nous": return "nousresearch"
        default: return nil
        }
    }

    /// SF Symbol fallback for providers without a lobehub icon.
    static func sfSymbol(for providerID: String) -> String {
        switch providerID {
        case "xiaomi": return "cpu"
        case "custom": return "globe"
        default: return "questionmark.circle"
        }
    }
}

/// Renders the provider's brand icon at the requested point size.
/// Tints to the inherited foregroundStyle via NSImage.isTemplate (same pattern
/// as NotchView.callBellImage).
struct ProviderIcon: View {
    let providerID: String
    var size: CGFloat = 13

    var body: some View {
        if let slug = ProviderIconCatalog.slug(for: providerID),
           let image = Self.cachedImage(for: slug) {
            image
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .frame(width: size, height: size)
        } else {
            Image(systemName: ProviderIconCatalog.sfSymbol(for: providerID))
                .font(.system(size: size, weight: .medium))
        }
    }

    // MARK: - Cache (load each SVG once at first use)
    private static var cache: [String: Image] = [:]

    private static func cachedImage(for slug: String) -> Image? {
        if let hit = cache[slug] { return hit }
        guard let url = Bundle.main.url(forResource: "provider_\(slug)", withExtension: "svg"),
              let nsImage = NSImage(contentsOf: url) else {
            return nil
        }
        nsImage.isTemplate = true
        let image = Image(nsImage: nsImage)
        cache[slug] = image
        return image
    }
}

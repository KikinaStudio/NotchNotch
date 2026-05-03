import SwiftUI
import AppKit

/// Renders a `CuratedSkill.IconKind` at the requested point size.
///
/// `.brand` loads the Simple Icons monochrome SVG (single path, viewBox 24x24)
/// from `Bundle.main`, marks `isTemplate = true` so `.foregroundStyle` tints
/// it, and applies the official brand color. Brands too dark to register on
/// NotchNotch's near-black panel (Notion's `#000000`, etc.) are substituted
/// with `.primary`.
///
/// `.sfSymbol` is rendered via `Image(systemName:)` and tinted with the
/// inherited foreground style.
///
/// Cache is per-process — each SVG is read once on first use.
struct BrandIconView: View {
    let kind: IconKind
    var size: CGFloat = 24
    /// When true, the icon is rendered in a uniform near-grey
    /// (`Color.primary.opacity(0.35)`) instead of its brand color.
    /// Used by the Section 1 "Apps" row when an App is `.available`
    /// (not yet connected) — gives a clear monochrome cue without
    /// dropping the icon shape.
    var desaturated: Bool = false

    var body: some View {
        switch kind {
        case .brand(let slug, let hex):
            if let image = Self.cachedImage(for: slug) {
                image
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .frame(width: size, height: size)
                    .foregroundStyle(desaturated
                                     ? AnyShapeStyle(Color.primary.opacity(0.35))
                                     : AnyShapeStyle(Self.color(for: hex)))
            } else {
                Image(systemName: "puzzlepiece.fill")
                    .font(.system(size: size * 0.7, weight: .medium))
                    .foregroundStyle(desaturated
                                     ? AnyShapeStyle(Color.primary.opacity(0.35))
                                     : AnyShapeStyle(.tertiary))
                    .frame(width: size, height: size)
            }
        case .sfSymbol(let name):
            Image(systemName: name)
                .font(.system(size: size * 0.85, weight: .medium))
                .frame(width: size, height: size)
                .foregroundStyle(desaturated
                                 ? AnyShapeStyle(Color.primary.opacity(0.35))
                                 : AnyShapeStyle(.primary))
        }
    }

    // MARK: - Color resolution

    /// Hex string → `Color`, with a luminance gate that swaps too-dark brands
    /// for `.primary` so they remain visible on the panel's near-black bg.
    private static func color(for hex: String) -> Color {
        guard let rgb = parseHex(hex) else { return .primary }
        let luminance = 0.299 * rgb.r + 0.587 * rgb.g + 0.114 * rgb.b
        if luminance < 0.18 { return .primary }
        return Color(red: rgb.r, green: rgb.g, blue: rgb.b)
    }

    private static func parseHex(_ hex: String) -> (r: Double, g: Double, b: Double)? {
        var s = hex.uppercased()
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let value = UInt32(s, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        return (r, g, b)
    }

    // MARK: - SVG cache

    private static var cache: [String: Image] = [:]

    private static func cachedImage(for slug: String) -> Image? {
        if let hit = cache[slug] { return hit }
        guard let url = Bundle.main.url(forResource: slug, withExtension: "svg"),
              let nsImage = NSImage(contentsOf: url) else {
            return nil
        }
        nsImage.isTemplate = true
        let image = Image(nsImage: nsImage)
        cache[slug] = image
        return image
    }
}

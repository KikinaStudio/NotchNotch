import Foundation
import CoreGraphics

final class AppearanceSettings: ObservableObject {
    enum TextSize: String, CaseIterable {
        case small, medium, large

        var scale: CGFloat {
            switch self {
            case .small:  return 0.85
            case .medium: return 1.0
            case .large:  return 1.25
            }
        }
    }

    private static let key = "textSize"

    @Published var textSize: TextSize {
        didSet { UserDefaults.standard.set(textSize.rawValue, forKey: Self.key) }
    }

    init() {
        let raw = UserDefaults.standard.string(forKey: Self.key) ?? ""
        textSize = TextSize(rawValue: raw) ?? .medium
    }
}

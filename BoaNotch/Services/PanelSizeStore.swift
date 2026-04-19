import Foundation
import Combine

enum PanelSize: String {
    case standard
    case large
}

final class PanelSizeStore: ObservableObject {
    private static let defaultsKey = "panelSize"

    @Published var size: PanelSize {
        didSet {
            UserDefaults.standard.set(size.rawValue, forKey: Self.defaultsKey)
        }
    }

    init() {
        let raw = UserDefaults.standard.string(forKey: Self.defaultsKey) ?? PanelSize.standard.rawValue
        self.size = PanelSize(rawValue: raw) ?? .standard
    }
}

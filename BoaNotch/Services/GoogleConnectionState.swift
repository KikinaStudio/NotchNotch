import Foundation
import SwiftUI

@MainActor
final class GoogleConnectionState: ObservableObject {
    @Published var isConnected: Bool = false
    @Published var connectedEmail: String?
    @Published var isConnecting: Bool = false
    @Published var errorMessage: String?

    init() {
        refresh()
    }

    func refresh() {
        let tokenExists = GoogleOAuthService.tokenFileExists()
        let email = UserDefaults.standard.string(forKey: "googleConnectedEmail")
        self.isConnected = tokenExists && email != nil
        self.connectedEmail = tokenExists ? email : nil
    }

    func connect() async {
        errorMessage = nil
        isConnecting = true
        defer { isConnecting = false }
        do {
            let email = try await GoogleOAuthService.shared.connect()
            self.connectedEmail = email
            self.isConnected = true
        } catch GoogleOAuthService.GoogleOAuthError.userCancelled {
            // Silent — user backed out, no need to surface an error banner.
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    func disconnect() {
        GoogleOAuthService.shared.disconnect()
        self.connectedEmail = nil
        self.isConnected = false
        self.errorMessage = nil
    }

    func dismissError() {
        self.errorMessage = nil
    }
}

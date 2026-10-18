import SwiftUI

@main
struct BoaNotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Placeholder scene: SwiftUI needs one, the UI lives in the notch panel.
        // A never-inserted MenuBarExtra owns no window, unlike `Settings { EmptyView() }`,
        // whose empty "notchnotch Settings" window kept popping up.
        MenuBarExtra("notchnotch", isInserted: .constant(false)) {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Réglages…") {
                    appDelegate.notchVM.open()
                    appDelegate.notchVM.openSettings()
                }
                .keyboardShortcut(",")
            }
        }
    }
}

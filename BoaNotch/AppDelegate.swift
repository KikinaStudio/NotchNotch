import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    var panelController: NotchWindowController?
    let chatVM = ChatViewModel()
    let notchVM = NotchViewModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        panelController = NotchWindowController(chatVM: chatVM, notchVM: notchVM)
        panelController?.showPanel()
    }
}

import AppKit
import SwiftUI

/// Hosts `SettingsView` in a plain AppKit window we open on demand.
///
/// `SettingsLink` / the SwiftUI `Settings` scene are unreliable from a menu-bar
/// (`LSUIElement`) app — the window opens behind everything or not at all, and the
/// legacy `showSettingsWindow:` selector is a no-op on macOS 14+. Managing the window
/// ourselves opens it reliably, brings it to the front, and never auto-opens at launch.
@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func show(state: AppState) {
        if window == nil {
            let hosting = NSHostingController(
                rootView: SettingsView().environmentObject(state).frame(width: 460)
            )
            let window = NSWindow(contentViewController: hosting)
            window.title = "Spool Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

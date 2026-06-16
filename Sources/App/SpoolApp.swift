import SwiftUI

/// Spool — a menu-bar screen recorder that stores recordings in Frame.io.
@main
struct SpoolApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView()
                .environmentObject(state)
                .frame(width: 320)
        } label: {
            // While recording, show a red dot plus the elapsed timer; idle shows a camera.
            Label(state.isRecording ? state.recordingElapsedString : "",
                  systemImage: state.isRecording ? "record.circle.fill" : "video.circle")
        }
        .menuBarExtraStyle(.window)
        // Settings is shown via SettingsWindowController (an AppKit window) from the
        // menu — the SwiftUI Settings scene is unreliable for a menu-bar app.
    }
}

import SwiftUI

/// The popover shown from the menu-bar icon: record/stop controls, capture toggles,
/// Frame.io connection state, and upload status.
struct MenuContentView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            Divider()

            if state.isRecording {
                RecordingActiveView()
            } else {
                RecordingControlsView()
            }

            Divider()

            UploadStatusView()

            Divider()

            footer
        }
        .padding(14)
        .task {
            state.refreshMicrophones()
            state.refreshCameras()
            await state.refreshSources()
        }
    }

    private var header: some View {
        HStack {
            Image(systemName: "video.circle.fill")
                .foregroundStyle(.tint)
            Text("Spool")
                .font(.headline)
            Spacer()
            connectionBadge
        }
    }

    private var connectionBadge: some View {
        Group {
            if state.isSignedIn {
                Label("Frame.io", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
            } else {
                Label("Not connected", systemImage: "person.crop.circle.badge.xmark")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
    }

    private var footer: some View {
        HStack {
            SettingsLink {
                Label("Settings", systemImage: "gearshape")
            }
            Spacer()
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power")
            }
        }
        .buttonStyle(.borderless)
        .font(.callout)
    }
}

import SwiftUI

/// Renders the post-recording phase: upload progress, the shareable Frame.io link,
/// or an error message.
struct UploadStatusView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        switch state.phase {
        case .uploading(let fraction):
            VStack(alignment: .leading, spacing: 6) {
                Text("Uploading to Frame.io…").font(.callout)
                ProgressView(value: fraction)
                Text("\(Int(fraction * 100))%")
                    .font(.caption).foregroundStyle(.secondary)
            }

        case .finished(let link):
            VStack(alignment: .leading, spacing: 6) {
                Label("Recording saved", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                if let link = link, let url = URL(string: link) {
                    Link(destination: url) {
                        Label("Open in Frame.io", systemImage: "arrow.up.right.square")
                    }
                    Button {
                        copyToPasteboard(link)
                    } label: {
                        Label("Copy share link", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                } else {
                    Text("Saved to ~/Movies/Spool")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)

        default:
            EmptyView()
        }
    }

    private func copyToPasteboard(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}

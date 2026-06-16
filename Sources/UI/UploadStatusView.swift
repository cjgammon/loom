import SwiftUI

/// Renders the post-recording phase: upload progress, the shareable Frame.io link,
/// or an error message.
struct UploadStatusView: View {
    @EnvironmentObject private var state: AppState
    @State private var didCopy = false

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
            VStack(alignment: .leading, spacing: 8) {
                Label("Upload complete", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)

                if let link = link, let url = URL(string: link) {
                    // Show the share link and a prominent copy button.
                    Text(link)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)

                    HStack(spacing: 8) {
                        Button {
                            copyToPasteboard(link)
                        } label: {
                            Label(didCopy ? "Copied!" : "Copy to clipboard",
                                  systemImage: didCopy ? "checkmark" : "doc.on.doc")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)

                        Link(destination: url) {
                            Image(systemName: "arrow.up.right.square")
                        }
                        .help("Open in browser")
                    }
                } else {
                    // No link: either upload was off/not signed in (deliberate local
                    // save) or the upload happened but the share link couldn't be made.
                    let uploaded = state.uploadToFrameIO && state.isSignedIn
                    Text(uploaded
                         ? "Saved to ~/Movies/Spool. A share link couldn’t be created — check that your Frame.io plan allows public shares."
                         : "Saved to ~/Movies/Spool.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let fileURL = state.lastSavedFileURL {
                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([fileURL])
                        } label: {
                            Label("Reveal in Finder", systemImage: "folder")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            .onChange(of: link) { _, _ in didCopy = false }

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
        didCopy = true
    }
}

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
                    Text("Saved to ~/Movies/Spool. A share link couldn’t be created — check that your Frame.io plan allows public shares.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
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

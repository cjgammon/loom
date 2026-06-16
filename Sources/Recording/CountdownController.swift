import AppKit

/// Shows a brief full-screen "3… 2… 1…" countdown before capture starts, so the
/// numbers are never part of the recording. Uses a borderless, click-through window
/// centered on the main screen.
@MainActor
final class CountdownController {
    private var window: NSWindow?
    private weak var label: NSTextField?

    /// Display a countdown from `seconds` to 1, ~1s per number. No-op if `seconds <= 0`.
    func run(seconds: Int) async {
        guard seconds > 0 else { return }
        for remaining in stride(from: seconds, through: 1, by: -1) {
            show(remaining)
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        dismiss()
    }

    private func show(_ number: Int) {
        if window == nil { build() }
        label?.stringValue = "\(number)"
        window?.orderFrontRegardless()
    }

    private func build() {
        let side: CGFloat = 220
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: side, height: side),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        win.isOpaque = false
        win.backgroundColor = .clear
        win.level = .screenSaver
        win.ignoresMouseEvents = true
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let container = NSView(frame: NSRect(x: 0, y: 0, width: side, height: side))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
        container.layer?.cornerRadius = 28

        let text = NSTextField(labelWithString: "")
        text.alignment = .center
        text.font = .systemFont(ofSize: 130, weight: .bold)
        text.textColor = .white
        text.frame = NSRect(x: 0, y: (side - 160) / 2, width: side, height: 160)
        container.addSubview(text)
        win.contentView = container
        self.label = text

        if let screen = NSScreen.main {
            let f = screen.frame
            win.setFrameOrigin(NSPoint(x: f.midX - side / 2, y: f.midY - side / 2))
        }
        window = win
    }

    private func dismiss() {
        window?.orderOut(nil)
        window = nil
        label = nil
    }
}

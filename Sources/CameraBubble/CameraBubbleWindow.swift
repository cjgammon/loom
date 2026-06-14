import AppKit
import AVFoundation

/// A borderless, circular, always-on-top window that shows the live webcam feed.
///
/// It floats above all other apps and is draggable anywhere on screen. Because it is
/// an ordinary on-screen window, ScreenCaptureKit captures it in-frame, producing the
/// Loom-style camera "bubble" without any video compositing.
final class CameraBubbleWindow: NSWindow {
    private let previewLayer: AVCaptureVideoPreviewLayer
    private let diameter: CGFloat

    init(session: AVCaptureSession, diameter: CGFloat = 180) {
        self.diameter = diameter
        self.previewLayer = AVCaptureVideoPreviewLayer(session: session)

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: diameter, height: diameter),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        isMovableByWindowBackground = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // Keep the bubble visible while interacting with other apps.
        ignoresMouseEvents = false

        let container = BubbleView(frame: NSRect(x: 0, y: 0, width: diameter, height: diameter))
        container.wantsLayer = true
        previewLayer.frame = container.bounds
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.cornerRadius = diameter / 2
        previewLayer.masksToBounds = true
        container.layer?.addSublayer(previewLayer)
        contentView = container

        positionInBottomRight()
    }

    /// Place the bubble near the bottom-right of the main screen with a margin.
    private func positionInBottomRight(margin: CGFloat = 40) {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let origin = NSPoint(
            x: visible.maxX - diameter - margin,
            y: visible.minY + margin
        )
        setFrameOrigin(origin)
    }

    override var canBecomeKey: Bool { true }
}

/// Content view that draws a subtle ring border around the circular preview.
private final class BubbleView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let inset = bounds.insetBy(dx: 1.5, dy: 1.5)
        let ring = NSBezierPath(ovalIn: inset)
        ring.lineWidth = 3
        NSColor.white.withAlphaComponent(0.9).setStroke()
        ring.stroke()
    }

    // Round hit-testing so clicks outside the circle pass through.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let center = NSPoint(x: bounds.midX, y: bounds.midY)
        let dx = point.x - center.x
        let dy = point.y - center.y
        let radius = bounds.width / 2
        return (dx * dx + dy * dy) <= radius * radius ? super.hitTest(point) : nil
    }
}

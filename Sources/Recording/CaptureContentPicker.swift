import Foundation
import ScreenCaptureKit

/// Enumerates the displays (and, optionally, windows) available to record via
/// ScreenCaptureKit, and builds the `SCContentFilter` used to start a stream.
struct CaptureContentPicker {
    enum Source: Identifiable, Hashable {
        case display(SCDisplay)
        case window(SCWindow)

        var id: String {
            switch self {
            case .display(let d): return "display-\(d.displayID)"
            case .window(let w): return "window-\(w.windowID)"
            }
        }

        var title: String {
            switch self {
            case .display(let d):
                return "Display \(d.displayID) (\(d.width)×\(d.height))"
            case .window(let w):
                let app = w.owningApplication?.applicationName ?? "Unknown"
                let name = w.title ?? "Untitled"
                return "\(app) — \(name)"
            }
        }
    }

    /// Fetch shareable content. Throws if Screen Recording permission is not granted.
    static func availableSources(includeWindows: Bool = false) async throws -> [Source] {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )
        var sources: [Source] = content.displays.map { .display($0) }
        if includeWindows {
            // Skip tiny/util windows and our own app to keep the list usable.
            let windows = content.windows
                .filter { ($0.title?.isEmpty == false) && $0.frame.width > 120 && $0.frame.height > 120 }
                .filter { $0.owningApplication?.bundleIdentifier != Bundle.main.bundleIdentifier }
            sources += windows.map { .window($0) }
        }
        return sources
    }

    /// Build the content filter for a chosen source. The Spool app's own windows
    /// (notably the menu UI) are excluded; the camera bubble is intentionally NOT
    /// excluded so it is captured in-frame.
    static func filter(for source: Source) -> SCContentFilter {
        switch source {
        case .display(let display):
            return SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        case .window(let window):
            return SCContentFilter(desktopIndependentWindow: window)
        }
    }

    static func dimensions(for source: Source) -> (width: Int, height: Int) {
        switch source {
        case .display(let d): return (d.width, d.height)
        case .window(let w): return (Int(w.frame.width), Int(w.frame.height))
        }
    }
}

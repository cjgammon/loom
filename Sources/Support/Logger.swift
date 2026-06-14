import Foundation
import OSLog

/// Lightweight wrapper around `os.Logger` with per-subsystem categories so the
/// recording pipeline, Frame.io networking, and UI can be filtered independently
/// in Console.app / `log stream`.
enum Log {
    private static let subsystem = "com.cjgammon.Spool"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let recording = Logger(subsystem: subsystem, category: "recording")
    static let camera = Logger(subsystem: subsystem, category: "camera")
    static let frameio = Logger(subsystem: subsystem, category: "frameio")
    static let auth = Logger(subsystem: subsystem, category: "auth")
}

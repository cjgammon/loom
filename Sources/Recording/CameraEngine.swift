import Foundation
import AVFoundation

/// Runs an `AVCaptureSession` for the webcam and exposes it so the camera-bubble
/// window can attach an `AVCaptureVideoPreviewLayer`.
///
/// In this MVP the camera is NOT muxed into the file directly — the bubble window
/// floats on screen and is captured in-frame by ScreenCaptureKit, which yields the
/// classic Loom look without custom compositing.
final class CameraEngine {
    enum CameraError: LocalizedError {
        case noCamera
        case cannotAddInput

        var errorDescription: String? {
            switch self {
            case .noCamera: return "No camera was found."
            case .cannotAddInput: return "The selected camera could not be used."
            }
        }
    }

    let session = AVCaptureSession()
    private let configQueue = DispatchQueue(label: "com.cjgammon.Spool.camera.config")

    /// All connected cameras (built-in + external/Continuity).
    static func availableCameras() -> [AVCaptureDevice] {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
            mediaType: .video,
            position: .unspecified
        )
        return discovery.devices
    }

    /// Configure with a specific camera (or the system default when `nil`).
    func configure(device: AVCaptureDevice? = nil) throws {
        let camera = device ?? AVCaptureDevice.default(for: .video)
        guard let camera = camera else { throw CameraError.noCamera }

        try configQueue.sync {
            session.beginConfiguration()
            defer { session.commitConfiguration() }

            session.sessionPreset = .high
            // Replace any existing inputs.
            for input in session.inputs { session.removeInput(input) }

            let input = try AVCaptureDeviceInput(device: camera)
            guard session.canAddInput(input) else { throw CameraError.cannotAddInput }
            session.addInput(input)
        }
    }

    func start() {
        configQueue.async { [session] in
            if !session.isRunning { session.startRunning() }
        }
    }

    func stop() {
        configQueue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }
}

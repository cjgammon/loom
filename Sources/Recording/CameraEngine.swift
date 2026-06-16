import Foundation
import AVFoundation

/// Runs an `AVCaptureSession` for the webcam and exposes it so the camera-bubble
/// window can attach an `AVCaptureVideoPreviewLayer`.
///
/// In this MVP the camera is NOT muxed into the file directly — the bubble window
/// floats on screen and is captured in-frame by ScreenCaptureKit, which yields the
/// classic Loom look without custom compositing.
///
/// A lightweight `AVCaptureVideoDataOutput` is attached solely to detect the first
/// delivered frame, so callers can defer showing the bubble until the feed is live
/// (no empty circle).
final class CameraEngine: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
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

    /// Called once, on the main queue, when the first camera frame is delivered.
    var onReady: (() -> Void)?

    private let videoOutput = AVCaptureVideoDataOutput()
    private let configQueue = DispatchQueue(label: "com.cjgammon.Spool.camera.config")
    private let sampleQueue = DispatchQueue(label: "com.cjgammon.Spool.camera.samples")
    private var didSignalReady = false

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
            // Replace any existing inputs/outputs.
            for input in session.inputs { session.removeInput(input) }
            for output in session.outputs { session.removeOutput(output) }

            let input = try AVCaptureDeviceInput(device: camera)
            guard session.canAddInput(input) else { throw CameraError.cannotAddInput }
            session.addInput(input)

            // First-frame detector.
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.setSampleBufferDelegate(self, queue: sampleQueue)
            if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }
        }
        sampleQueue.sync { didSignalReady = false }
    }

    func start() {
        configQueue.async { [session] in
            if !session.isRunning { session.startRunning() }
        }
    }

    func stop() {
        onReady = nil
        configQueue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard !didSignalReady else { return }
        didSignalReady = true
        let callback = onReady
        DispatchQueue.main.async { callback?() }
    }
}

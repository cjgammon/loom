import Foundation
import AVFoundation
import CoreMedia

/// Captures microphone audio via an `AVCaptureSession` and forwards the sample
/// buffers to `onAudioSample` for muxing into the recording's mic track.
final class MicrophoneEngine: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    enum MicError: LocalizedError {
        case noMicrophone
        case cannotConfigure

        var errorDescription: String? {
            switch self {
            case .noMicrophone: return "No microphone was found."
            case .cannotConfigure: return "The microphone could not be configured."
            }
        }
    }

    var onAudioSample: ((CMSampleBuffer) -> Void)?

    private let session = AVCaptureSession()
    private let output = AVCaptureAudioDataOutput()
    private let sampleQueue = DispatchQueue(label: "com.cjgammon.Spool.mic.samples")
    private let configQueue = DispatchQueue(label: "com.cjgammon.Spool.mic.config")

    static func availableMicrophones() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone],
            mediaType: .audio,
            position: .unspecified
        ).devices
    }

    func configure(device: AVCaptureDevice? = nil) throws {
        let mic = device ?? AVCaptureDevice.default(for: .audio)
        guard let mic = mic else { throw MicError.noMicrophone }

        try configQueue.sync {
            session.beginConfiguration()
            defer { session.commitConfiguration() }

            for input in session.inputs { session.removeInput(input) }
            for existing in session.outputs { session.removeOutput(existing) }

            let input = try AVCaptureDeviceInput(device: mic)
            guard session.canAddInput(input) else { throw MicError.cannotConfigure }
            session.addInput(input)

            output.setSampleBufferDelegate(self, queue: sampleQueue)
            guard session.canAddOutput(output) else { throw MicError.cannotConfigure }
            session.addOutput(output)
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

    // MARK: - AVCaptureAudioDataOutputSampleBufferDelegate

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard CMSampleBufferIsValid(sampleBuffer) else { return }
        onAudioSample?(sampleBuffer)
    }
}

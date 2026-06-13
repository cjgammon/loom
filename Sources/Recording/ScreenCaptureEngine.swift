import Foundation
import ScreenCaptureKit
import CoreMedia

/// Drives an `SCStream` that delivers display video frames and (on macOS 13+) system
/// audio sample buffers. Buffers are forwarded to the supplied closures on the
/// stream's delivery queue; the coordinator routes them into `MovieWriter`.
final class ScreenCaptureEngine: NSObject, SCStreamOutput {
    enum CaptureError: LocalizedError {
        case streamStartFailed(String)

        var errorDescription: String? {
            switch self {
            case .streamStartFailed(let d): return "Could not start screen capture: \(d)."
            }
        }
    }

    var onVideoSample: ((CMSampleBuffer) -> Void)?
    var onAudioSample: ((CMSampleBuffer) -> Void)?

    private var stream: SCStream?
    private let sampleQueue = DispatchQueue(label: "com.cjgammon.Spool.screen.samples")

    /// Start capturing the given source at its native size, with system audio.
    func start(source: CaptureContentPicker.Source, captureSystemAudio: Bool) async throws {
        let filter = CaptureContentPicker.filter(for: source)
        let (width, height) = CaptureContentPicker.dimensions(for: source)

        let config = SCStreamConfiguration()
        config.width = width
        config.height = height
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        config.queueDepth = 6
        config.showsCursor = true
        config.pixelFormat = kCVPixelFormatType_32BGRA
        if captureSystemAudio {
            config.capturesAudio = true
            config.excludesCurrentProcessAudio = true
        }

        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
        if captureSystemAudio {
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleQueue)
        }

        do {
            try await stream.startCapture()
        } catch {
            throw CaptureError.streamStartFailed(error.localizedDescription)
        }
        self.stream = stream
        Log.recording.info("Screen capture started (\(width)×\(height), audio: \(captureSystemAudio)).")
    }

    func stop() async {
        guard let stream = stream else { return }
        try? await stream.stopCapture()
        self.stream = nil
        Log.recording.info("Screen capture stopped.")
    }

    // MARK: - SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard CMSampleBufferIsValid(sampleBuffer) else { return }
        switch type {
        case .screen:
            // Only forward frames that ScreenCaptureKit marks as complete.
            guard sampleBuffer.isCompleteScreenFrame else { return }
            onVideoSample?(sampleBuffer)
        case .audio:
            onAudioSample?(sampleBuffer)
        default:
            break
        }
    }
}

private extension CMSampleBuffer {
    /// ScreenCaptureKit attaches per-frame status; only `.complete` frames carry pixels.
    var isCompleteScreenFrame: Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(self, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let first = attachments.first,
              let rawStatus = first[.status] as? Int,
              let status = SCFrameStatus(rawValue: rawStatus) else {
            return true // If we can't tell, don't drop it.
        }
        return status == .complete
    }
}

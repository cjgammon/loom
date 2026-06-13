import Foundation
import AVFoundation
import CoreMedia

/// Wraps `AVAssetWriter` to mux the recording into an `.mp4`: one H.264 video track
/// (the screen) plus up to two AAC audio tracks (system audio and microphone).
///
/// All sample appends are funneled through `writerQueue` so the three capture sources
/// (ScreenCaptureKit screen, ScreenCaptureKit audio, AVCaptureSession mic) can hand
/// off buffers from their own callback queues safely.
///
/// `@unchecked Sendable`: all mutable state is confined to `writerQueue`, so the
/// instance is safe to hand to the capture engines' background callbacks.
final class MovieWriter: @unchecked Sendable {
    enum Track {
        case video
        case systemAudio
        case microphone
    }

    enum WriterError: LocalizedError {
        case alreadyStarted
        case couldNotCreateWriter(String)

        var errorDescription: String? {
            switch self {
            case .alreadyStarted: return "Recording is already in progress."
            case .couldNotCreateWriter(let d): return "Could not start recording: \(d)."
            }
        }
    }

    let outputURL: URL

    private let writer: AVAssetWriter
    private var videoInput: AVAssetWriterInput?
    private var systemAudioInput: AVAssetWriterInput?
    private var micInput: AVAssetWriterInput?

    private let writerQueue = DispatchQueue(label: "com.cjgammon.Spool.writer")
    private var sessionStarted = false
    private var finished = false

    init(outputURL: URL) throws {
        self.outputURL = outputURL
        do {
            self.writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        } catch {
            throw WriterError.couldNotCreateWriter(error.localizedDescription)
        }
    }

    // MARK: - Input configuration (call before `start`)

    func configureVideo(width: Int, height: Int) {
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: Self.bitrate(width: width, height: height),
                AVVideoExpectedSourceFrameRateKey: 60,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            ],
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = true
        if writer.canAdd(input) { writer.add(input) }
        videoInput = input
    }

    func configureSystemAudio() {
        systemAudioInput = makeAudioInput()
    }

    func configureMicrophone() {
        micInput = makeAudioInput()
    }

    private func makeAudioInput() -> AVAssetWriterInput {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVNumberOfChannelsKey: 2,
            AVSampleRateKey: 48_000,
            AVEncoderBitRateKey: 160_000,
        ]
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
        input.expectsMediaDataInRealTime = true
        if writer.canAdd(input) { writer.add(input) }
        return input
    }

    // MARK: - Lifecycle

    func start() throws {
        guard !sessionStarted else { throw WriterError.alreadyStarted }
        guard writer.startWriting() else {
            throw WriterError.couldNotCreateWriter(writer.error?.localizedDescription ?? "unknown")
        }
    }

    /// Append a sample buffer for the given track. The writer session is lazily started
    /// on the first video buffer so all tracks share the same zero point.
    func append(_ sampleBuffer: CMSampleBuffer, to track: Track) {
        writerQueue.async { [weak self] in
            guard let self = self, !self.finished else { return }
            guard self.writer.status == .writing else { return }

            // Anchor the timeline to the first video frame.
            if !self.sessionStarted {
                guard track == .video else { return }
                let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                self.writer.startSession(atSourceTime: pts)
                self.sessionStarted = true
            }

            let input: AVAssetWriterInput?
            switch track {
            case .video: input = self.videoInput
            case .systemAudio: input = self.systemAudioInput
            case .microphone: input = self.micInput
            }
            guard let input = input, input.isReadyForMoreMediaData else { return }
            input.append(sampleBuffer)
        }
    }

    func finish() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            writerQueue.async { [weak self] in
                guard let self = self, !self.finished else {
                    continuation.resume(); return
                }
                self.finished = true
                self.videoInput?.markAsFinished()
                self.systemAudioInput?.markAsFinished()
                self.micInput?.markAsFinished()
                self.writer.finishWriting {
                    continuation.resume()
                }
            }
        }
    }

    // MARK: - Helpers

    /// Rough quality-oriented bitrate target scaled by pixel count (~0.15 bpp @ 60fps).
    private static func bitrate(width: Int, height: Int) -> Int {
        let pixels = width * height
        return max(4_000_000, Int(Double(pixels) * 0.15 * 60 / 8))
    }
}

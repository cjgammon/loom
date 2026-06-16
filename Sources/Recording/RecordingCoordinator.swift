import Foundation
import AVFoundation
import AppKit

/// Options chosen in the UI before a recording starts.
struct RecordingOptions {
    var source: CaptureContentPicker.Source
    var includeCamera: Bool
    var includeMicrophone: Bool
    var includeSystemAudio: Bool
    var cameraDevice: AVCaptureDevice?
    var microphoneDevice: AVCaptureDevice?
}

/// Orchestrates the full capture graph — screen + system audio (ScreenCaptureKit),
/// microphone (AVCaptureSession), and the on-screen camera bubble — feeding all
/// sample buffers into a single `MovieWriter`.
@MainActor
final class RecordingCoordinator {
    enum State {
        case idle
        case recording
    }

    private(set) var state: State = .idle

    private let screenEngine = ScreenCaptureEngine()
    private let cameraEngine = CameraEngine()
    private let micEngine = MicrophoneEngine()

    private var writer: MovieWriter?
    private var bubbleWindow: CameraBubbleWindow?
    private(set) var currentOutputURL: URL?

    // MARK: - Start

    func start(options: RecordingOptions) async throws {
        guard state == .idle else { return }

        let outputURL = try Self.makeOutputURL()
        let (width, height) = CaptureContentPicker.dimensions(for: options.source)

        let writer = try MovieWriter(outputURL: outputURL)
        writer.configureVideo(width: width, height: height)
        if options.includeSystemAudio { writer.configureSystemAudio() }
        if options.includeMicrophone { writer.configureMicrophone() }
        try writer.start()
        self.writer = writer
        self.currentOutputURL = outputURL

        // Route capture callbacks into the writer. Capture `writer` (Sendable) rather
        // than `self` so these run safely off the main actor.
        screenEngine.onVideoSample = { buffer in writer.append(buffer, to: .video) }
        if options.includeSystemAudio {
            screenEngine.onAudioSample = { buffer in writer.append(buffer, to: .systemAudio) }
        }
        if options.includeMicrophone {
            micEngine.onAudioSample = { buffer in writer.append(buffer, to: .microphone) }
        }

        // Camera bubble (shown on screen, captured in-frame). Skip if already warmed
        // up via warmUpCamera() so it isn't reconfigured/restarted.
        if options.includeCamera && bubbleWindow == nil {
            showCameraBubble(device: options.cameraDevice)
        }

        // Microphone.
        if options.includeMicrophone {
            try micEngine.configure(device: options.microphoneDevice)
            micEngine.start()
        }

        // Screen capture last so the bubble is already on screen.
        try await screenEngine.start(source: options.source, captureSystemAudio: options.includeSystemAudio)

        state = .recording
        Log.recording.info("Recording started → \(outputURL.lastPathComponent, privacy: .public)")
    }

    // MARK: - Camera warm-up

    /// Start the camera and show the bubble ahead of recording (e.g. during the
    /// countdown) so live frames are already flowing when capture begins — otherwise
    /// the bubble shows an empty circle for the first second. Safe to call repeatedly.
    func warmUpCamera(device: AVCaptureDevice?) {
        guard state == .idle, bubbleWindow == nil else { return }
        showCameraBubble(device: device)
    }

    /// Tear down a warmed-up camera/bubble (and mic) if recording never started, e.g.
    /// because `start()` threw after warm-up.
    func cancelWarmUp() {
        guard state == .idle else { return }
        cameraEngine.stop()
        micEngine.stop()
        bubbleWindow?.orderOut(nil)
        bubbleWindow = nil
    }

    private func showCameraBubble(device: AVCaptureDevice?) {
        do {
            try cameraEngine.configure(device: device)
            let bubble = CameraBubbleWindow(session: cameraEngine.session)
            bubbleWindow = bubble
            // Only reveal the bubble once the first frame arrives, so it never shows
            // an empty circle.
            cameraEngine.onReady = { [weak bubble] in bubble?.orderFrontRegardless() }
            cameraEngine.start()
        } catch {
            Log.recording.error("Camera setup failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Stop

    /// Stop all capture and finalize the file. Returns the written movie URL.
    @discardableResult
    func stop() async -> URL? {
        guard state == .recording else { return nil }

        await screenEngine.stop()
        micEngine.stop()
        cameraEngine.stop()

        bubbleWindow?.orderOut(nil)
        bubbleWindow = nil

        await writer?.finish()
        let url = currentOutputURL

        screenEngine.onVideoSample = nil
        screenEngine.onAudioSample = nil
        micEngine.onAudioSample = nil
        writer = nil
        state = .idle

        // Mix the separate mic + system-audio tracks into a single track so players
        // that only play the first audio track (e.g. Frame.io's web player) still
        // have sound. Best-effort: on failure the original multi-track file is kept.
        if let url = url {
            do {
                try await MoviePostProcessor.flattenAudioInPlace(at: url)
            } catch {
                Log.recording.error("Audio flatten failed, keeping multi-track file: \(error.localizedDescription, privacy: .public)")
            }
        }

        Log.recording.info("Recording finished.")
        return url
    }

    // MARK: - Output location

    static func makeOutputURL() throws -> URL {
        let movies = try FileManager.default.url(
            for: .moviesDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        let dir = movies.appendingPathComponent("Spool", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let name = "Spool Recording \(formatter.string(from: Date())).mp4"
        return dir.appendingPathComponent(name)
    }
}

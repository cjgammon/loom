import Foundation
import SwiftUI
import AVFoundation
import ScreenCaptureKit

/// Top-level observable app state shared across the menu-bar UI. Owns the auth
/// manager, the recording coordinator, and the Frame.io upload pipeline, and exposes
/// the high-level phases the UI renders.
@MainActor
final class AppState: ObservableObject {
    enum Phase: Equatable {
        case idle
        case preparing
        case recording
        case uploading(Double)
        case finished(link: String?)
        case failed(String)
    }

    // Collaborators
    let auth = FrameIOAuth()
    private(set) lazy var client = FrameIOClient(auth: auth)
    private lazy var uploader = FrameIOUploader(client: client)
    private let coordinator = RecordingCoordinator()
    private let countdown = CountdownController()
    private let hotKeys = HotKeyManager()

    // Published UI state
    @Published var phase: Phase = .idle
    @Published var availableSources: [CaptureContentPicker.Source] = []
    @Published var selectedSourceID: String?
    @Published var includeCamera = true
    @Published var includeMicrophone = true
    @Published var includeSystemAudio = true
    @Published var availableMicrophones: [AVCaptureDevice] = []
    @Published var selectedMicrophoneID: String? {
        didSet { UserDefaults.standard.set(selectedMicrophoneID, forKey: microphoneDefaultsKey) }
    }
    @Published var availableCameras: [AVCaptureDevice] = []
    @Published var selectedCameraID: String? {
        didSet { UserDefaults.standard.set(selectedCameraID, forKey: cameraDefaultsKey) }
    }
    @Published var destination: UploadDestination? {
        didSet { persistDestination() }
    }
    @Published var lastShareLink: String?
    /// Seconds of "3-2-1" countdown before capture starts (0 = off).
    @Published var countdownSeconds: Int {
        didSet { UserDefaults.standard.set(countdownSeconds, forKey: countdownDefaultsKey) }
    }
    /// Elapsed recording time, updated while recording for the menu-bar timer.
    @Published var recordingElapsed: TimeInterval = 0

    private let destinationDefaultsKey = "SpoolUploadDestination"
    private let microphoneDefaultsKey = "SpoolMicrophoneID"
    private let cameraDefaultsKey = "SpoolCameraID"
    private let countdownDefaultsKey = "SpoolCountdownSeconds"

    private var recordingStartedAt: Date?
    private var elapsedTimerTask: Task<Void, Never>?

    init() {
        // Default countdown to 3s on first launch; honor a stored 0 (off) thereafter.
        countdownSeconds = UserDefaults.standard.object(forKey: countdownDefaultsKey) as? Int ?? 3
        destination = loadDestination()
        selectedMicrophoneID = UserDefaults.standard.string(forKey: microphoneDefaultsKey)
        selectedCameraID = UserDefaults.standard.string(forKey: cameraDefaultsKey)

        // Global ⌥⌘R to start/stop recording from anywhere.
        hotKeys.onTrigger = { [weak self] in
            Task { @MainActor in self?.toggleRecording() }
        }
        hotKeys.register()
    }

    var recordingElapsedString: String {
        let total = Int(recordingElapsed)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    var isSignedIn: Bool { auth.isSignedIn }
    var isRecording: Bool { if case .recording = phase { return true }; return false }

    // MARK: - Source discovery

    func refreshSources() async {
        do {
            let sources = try await CaptureContentPicker.availableSources(includeWindows: true)
            availableSources = sources
            if selectedSourceID == nil { selectedSourceID = sources.first?.id }
        } catch {
            phase = .failed("Screen Recording permission is required. Grant it in System Settings → Privacy & Security → Screen Recording, then reopen Spool.")
        }
    }

    private var selectedSource: CaptureContentPicker.Source? {
        availableSources.first { $0.id == selectedSourceID } ?? availableSources.first
    }

    /// Enumerate microphones for the picker. Keeps the saved selection if still present,
    /// otherwise falls back to the system default.
    func refreshMicrophones() {
        let mics = MicrophoneEngine.availableMicrophones()
        availableMicrophones = mics
        if selectedMicrophoneID == nil || !mics.contains(where: { $0.uniqueID == selectedMicrophoneID }) {
            selectedMicrophoneID = AVCaptureDevice.default(for: .audio)?.uniqueID ?? mics.first?.uniqueID
        }
    }

    private var selectedMicrophoneDevice: AVCaptureDevice? {
        availableMicrophones.first { $0.uniqueID == selectedMicrophoneID }
    }

    /// Enumerate cameras for the bubble picker. Keeps the saved selection if still
    /// present, otherwise falls back to the system default camera.
    func refreshCameras() {
        let cameras = CameraEngine.availableCameras()
        availableCameras = cameras
        if selectedCameraID == nil || !cameras.contains(where: { $0.uniqueID == selectedCameraID }) {
            selectedCameraID = AVCaptureDevice.default(for: .video)?.uniqueID ?? cameras.first?.uniqueID
        }
    }

    private var selectedCameraDevice: AVCaptureDevice? {
        availableCameras.first { $0.uniqueID == selectedCameraID }
    }

    // MARK: - Recording control

    /// Toggle recording — used by the global hotkey and any toggle UI.
    func toggleRecording() {
        switch phase {
        case .recording:
            Task { await stopRecording() }
        case .preparing, .uploading:
            break // busy; ignore
        default:
            Task { await startRecording() }
        }
    }

    func startRecording() async {
        guard let source = selectedSource else {
            phase = .failed("Choose something to record first.")
            return
        }
        phase = .preparing

        // Count down first so the numbers aren't part of the recording.
        await countdown.run(seconds: countdownSeconds)

        let options = RecordingOptions(
            source: source,
            includeCamera: includeCamera,
            includeMicrophone: includeMicrophone,
            includeSystemAudio: includeSystemAudio,
            cameraDevice: selectedCameraDevice,
            microphoneDevice: selectedMicrophoneDevice
        )
        do {
            try await coordinator.start(options: options)
            phase = .recording
            startElapsedTimer()
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func stopRecording() async {
        stopElapsedTimer()
        guard let url = await coordinator.stop() else {
            phase = .idle
            return
        }
        await handleFinishedRecording(at: url)
    }

    private func startElapsedTimer() {
        recordingStartedAt = Date()
        recordingElapsed = 0
        elapsedTimerTask?.cancel()
        elapsedTimerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard let self, let start = self.recordingStartedAt else { break }
                self.recordingElapsed = Date().timeIntervalSince(start)
            }
        }
    }

    private func stopElapsedTimer() {
        elapsedTimerTask?.cancel()
        elapsedTimerTask = nil
        recordingStartedAt = nil
    }

    // MARK: - Upload

    private func handleFinishedRecording(at url: URL) async {
        // If signed in with a destination, upload; otherwise leave the file locally.
        guard isSignedIn, let destination = destination else {
            phase = .finished(link: nil)
            lastShareLink = nil
            Log.frameio.info("Saved locally (not uploaded): \(url.path, privacy: .public)")
            return
        }

        phase = .uploading(0)
        do {
            let link = try await uploader.upload(fileURL: url, destination: destination) { [weak self] fraction in
                Task { @MainActor in self?.phase = .uploading(fraction) }
            }
            lastShareLink = link
            phase = .finished(link: link)
        } catch {
            phase = .failed("Upload failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Auth

    func signIn() async {
        do { try await auth.signIn() } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func signOut() {
        auth.signOut()
        destination = nil
    }

    // MARK: - Destination persistence

    private func persistDestination() {
        if let destination = destination, let data = try? JSONEncoder().encode(destination) {
            UserDefaults.standard.set(data, forKey: destinationDefaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: destinationDefaultsKey)
        }
    }

    private func loadDestination() -> UploadDestination? {
        guard let data = UserDefaults.standard.data(forKey: destinationDefaultsKey) else { return nil }
        return try? JSONDecoder().decode(UploadDestination.self, from: data)
    }
}

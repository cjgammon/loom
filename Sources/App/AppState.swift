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

    // Published UI state
    @Published var phase: Phase = .idle
    @Published var availableSources: [CaptureContentPicker.Source] = []
    @Published var selectedSourceID: String?
    @Published var includeCamera = true
    @Published var includeMicrophone = true
    @Published var includeSystemAudio = true
    @Published var destination: UploadDestination? {
        didSet { persistDestination() }
    }
    @Published var lastShareLink: String?

    private let destinationDefaultsKey = "SpoolUploadDestination"

    init() {
        destination = loadDestination()
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

    // MARK: - Recording control

    func startRecording() async {
        guard let source = selectedSource else {
            phase = .failed("Choose something to record first.")
            return
        }
        phase = .preparing
        let options = RecordingOptions(
            source: source,
            includeCamera: includeCamera,
            includeMicrophone: includeMicrophone,
            includeSystemAudio: includeSystemAudio,
            cameraDevice: nil,
            microphoneDevice: nil
        )
        do {
            try await coordinator.start(options: options)
            phase = .recording
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func stopRecording() async {
        guard let url = await coordinator.stop() else {
            phase = .idle
            return
        }
        await handleFinishedRecording(at: url)
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

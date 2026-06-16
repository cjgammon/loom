import SwiftUI

/// Pre-recording controls: pick a source, toggle camera/mic/system audio, and start.
struct RecordingControlsView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Record", selection: $state.selectedSourceID) {
                ForEach(state.availableSources) { source in
                    Text(source.title).tag(Optional(source.id))
                }
            }
            .pickerStyle(.menu)

            VStack(alignment: .leading, spacing: 4) {
                Toggle(isOn: $state.includeCamera) {
                    Label("Camera bubble", systemImage: "person.crop.circle")
                }
                Toggle(isOn: $state.includeMicrophone) {
                    Label("Microphone", systemImage: "mic")
                }
                Toggle(isOn: $state.includeSystemAudio) {
                    Label("System audio", systemImage: "speaker.wave.2")
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)

            // Choose which camera feeds the bubble when more than one is available.
            if state.includeCamera && state.availableCameras.count > 1 {
                Picker("Camera", selection: $state.selectedCameraID) {
                    ForEach(state.availableCameras, id: \.uniqueID) { camera in
                        Text(camera.localizedName).tag(Optional(camera.uniqueID))
                    }
                }
                .pickerStyle(.menu)
                .controlSize(.small)
            }

            // Choose which microphone to record when more than one is available.
            if state.includeMicrophone && state.availableMicrophones.count > 1 {
                Picker("Mic", selection: $state.selectedMicrophoneID) {
                    ForEach(state.availableMicrophones, id: \.uniqueID) { mic in
                        Text(mic.localizedName).tag(Optional(mic.uniqueID))
                    }
                }
                .pickerStyle(.menu)
                .controlSize(.small)
            }

            Button {
                Task { await state.startRecording() }
            } label: {
                Label("Start Recording", systemImage: "record.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(state.availableSources.isEmpty)

            if case .preparing = state.phase {
                ProgressView("Preparing…").controlSize(.small)
            }
        }
    }
}

/// Shown while a recording is in progress.
struct RecordingActiveView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(spacing: 10) {
            Label("Recording…", systemImage: "record.circle.fill")
                .foregroundStyle(.red)
                .font(.headline)

            Button(role: .destructive) {
                Task { await state.stopRecording() }
            } label: {
                Label("Stop & Upload", systemImage: "stop.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

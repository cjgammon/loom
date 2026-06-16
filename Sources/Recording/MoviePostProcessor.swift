import Foundation
import AVFoundation

/// Post-recording fix-ups for the finished movie file.
///
/// Spool captures microphone and system audio as two independent `AVAssetWriter`
/// audio inputs, which produces a file with two audio tracks. Desktop players mix
/// them, but some web players (notably Frame.io's) only play the first audio track,
/// so narration recorded on the mic track is inaudible there.
///
/// `flattenAudioInPlace` rewrites the file with the audio tracks **mixed down into a
/// single AAC track** while passing the video through untouched (no re-encode).
enum MoviePostProcessor {
    enum ProcessError: LocalizedError {
        case readerInitFailed
        case writerInitFailed
        case readFailed(String)
        case writeFailed(String)

        var errorDescription: String? {
            switch self {
            case .readerInitFailed: return "Could not read the recording for audio mixing."
            case .writerInitFailed: return "Could not create the mixed output file."
            case .readFailed(let d): return "Reading failed during audio mixing: \(d)."
            case .writeFailed(let d): return "Writing failed during audio mixing: \(d)."
            }
        }
    }

    /// Mix all audio tracks into one and overwrite `url`. No-op if the file has 0 or 1
    /// audio track (nothing to merge).
    static func flattenAudioInPlace(at url: URL) async throws {
        let asset = AVURLAsset(url: url)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard audioTracks.count > 1 else { return } // nothing to merge

        let videoTracks = try await asset.loadTracks(withMediaType: .video)

        let tempURL = url.deletingLastPathComponent()
            .appendingPathComponent("." + url.deletingPathExtension().lastPathComponent + "-mix.mp4")
        try? FileManager.default.removeItem(at: tempURL)

        guard let reader = try? AVAssetReader(asset: asset) else { throw ProcessError.readerInitFailed }
        guard let writer = try? AVAssetWriter(outputURL: tempURL, fileType: .mp4) else {
            throw ProcessError.writerInitFailed
        }

        // Video: straight passthrough (compressed samples copied, no re-encode).
        var videoOutput: AVAssetReaderTrackOutput?
        var videoInput: AVAssetWriterInput?
        if let videoTrack = videoTracks.first {
            let output = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: nil)
            output.alwaysCopiesSampleData = false
            if reader.canAdd(output) { reader.add(output) }
            let formatHint = try await videoTrack.load(.formatDescriptions).first
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: formatHint)
            input.expectsMediaDataInRealTime = false
            if writer.canAdd(input) { writer.add(input) }
            videoOutput = output
            videoInput = input
        }

        // Audio: decode + mix every audio track into one PCM stream, re-encode to AAC.
        let pcmSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 2,
        ]
        let audioOutput = AVAssetReaderAudioMixOutput(audioTracks: audioTracks, audioSettings: pcmSettings)
        audioOutput.alwaysCopiesSampleData = false
        if reader.canAdd(audioOutput) { reader.add(audioOutput) }

        let aacSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVNumberOfChannelsKey: 2,
            AVSampleRateKey: 48_000,
            AVEncoderBitRateKey: 160_000,
        ]
        let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: aacSettings)
        audioInput.expectsMediaDataInRealTime = false
        if writer.canAdd(audioInput) { writer.add(audioInput) }

        guard reader.startReading() else {
            throw ProcessError.readFailed(reader.error?.localizedDescription ?? "startReading")
        }
        guard writer.startWriting() else {
            throw ProcessError.writeFailed(writer.error?.localizedDescription ?? "startWriting")
        }
        writer.startSession(atSourceTime: .zero)

        // Pump video and audio on independent queues; finish when both drain.
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let group = DispatchGroup()

            if let videoInput = videoInput, let videoOutput = videoOutput {
                group.enter()
                videoInput.requestMediaDataWhenReady(on: DispatchQueue(label: "com.cjgammon.Spool.mix.video")) {
                    while videoInput.isReadyForMoreMediaData {
                        if let sample = videoOutput.copyNextSampleBuffer() {
                            videoInput.append(sample)
                        } else {
                            videoInput.markAsFinished()
                            group.leave()
                            return
                        }
                    }
                }
            }

            group.enter()
            audioInput.requestMediaDataWhenReady(on: DispatchQueue(label: "com.cjgammon.Spool.mix.audio")) {
                while audioInput.isReadyForMoreMediaData {
                    if let sample = audioOutput.copyNextSampleBuffer() {
                        audioInput.append(sample)
                    } else {
                        audioInput.markAsFinished()
                        group.leave()
                        return
                    }
                }
            }

            group.notify(queue: DispatchQueue(label: "com.cjgammon.Spool.mix.done")) {
                writer.finishWriting { continuation.resume() }
            }
        }

        guard writer.status == .completed else {
            try? FileManager.default.removeItem(at: tempURL)
            throw ProcessError.writeFailed(writer.error?.localizedDescription ?? "incomplete")
        }
        guard reader.status == .completed else {
            try? FileManager.default.removeItem(at: tempURL)
            throw ProcessError.readFailed(reader.error?.localizedDescription ?? "incomplete")
        }

        // Swap the mixed file in for the original.
        _ = try FileManager.default.replaceItemAt(url, withItemAt: tempURL)
        Log.recording.info("Mixed \(audioTracks.count) audio tracks into one.")
    }
}

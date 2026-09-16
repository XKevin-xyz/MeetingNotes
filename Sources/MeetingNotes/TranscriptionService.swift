import Foundation
import AVFoundation
import SpeakerKit
import WhisperKit

actor TranscriptionService {
    enum TranscriptionError: LocalizedError {
        case noAudioFile

        var errorDescription: String? {
            switch self {
            case .noAudioFile:
                return "Er is geen systeem-audiobestand gevonden om te transcriberen."
            }
        }
    }

    func transcribe(
        sessionURL: URL,
        modelsURL: URL,
        modelVariant: String = "tiny",
        language: String = "nl",
        skipSilence: Bool = true
    ) async throws -> TranscriptDocument {
        let systemAudioURL = sessionURL.appendingPathComponent("system-audio.wav")
        let microphoneURL = sessionURL.appendingPathComponent("microphone.wav")
        guard FileManager.default.fileExists(atPath: systemAudioURL.path)
                || FileManager.default.fileExists(atPath: microphoneURL.path) else {
            throw TranscriptionError.noAudioFile
        }

        try FileManager.default.createDirectory(at: modelsURL, withIntermediateDirectories: true)
        // WhisperKit treats a supplied modelFolder as an already-downloaded
        // model. Download explicitly first, then load from our app-managed
        // Models directory so cleanup remains predictable.
        let downloadedModelURL = try await WhisperKit.download(
            variant: modelVariant,
            downloadBase: modelsURL
        )
        let config = WhisperKitConfig(
            model: modelVariant,
            modelFolder: downloadedModelURL.path,
            load: true,
            download: false
        )
        let whisper = try await WhisperKit(config)
        let options = DecodingOptions(
            language: language,
            wordTimestamps: true,
            chunkingStrategy: skipSilence ? .vad : ChunkingStrategy.none
        )
        let speakerKit = try await SpeakerKit()

        var segments: [TranscriptSegment] = []
        if FileManager.default.fileExists(atPath: microphoneURL.path) {
            segments.append(contentsOf: try await transcribeFile(
                microphoneURL,
                speaker: "Jij",
                whisper: whisper,
                speakerKit: nil,
                options: options,
                idOffset: 0
            ))
        }
        if FileManager.default.fileExists(atPath: systemAudioURL.path) {
            segments.append(contentsOf: try await transcribeFile(
                systemAudioURL,
                speaker: "Systeem",
                whisper: whisper,
                speakerKit: speakerKit,
                options: options,
                idOffset: segments.count
            ))
        }

        segments.sort { $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start }

        return TranscriptDocument(language: "nl", segments: segments)
    }

    private func transcribeFile(
        _ audioURL: URL,
        speaker: String,
        whisper: WhisperKit,
        speakerKit: SpeakerKit?,
        options: DecodingOptions,
        idOffset: Int
    ) async throws -> [TranscriptSegment] {
        guard containsSpeech(in: audioURL) else { return [] }
        let results = try await whisper.transcribe(audioPath: audioURL.path, decodeOptions: options)

        if let speakerKit {
            let audioArray = try AudioProcessor.loadAudioAsFloatArray(fromPath: audioURL.path)
            let diarization = try await speakerKit.diarize(audioArray: audioArray)
            let attributed = diarization.addSpeakerInfo(to: results, strategy: .segment).flatMap { $0 }
            if !attributed.isEmpty {
                return attributed.enumerated().compactMap { index, segment in
                    let cleaned = cleanWhisperTokens(segment.text)
                    guard !cleaned.isEmpty else { return nil }
                    return TranscriptSegment(
                        id: idOffset + index,
                        start: TimeInterval(segment.startTime),
                        end: TimeInterval(segment.endTime),
                        text: cleaned,
                        speaker: "Spreker \((segment.speaker.speakerId ?? 0) + 1)"
                    )
                }
            }
        }

        return results.flatMap(\.segments).enumerated().compactMap { index, segment in
            let cleaned = cleanWhisperTokens(segment.text)
            guard !cleaned.isEmpty else { return nil }
            return TranscriptSegment(
                id: idOffset + index,
                start: TimeInterval(segment.start),
                end: TimeInterval(segment.end),
                text: cleaned,
                speaker: speaker
            )
        }
    }

    private func cleanWhisperTokens(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "<\\|[^>]+\\|>") else {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let range = NSRange(text.startIndex..., in: text)
        let cleaned = regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func containsSpeech(in url: URL) -> Bool {
        guard let file = try? AVAudioFile(forReading: url),
              let buffer = AVAudioPCMBuffer(
                pcmFormat: file.processingFormat,
                frameCapacity: AVAudioFrameCount(min(file.length, 160_000))
              ) else { return true }

        do {
            try file.read(into: buffer)
        } catch {
            return true
        }

        guard let channelData = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return true }
        let sampleCount = Int(buffer.frameLength)
        var energy: Float = 0
        for index in stride(from: 0, to: sampleCount, by: max(1, sampleCount / 10_000)) {
            energy += abs(channelData[index])
        }
        let averageEnergy = energy / Float(max(1, sampleCount / max(1, sampleCount / 10_000)))
        return averageEnergy > 0.002
    }
}

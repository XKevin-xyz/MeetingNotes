import AVFoundation
import Foundation
import ScreenCaptureKit

@MainActor
@Observable
final class RecordingCoordinator {
    private(set) var isRecording = false
    private(set) var statusMessage = "Klaar om microfoon en systeemaudio op te nemen."
    private(set) var latestSessionURL: URL?
    private(set) var transcript: TranscriptDocument?
    private(set) var latestTranscriptURL: URL?
    private(set) var isTranscribing = false
    private(set) var transcriptionStartedAt: Date?

    private var captureEngine: AudioCaptureEngine?
    private let transcriptionService = TranscriptionService()

    func toggleRecording(storage: AppStorageManager) async {
        if isRecording {
            await stopRecording(storage: storage)
            return
        }

        let microphoneGranted = await AVCaptureDevice.requestAccess(for: .audio)
        guard microphoneGranted else {
            statusMessage = "Microfoontoegang is nodig om je eigen stem op te nemen."
            return
        }

        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
            statusMessage = "Scherm- en systeemaudiotoegang is nodig voor audio uit Meet, Teams, Zoom en Discord."
            return
        }

        do {
            let engine = AudioCaptureEngine(storage: storage)
            try await engine.start()
            captureEngine = engine
            isRecording = true
            statusMessage = "Opname loopt. Microfoon en systeemaudio worden apart opgeslagen."
        } catch {
            statusMessage = "Opname kon niet starten: \(error.localizedDescription)"
        }
    }

    private func stopRecording(storage: AppStorageManager) async {
        latestSessionURL = await captureEngine?.stop()
        captureEngine = nil
        isRecording = false
        if let latestSessionURL {
            statusMessage = "Opname opgeslagen in \(latestSessionURL.lastPathComponent). Transcriptie volgt in de volgende module."
            storage.refreshSessions()
        } else {
            statusMessage = "Opname gestopt. Er is geen sessiemap gevonden."
        }

        if UserDefaults.standard.bool(forKey: "autoTranscribe"), latestSessionURL != nil {
            await transcribeLatest(storage: storage)
        }
    }

    func transcribeLatest(storage: AppStorageManager) async {
        guard let latestSessionURL else {
            statusMessage = "Maak eerst een opname."
            return
        }

        isTranscribing = true
        transcriptionStartedAt = Date()
        statusMessage = "Transcriptie wordt voorbereid…"
        do {
            let selectedQuality = UserDefaults.standard.string(forKey: "transcriptionQuality") ?? "base"
            let modelVariant = selectedQuality == "large" ? "large-v3-v20240930_626MB" : selectedQuality
            let language = UserDefaults.standard.string(forKey: "preferredLanguage") ?? "nl"
            let skipSilence = UserDefaults.standard.object(forKey: "skipSilence") as? Bool ?? true
            transcript = try await transcriptionService.transcribe(
                sessionURL: latestSessionURL,
                modelsURL: storage.modelsURL,
                modelVariant: modelVariant,
                language: language,
                skipSilence: skipSilence
            )
            if let transcript {
                latestTranscriptURL = try storage.saveTranscript(transcript, in: latestSessionURL)
                storage.refreshSessions()
            }
            statusMessage = "Transcriptie opgeslagen: \(transcript?.segments.count ?? 0) segmenten."
        } catch {
            statusMessage = "Transcriptie mislukt: \(error.localizedDescription)"
        }
        isTranscribing = false
        transcriptionStartedAt = nil
    }

    func renameSpeaker(label: String, to name: String, storage: AppStorageManager) {
        storage.renameSpeaker(label: label, to: name)
        guard let transcript, let latestSessionURL else { return }
        _ = try? storage.saveTranscript(transcript, in: latestSessionURL)
    }

    func loadSession(_ session: MeetingSession) throws {
        let transcriptURL = session.folderURL.appendingPathComponent("transcript.json")
        guard FileManager.default.fileExists(atPath: transcriptURL.path) else {
            transcript = nil
            latestTranscriptURL = nil
            latestSessionURL = session.folderURL
            return
        }
        transcript = try JSONDecoder().decode(TranscriptDocument.self, from: Data(contentsOf: transcriptURL))
        latestSessionURL = session.folderURL
        latestTranscriptURL = session.transcriptURL
        statusMessage = "Vergadering geladen: \(session.title)"
    }

    func setStatus(_ message: String) {
        statusMessage = message
    }

    func clearLoadedSession() {
        latestSessionURL = nil
        latestTranscriptURL = nil
        transcript = nil
        statusMessage = "Klaar om microfoon en systeemaudio op te nemen."
    }
}

private final class AudioCaptureEngine: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let storage: AppStorageManager
    private var stream: SCStream?
    private let outputQueue = DispatchQueue(label: "com.meetingnotes.audio-capture")
    private let sessionFolder: URL
    private var microphoneFile: AVAudioFile?
    private var systemFile: AVAudioFile?

    init(storage: AppStorageManager) {
        self.storage = storage
        let folderName = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        sessionFolder = storage.recordingsURL.appendingPathComponent(folderName, isDirectory: true)
        try? FileManager.default.createDirectory(at: sessionFolder, withIntermediateDirectories: true)
        super.init()
    }

    func start() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let display = content.displays.first else {
            throw CaptureError.noDisplay
        }

        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = true
        configuration.captureMicrophone = true
        let selectedMicrophone = UserDefaults.standard.string(forKey: "microphoneDeviceID")
        configuration.microphoneCaptureDeviceID = selectedMicrophone?.isEmpty == true ? nil : selectedMicrophone
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = 16_000
        configuration.channelCount = 1
        configuration.width = 2
        configuration.height = 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)

        let configuredStream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try configuredStream.addStreamOutput(self, type: SCStreamOutputType.audio, sampleHandlerQueue: outputQueue)
        try configuredStream.addStreamOutput(self, type: SCStreamOutputType.microphone, sampleHandlerQueue: outputQueue)

        microphoneFile = nil
        systemFile = nil
        stream = configuredStream
        try await configuredStream.startCapture()
    }

    func stop() async -> URL? {
        try? await stream?.stopCapture()
        stream = nil
        microphoneFile = nil
        systemFile = nil
        return sessionFolder
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard sampleBuffer.isValid, sampleBuffer.numSamples > 0,
              let formatDescription = sampleBuffer.formatDescription else { return }

        let format = AVAudioFormat(cmAudioFormatDescription: formatDescription)
        try? sampleBuffer.withAudioBufferList { audioBufferList, _ in
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: audioBufferList.unsafePointer) else { return }
            buffer.frameLength = AVAudioFrameCount(sampleBuffer.numSamples)

            do {
                if type == .microphone {
                    if self.microphoneFile == nil {
                        self.microphoneFile = try AVAudioFile(forWriting: self.sessionFolder.appendingPathComponent("microphone.wav"), settings: buffer.format.settings)
                    }
                    try self.microphoneFile?.write(from: buffer)
                } else if type == .audio {
                    if self.systemFile == nil {
                        self.systemFile = try AVAudioFile(forWriting: self.sessionFolder.appendingPathComponent("system-audio.wav"), settings: buffer.format.settings)
                    }
                    try self.systemFile?.write(from: buffer)
                }
            } catch {
                NSLog("MeetingNotes audio write error: \(error.localizedDescription)")
            }
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        NSLog("MeetingNotes capture stopped: \(error.localizedDescription)")
    }

}

private enum CaptureError: LocalizedError {
    case noDisplay

    var errorDescription: String? {
        switch self {
        case .noDisplay: return "Er is geen scherm beschikbaar om systeemaudio te capturen."
        }
    }
}

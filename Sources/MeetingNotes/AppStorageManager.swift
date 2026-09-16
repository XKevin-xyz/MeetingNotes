import AppKit
import Foundation

@Observable
final class AppStorageManager {
    let rootURL: URL
    private let fileManager = FileManager.default
    private let speakerNamesKey = "speakerNames"

    var recordingsURL: URL {
        rootURL.appendingPathComponent("Recordings", isDirectory: true)
    }

    var modelsURL: URL {
        rootURL.appendingPathComponent("Models", isDirectory: true)
    }

    init() {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        rootURL = base.appendingPathComponent("MeetingNotes", isDirectory: true)
        try? fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        for folder in ["Recordings", "Transcripts", "Models", "Exports"] {
            try? fileManager.createDirectory(
                at: rootURL.appendingPathComponent(folder, isDirectory: true),
                withIntermediateDirectories: true
            )
        }
    }

    var formattedDataSize: String {
        ByteCountFormatter.string(fromByteCount: totalDataSize, countStyle: .file)
    }

    private var totalDataSize: Int64 {
        guard let enumerator = fileManager.enumerator(at: rootURL, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }

        return enumerator.reduce(into: Int64(0)) { total, item in
            guard let url = item as? URL,
                  let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
                  let size = values.fileSize else { return }
            total += Int64(size)
        }
    }

    func revealRootInFinder() {
        try? fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([rootURL])
    }

    func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func displaySpeakerName(for label: String) -> String {
        let names = UserDefaults.standard.dictionary(forKey: speakerNamesKey) as? [String: String] ?? [:]
        return names[label] ?? label
    }

    func renameSpeaker(label: String, to name: String) {
        var names = UserDefaults.standard.dictionary(forKey: speakerNamesKey) as? [String: String] ?? [:]
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == label {
            names.removeValue(forKey: label)
        } else {
            names[label] = trimmed
        }
        UserDefaults.standard.set(names, forKey: speakerNamesKey)
    }

    @discardableResult
    func saveTranscript(_ transcript: TranscriptDocument, in sessionURL: URL) throws -> URL {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonURL = sessionURL.appendingPathComponent("transcript.json")
        try encoder.encode(transcript).write(to: jsonURL, options: .atomic)

        let markdownURL = sessionURL.appendingPathComponent("transcript.md")
        var markdown = "# Transcriptie\n\n"
        markdown += "Taal: Nederlands\n\n"
        for segment in transcript.segments {
            let start = formatTimestamp(segment.start)
            markdown += "**[\(start)] \(displaySpeakerName(for: segment.speaker)):** \(segment.text)\n\n"
        }
        try markdown.write(to: markdownURL, atomically: true, encoding: .utf8)
        return markdownURL
    }

    private func formatTimestamp(_ seconds: TimeInterval) -> String {
        let totalSeconds = max(0, Int(seconds))
        return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }

    func deleteAllUserData() {
        try? fileManager.removeItem(at: rootURL)
        try? fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }
}

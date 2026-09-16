import AppKit
import Foundation

struct MeetingSession: Identifiable, Hashable, Sendable {
    let id: String
    let folderURL: URL
    var title: String
    let date: Date
    let hasTranscript: Bool

    var transcriptURL: URL {
        folderURL.appendingPathComponent("transcript.md")
    }
}

@Observable
final class AppStorageManager {
    let rootURL: URL
    private let fileManager = FileManager.default
    private let speakerNamesKey = "speakerNames"
    private let sessionNamesKey = "sessionNames"
    private(set) var sessions: [MeetingSession] = []

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
        refreshSessions()
    }

    func refreshSessions() {
        let names = UserDefaults.standard.dictionary(forKey: sessionNamesKey) as? [String: String] ?? [:]
        let urls = (try? fileManager.contentsOfDirectory(
            at: recordingsURL,
            includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        sessions = urls.compactMap { url in
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return nil }
            let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
            let date = values?.creationDate ?? values?.contentModificationDate ?? .distantPast
            let id = url.lastPathComponent
            let transcriptExists = fileManager.fileExists(atPath: url.appendingPathComponent("transcript.md").path)
            return MeetingSession(
                id: id,
                folderURL: url,
                title: names[id] ?? Self.defaultSessionTitle(for: date),
                date: date,
                hasTranscript: transcriptExists
            )
        }
        .sorted { $0.date > $1.date }
    }

    func renameSession(_ session: MeetingSession, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        var names = UserDefaults.standard.dictionary(forKey: sessionNamesKey) as? [String: String] ?? [:]
        if trimmed.isEmpty || trimmed == Self.defaultSessionTitle(for: session.date) {
            names.removeValue(forKey: session.id)
        } else {
            names[session.id] = trimmed
        }
        UserDefaults.standard.set(names, forKey: sessionNamesKey)
        refreshSessions()
    }

    func deleteSession(_ session: MeetingSession) {
        try? fileManager.removeItem(at: session.folderURL)
        var names = UserDefaults.standard.dictionary(forKey: sessionNamesKey) as? [String: String] ?? [:]
        names.removeValue(forKey: session.id)
        UserDefaults.standard.set(names, forKey: sessionNamesKey)
        refreshSessions()
    }

    private static func defaultSessionTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "nl_NL")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return "Vergadering — \(formatter.string(from: date))"
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
        UserDefaults.standard.removeObject(forKey: sessionNamesKey)
        refreshSessions()
    }
}

import Foundation

struct MeetingSummary: Sendable {
    let overview: String
    let highlights: [String]
    let decisions: [String]
    let actions: [String]
    let openQuestions: [String]
}

enum SummaryService {
    static func generate(for transcript: TranscriptDocument) -> MeetingSummary {
        let segments = transcript.segments.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let texts = unique(segments.map(\.text))
        let normalized = segments.map { ($0, $0.text.lowercased()) }

        let decisions = unique(normalized.compactMap { segment, text in
            matches(text, words: ["besloten", "afgesproken", "besluit", "akkoord", "we gaan"]) ? segment.text : nil
        })
        let actions = unique(normalized.compactMap { segment, text in
            matches(text, words: ["actie", "oppakken", "regelen", "sturen", "uitzoeken", "moet", "zal "]) ? "\(segment.speaker): \(segment.text)" : nil
        })
        let questions = unique(normalized.compactMap { segment, text in
            matches(text, words: ["?", "open vraag", "nog uitzoeken", "onduidelijk", "wanneer"]) ? segment.text : nil
        })

        return MeetingSummary(
            overview: texts.isEmpty ? "Er is nog geen tekst beschikbaar om samen te vatten." : texts.prefix(3).joined(separator: " "),
            highlights: Array(texts.prefix(5)),
            decisions: decisions,
            actions: actions,
            openQuestions: questions
        )
    }

    private static func matches(_ text: String, words: [String]) -> Bool {
        words.contains { text.contains($0) }
    }

    private static func unique(_ values: [String]) -> [String] {
        var result: [String] = []
        for value in values {
            let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty, !result.contains(cleaned) else { continue }
            result.append(cleaned)
        }
        return result
    }
}

import Foundation

struct TranscriptSegment: Identifiable, Codable, Sendable {
    let id: Int
    let start: TimeInterval
    let end: TimeInterval
    let text: String
    var speaker: String = "Onbekend"
}

struct TranscriptDocument: Codable, Sendable {
    let language: String
    let segments: [TranscriptSegment]

    var text: String {
        segments.map(\.text).joined(separator: " ")
    }
}

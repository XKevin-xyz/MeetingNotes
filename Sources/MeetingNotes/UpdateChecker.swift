import AppKit
import Foundation

struct MeetingNotesUpdate: Decodable, Identifiable, Sendable {
    let version: String
    let build: Int
    let downloadURL: URL
    let notes: String?

    var id: String { "\(version)-\(build)" }
}

@MainActor
@Observable
final class UpdateChecker {
    enum State {
        case idle
        case checking
        case notConfigured
        case upToDate
        case available(MeetingNotesUpdate)
        case failed(String)
    }

    private(set) var state: State = .idle

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.2.0"
    }

    var currentBuild: Int {
        Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "2") ?? 2
    }

    private var feedURL: URL? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "MNUpdateFeedURL") as? String,
              !value.isEmpty else { return nil }
        return URL(string: value)
    }

    func check() async {
        guard let feedURL else {
            state = .notConfigured
            return
        }

        state = .checking

        do {
            var request = URLRequest(url: feedURL)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                throw UpdateError.invalidResponse
            }

            let update = try JSONDecoder().decode(MeetingNotesUpdate.self, from: data)
            state = isNewer(update) ? .available(update) : .upToDate
        } catch is CancellationError {
            state = .idle
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func openDownload(_ update: MeetingNotesUpdate) {
        NSWorkspace.shared.open(update.downloadURL)
    }

    private func isNewer(_ update: MeetingNotesUpdate) -> Bool {
        if update.build != currentBuild {
            return update.build > currentBuild
        }
        return compareVersions(update.version, currentVersion) == .orderedDescending
    }

    private func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = lhs.split(separator: ".").map { Int($0) ?? 0 }
        let right = rhs.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(left.count, right.count) {
            let leftPart = index < left.count ? left[index] : 0
            let rightPart = index < right.count ? right[index] : 0
            if leftPart != rightPart {
                return leftPart > rightPart ? .orderedDescending : .orderedAscending
            }
        }
        return .orderedSame
    }
}

private enum UpdateError: LocalizedError {
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "De updatebron gaf geen geldig antwoord."
        }
    }
}

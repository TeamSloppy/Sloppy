import Foundation
import Protocols

struct PullRequestAutomationStore {
    struct Pending: Codable, Sendable {
        var event: PullRequestEvent
        var messageID = UUID().uuidString
        var session: CodeReviewAutomationSession?
        var content: String?
        var allowsEdits: Bool?
    }

    struct Subscription: Codable, Sendable {
        var projectID: String
        var settings: PullRequestAutomationSettings
        var generation = UUID()
        var sourceID: String?
        var repositoryPath: String?
        var since = Date()
        var cursor: JSONValue?
        var lastPollAt: Date?
        var lastError: String?
        var latestSession: CodeReviewAutomationSession?
        var pending: [Pending] = []
        var accepted: Set<String> = []
        var feedback: [String: PullRequestEvent] = [:]
        var replies: [String: PullRequestCommentReplyReceipt] = [:]
        var attemptedReplies: Set<String> = []

        mutating func receive(_ events: [PullRequestEvent]) {
            var seen = accepted.union(pending.map(\.event.id))
            for event in events where seen.insert(event.id).inserted {
                pending.append(Pending(event: event))
            }
        }

        var status: PullRequestAutomationStatus {
            .init(settings: settings, lastPollAt: lastPollAt, lastError: lastError,
                  pendingEvents: pending.count, latestSession: latestSession)
        }
    }

    let root: URL

    func load(_ projectID: String) throws -> Subscription? {
        let url = file(projectID)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try decode(url)
    }

    func list() throws -> [Subscription] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .map(decode)
    }

    func save(_ subscription: Subscription) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try JSONEncoder().encode(subscription).write(to: file(subscription.projectID), options: .atomic)
    }

    private func decode(_ url: URL) throws -> Subscription {
        try JSONDecoder().decode(Subscription.self, from: Data(contentsOf: url))
    }

    private func file(_ projectID: String) -> URL {
        root.appendingPathComponent(TaskSyncCrypto.sha256Hex(Data(projectID.utf8)) + ".json")
    }
}

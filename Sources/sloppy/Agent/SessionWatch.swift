import Foundation
import Protocols

struct SessionWatch: Codable, Sendable, Equatable {
    enum Target: Codable, Sendable, Equatable {
        case process(id: String)
        case mcp(MCPStatus)
    }

    struct MCPStatus: Codable, Sendable, Equatable {
        let tool: String
        let arguments: [String: JSONValue]
        let statusPath: [String]
        let pending: [String]
        let success: [String]
        let failure: [String]
        let detailPath: [String]?

        func evaluate(_ output: JSONValue) -> Observation {
            guard let content = output.asObject?["content"]?.asArray,
                  let document = content.lazy.compactMap({ item in
                      item.asObject?["text"]?.asString.flatMap {
                          try? JSONDecoder().decode(JSONValue.self, from: Data($0.utf8))
                      }
                  }).first,
                  let status = value(at: statusPath, in: document)?.asString else {
                return .finished(.init(state: .unavailable, detail: "The status tool did not return the configured JSON status field."))
            }
            if pending.contains(status) { return .pending(status) }
            let state: Outcome.State
            if success.contains(status) {
                state = .succeeded
            } else if failure.contains(status) {
                state = .failed
            } else {
                return .finished(.init(state: .unavailable, detail: "Unrecognized job status: \(status.prefix(200))."))
            }
            let detail = detailPath.flatMap { value(at: $0, in: document)?.asString }
            return .finished(.init(state: state, detail: "Status: \(status.prefix(200))." + (detail.map { "\n\($0.suffix(1400))" } ?? "")))
        }

        private func value(at path: [String], in document: JSONValue) -> JSONValue? {
            path.reduce(Optional(document)) { item, component in
                if let object = item?.asObject { return object[component] }
                guard let index = Int(component), index >= 0, let array = item?.asArray,
                      index < array.count else { return nil }
                return array[index]
            }
        }
    }

    struct Outcome: Codable, Sendable, Equatable {
        enum State: String, Codable, Sendable {
            case succeeded, failed, unavailable, cancelled
        }
        let state: State
        let detail: String

        var label: String {
            switch state {
            case .succeeded: "Job succeeded"
            case .failed: "Job failed"
            case .unavailable: "Job status unavailable"
            case .cancelled: "Job watch cancelled"
            }
        }
    }

    enum Observation: Sendable, Equatable {
        case pending(String)
        case retry
        case finished(Outcome)
    }

    let id: String
    let agentID: String
    let sessionID: String
    let title: String
    let target: Target
    let intervalSeconds: Int
    var nextCheck: Date
    var lastStatus: String?
    var consecutiveErrors = 0
    var outcome: Outcome?

    mutating func apply(_ observation: Observation, now: Date) {
        switch observation {
        case .pending(let status):
            lastStatus = status
            consecutiveErrors = 0
        case .retry:
            consecutiveErrors = min(consecutiveErrors + 1, 5)
        case .finished(let outcome):
            self.outcome = outcome
            nextCheck = now
            return
        }
        nextCheck = now.addingTimeInterval(Double(min(3600, intervalSeconds * (1 << consecutiveErrors))))
    }
}

/// Owned by CoreService. Each accepted checkpoint is atomic and independently recoverable.
struct SessionWatchStore: Sendable {
    let directory: URL

    init(root: URL) {
        directory = root.appendingPathComponent("session-messages/watches", isDirectory: true)
    }

    func save(_ watch: SessionWatch) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(watch).write(to: url(for: watch.id), options: .atomic)
    }

    func remove(_ watch: SessionWatch) throws {
        try FileManager.default.removeItem(at: url(for: watch.id))
    }

    func ids() throws -> [String] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(atPath: directory.path).compactMap { file in
            guard file.hasSuffix(".json") else { return nil }
            let id = String(file.dropLast(5))
            return UUID(uuidString: id) != nil ? id : nil
        }
    }

    func load(_ id: String) throws -> SessionWatch {
        let watch = try JSONDecoder().decode(SessionWatch.self, from: Data(contentsOf: url(for: id)))
        guard watch.id == id, (5...3600).contains(watch.intervalSeconds), (0...5).contains(watch.consecutiveErrors) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return watch
    }

    private func url(for id: String) -> URL {
        directory.appendingPathComponent(id + ".json")
    }
}

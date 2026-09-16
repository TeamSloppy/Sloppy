import Foundation
import Protocols

struct WorkspaceBrowserBinding: Codable, Sendable, Equatable {
    var bridgeId: String
    var agentId: String
    var sessionId: String
}

struct WorkspaceBrowserCommand: Codable, Sendable {
    var id: String
    var name: String
    var input: JSONValue
}

struct WorkspaceBrowserCommands: Codable, Sendable {
    var commands: [WorkspaceBrowserCommand]
}

struct WorkspaceBrowserCompletion: Codable, Sendable {
    var binding: WorkspaceBrowserBinding
    var commandId: String
    var data: JSONValue?
    var imageBase64: String?
    var error: String?
}

enum WorkspaceBrowserBridgeError: Error, LocalizedError, Equatable {
    case unavailable, conflict, unknownCommand, timedOut, commandFailed(String)
    var errorDescription: String? {
        switch self {
        case .unavailable: "The task's in-app browser is disconnected. Reopen this task in Sloppy."
        case .conflict: "This task already has a browser connected in another client."
        case .unknownCommand: "The browser command is expired or belongs to another client."
        case .timedOut: "The in-app browser command timed out. Read the page before retrying an action."
        case .commandFailed(let message): message
        }
    }
}

/// Client-initiated polling works for remote Core and never exposes a local listening port.
actor WorkspaceBrowserBridgeService {
    private struct Connection {
        var binding: WorkspaceBrowserBinding
        var lastSeen: Date
    }
    private struct Pending {
        var binding: WorkspaceBrowserBinding
        var command: WorkspaceBrowserCommand
        var continuation: CheckedContinuation<JSONValue, Error>
        var timeout: Task<Void, Never>
    }
    private var connections: [String: Connection] = [:]
    // A disconnected in-app session must not silently start a different browser on Core.
    private var assignedSessions: Set<String> = []
    private var pending: [String: Pending] = [:]
    private var queues: [String: [String]] = [:]
    private let lease: TimeInterval
    private let timeout: Duration

    init(lease: TimeInterval = 60, timeout: Duration = .seconds(25)) {
        self.lease = lease
        self.timeout = timeout
    }

    func register(_ binding: WorkspaceBrowserBinding) throws {
        guard !binding.sessionId.isEmpty, !binding.agentId.isEmpty,
              UUID(uuidString: binding.bridgeId) != nil else { throw WorkspaceBrowserBridgeError.unavailable }
        if let existing = connections[binding.sessionId], existing.binding != binding {
            guard Date().timeIntervalSince(existing.lastSeen) > lease else { throw WorkspaceBrowserBridgeError.conflict }
            disconnect(existing.binding)
        }
        connections[binding.sessionId] = Connection(binding: binding, lastSeen: Date())
        assignedSessions.insert(binding.sessionId)
    }

    func isAssigned(sessionID: String) -> Bool { assignedSessions.contains(sessionID) }

    func status(sessionID: String) -> JSONValue {
        let connected = connections[sessionID].map { Date().timeIntervalSince($0.lastSeen) <= lease } ?? false
        return .object(["running": .bool(connected), "surface": .string("in_app"),
                        "connected": .bool(connected), "hint": .string("Use browser.read to inspect the live page and its element selectors.")])
    }

    func poll(_ binding: WorkspaceBrowserBinding) throws -> WorkspaceBrowserCommands {
        try validate(binding)
        connections[binding.sessionId]?.lastSeen = Date()
        let ids = queues.removeValue(forKey: binding.bridgeId) ?? []
        return WorkspaceBrowserCommands(commands: ids.compactMap { pending[$0]?.command })
    }

    func complete(_ result: WorkspaceBrowserCompletion) throws {
        try validate(result.binding)
        guard let command = pending[result.commandId], command.binding == result.binding else {
            throw WorkspaceBrowserBridgeError.unknownCommand
        }
        pending.removeValue(forKey: result.commandId)
        command.timeout.cancel()
        if let error = result.error {
            command.continuation.resume(throwing: WorkspaceBrowserBridgeError.commandFailed(error))
        } else {
            var data = result.data?.asObject ?? [:]
            if let image = result.imageBase64 { data["imageBase64"] = .string(image) }
            data["surface"] = .string("in_app")
            command.continuation.resume(returning: .object(data))
        }
    }

    func disconnect(_ binding: WorkspaceBrowserBinding) {
        guard connections[binding.sessionId]?.binding == binding else { return }
        connections.removeValue(forKey: binding.sessionId)
        queues.removeValue(forKey: binding.bridgeId)
        for id in pending.keys.filter({ pending[$0]?.binding == binding }) {
            finish(id, error: WorkspaceBrowserBridgeError.unavailable)
        }
    }

    func run(sessionID: String, name: String, input: JSONValue = .object([:])) async throws -> JSONValue {
        guard let connection = connections[sessionID], Date().timeIntervalSince(connection.lastSeen) <= lease else {
            throw WorkspaceBrowserBridgeError.unavailable
        }
        // One action at a time per page; concurrent tasks have independent pages.
        guard !pending.values.contains(where: { $0.binding.sessionId == sessionID }) else {
            throw WorkspaceBrowserBridgeError.commandFailed("A browser action is already running. Wait for its result.")
        }
        let id = UUID().uuidString
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                let command = WorkspaceBrowserCommand(id: id, name: name, input: input)
                let timer = Task {
                    do { try await Task.sleep(for: timeout) } catch { return }
                    finish(id, error: WorkspaceBrowserBridgeError.timedOut)
                }
                pending[id] = Pending(binding: connection.binding, command: command, continuation: continuation, timeout: timer)
                queues[connection.binding.bridgeId, default: []].append(id)
            }
        } onCancel: {
            Task { await self.finish(id, error: CancellationError()) }
        }
    }

    func cleanup(sessionID: String) {
        if let binding = connections[sessionID]?.binding { disconnect(binding) }
    }

    func shutdown() {
        for connection in Array(connections.values) { disconnect(connection.binding) }
    }

    private func validate(_ binding: WorkspaceBrowserBinding) throws {
        guard connections[binding.sessionId]?.binding == binding else { throw WorkspaceBrowserBridgeError.unavailable }
    }

    private func finish(_ id: String, error: Error) {
        guard let command = pending.removeValue(forKey: id) else { return }
        queues[command.binding.bridgeId]?.removeAll { $0 == id }
        command.timeout.cancel()
        command.continuation.resume(throwing: error)
    }
}

import Foundation
import Protocols

enum SafariBridgeError: Error, LocalizedError, Sendable, Equatable {
    case bridgeUnavailable
    case commandNotFound
    case commandFailed(String)
    case commandTimedOut

    var errorDescription: String? {
        switch self {
        case .bridgeUnavailable:
            return "SloppySafari bridge is not connected."
        case .commandNotFound:
            return "Safari bridge command was not found."
        case .commandFailed(let message):
            return "Safari bridge command failed: \(message)"
        case .commandTimedOut:
            return "Safari bridge command timed out."
        }
    }

    var code: String {
        switch self {
        case .bridgeUnavailable:
            return "safari_bridge_unavailable"
        case .commandNotFound:
            return "safari_command_not_found"
        case .commandFailed:
            return "safari_command_failed"
        case .commandTimedOut:
            return "safari_command_timed_out"
        }
    }
}

actor SafariBridgeService {
    private struct BridgeState {
        var id: String
        var tabs: [SafariBridgeTab]
        var capabilities: [String]
        var lastSeenAt: Date
    }

    private struct PendingCommand {
        var bridgeId: String
        var command: SafariBridgeCommand
        var continuation: CheckedContinuation<JSONValue, Error>
    }

    private var bridges: [String: BridgeState] = [:]
    private var activeBridgeId: String?
    private var queuedCommands: [String: [SafariBridgeCommand]] = [:]
    private var pendingCommands: [String: PendingCommand] = [:]
    private let commandTimeoutMs: Int
    private let commandPollIntervalMs: Int

    init(commandTimeoutMs: Int = 20_000, commandPollIntervalMs: Int = 1_000) {
        self.commandTimeoutMs = commandTimeoutMs
        self.commandPollIntervalMs = commandPollIntervalMs
    }

    func register(_ request: SafariBridgeRegisterRequest) -> SafariBridgeRegisterResponse {
        let bridgeId = normalizedBridgeID(request.bridgeId) ?? "safari-\(UUID().uuidString.lowercased())"
        bridges[bridgeId] = BridgeState(
            id: bridgeId,
            tabs: request.tabs,
            capabilities: request.capabilities,
            lastSeenAt: Date()
        )
        activeBridgeId = bridgeId
        return SafariBridgeRegisterResponse(
            bridgeId: bridgeId,
            commandPollIntervalMs: commandPollIntervalMs
        )
    }

    func statusPayload() -> JSONValue {
        guard let bridge = activeBridge else {
            return .object([
                "connected": .bool(false),
                "tabs": .array([]),
                "capabilities": .array([]),
            ])
        }
        return .object([
            "connected": .bool(true),
            "bridgeId": .string(bridge.id),
            "tabs": .array(bridge.tabs.map(tabPayload)),
            "capabilities": .array(bridge.capabilities.map { .string($0) }),
            "lastSeenAt": .string(ISO8601DateFormatter().string(from: bridge.lastSeenAt)),
        ])
    }

    func pollCommands(bridgeId: String, limit: Int = 10) -> SafariBridgeCommandListResponse {
        let id = bridgeId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else {
            return SafariBridgeCommandListResponse()
        }
        var queue = queuedCommands[id] ?? []
        let commands = Array(queue.prefix(max(1, limit)))
        queue.removeFirst(commands.count)
        queuedCommands[id] = queue
        return SafariBridgeCommandListResponse(commands: commands)
    }

    func completeCommand(_ request: SafariBridgeCommandResultRequest) throws {
        guard let pending = pendingCommands.removeValue(forKey: request.commandId) else {
            throw SafariBridgeError.commandNotFound
        }
        if request.ok {
            pending.continuation.resume(returning: request.data ?? .object([:]))
        } else {
            pending.continuation.resume(throwing: SafariBridgeError.commandFailed(request.error ?? "unknown"))
        }
    }

    func runCommand(name: String, input: JSONValue = .object([:])) async throws -> JSONValue {
        guard let bridge = activeBridge else {
            throw SafariBridgeError.bridgeUnavailable
        }
        let command = SafariBridgeCommand(
            id: "safari-command-\(UUID().uuidString.lowercased())",
            name: name,
            input: input
        )
        return try await withCheckedThrowingContinuation { continuation in
            pendingCommands[command.id] = PendingCommand(
                bridgeId: bridge.id,
                command: command,
                continuation: continuation
            )
            queuedCommands[bridge.id, default: []].append(command)
            Task {
                try? await Task.sleep(for: .milliseconds(commandTimeoutMs))
                await timeoutCommand(command.id)
            }
        }
    }

    private var activeBridge: BridgeState? {
        activeBridgeId.flatMap { bridges[$0] }
    }

    private func timeoutCommand(_ commandId: String) {
        guard let pending = pendingCommands.removeValue(forKey: commandId) else {
            return
        }
        queuedCommands[pending.bridgeId]?.removeAll { $0.id == commandId }
        pending.continuation.resume(throwing: SafariBridgeError.commandTimedOut)
    }

    private func normalizedBridgeID(_ raw: String?) -> String? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func tabPayload(_ tab: SafariBridgeTab) -> JSONValue {
        .object([
            "id": tab.id.map { .number(Double($0)) } ?? .null,
            "url": .string(tab.url),
            "title": tab.title.map { .string($0) } ?? .null,
            "active": .bool(tab.active),
            "currentWindow": .bool(tab.currentWindow),
        ])
    }
}

import Foundation
import Protocols
import AgentRuntime

// MARK: - Path resolution

extension ToolContext {
    func resolveReadablePath(_ path: String) -> URL? {
        resolvePath(path, extraRoots: policy.guardrails.allowedWriteRoots)
    }

    func resolveWritablePath(_ path: String) -> URL? {
        resolvePath(path, extraRoots: policy.guardrails.allowedWriteRoots)
    }

    func resolveExecCwd(_ path: String) -> URL? {
        resolvePath(path, extraRoots: policy.guardrails.allowedExecRoots)
    }

    private func resolvePath(_ path: String, extraRoots: [String]) -> URL? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let candidate: URL
        if trimmed.hasPrefix("/") {
            candidate = URL(fileURLWithPath: trimmed)
        } else {
            candidate = workspaceRootURL.appendingPathComponent(trimmed)
        }

        let resolved = candidate.resolvingSymlinksInPath().standardizedFileURL
        let roots = [workspaceRootURL] + extraRoots.map { raw -> URL in
            raw.hasPrefix("/") ? URL(fileURLWithPath: raw) : workspaceRootURL.appendingPathComponent(raw)
        }

        for root in roots {
            let rootResolved = root.resolvingSymlinksInPath().standardizedFileURL
            let rootPath = rootResolved.path.hasSuffix("/") ? rootResolved.path : rootResolved.path + "/"
            if resolved.path == rootResolved.path || resolved.path.hasPrefix(rootPath) {
                return resolved
            }
        }
        return nil
    }
}

// MARK: - Command guard

func isCommandAllowed(_ command: String, deniedPrefixes: [String]) -> Bool {
    let normalized = command.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !normalized.isEmpty else { return false }
    let basename = URL(fileURLWithPath: normalized).lastPathComponent
    let candidates = [normalized, basename]
    for prefix in deniedPrefixes.map({ $0.lowercased() }) {
        if candidates.contains(where: { $0 == prefix || $0.hasPrefix(prefix + " ") }) {
            return false
        }
    }
    return true
}

// MARK: - Process execution

func runForegroundProcess(
    command: String,
    arguments: [String],
    cwd: URL?,
    timeoutMs: Int,
    maxOutputBytes: Int
) async throws -> JSONValue {
    let process = Process()
    let stdout = Pipe()
    let stderr = Pipe()

    if command.hasPrefix("/") || command.hasPrefix("./") || command.hasPrefix("../") {
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments
    } else {
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [command] + arguments
    }

    process.standardOutput = stdout
    process.standardError = stderr
    process.currentDirectoryURL = cwd
    try process.run()

    let didTimeout = await raceProcessAgainstTimeout(process: process, timeoutMs: timeoutMs)
    if didTimeout, process.isRunning {
        process.terminate()
        process.waitUntilExit()
    }

    let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
    let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()

    return .object([
        "command": .string(command),
        "arguments": .array(arguments.map { .string($0) }),
        "exitCode": .number(Double(process.terminationStatus)),
        "timedOut": .bool(didTimeout),
        "stdout": .string(String(decoding: trimData(stdoutData, maxBytes: maxOutputBytes), as: UTF8.self)),
        "stderr": .string(String(decoding: trimData(stderrData, maxBytes: maxOutputBytes), as: UTF8.self))
    ])
}

private func raceProcessAgainstTimeout(process: Process, timeoutMs: Int) async -> Bool {
    await withTaskGroup(of: Bool.self) { group in
        group.addTask {
            process.waitUntilExit()
            return false
        }
        group.addTask {
            try? await Task.sleep(nanoseconds: UInt64(max(1, timeoutMs)) * 1_000_000)
            return true
        }
        let first = await group.next() ?? false
        group.cancelAll()
        return first
    }
}

private func trimData(_ data: Data, maxBytes: Int) -> Data {
    data.count <= maxBytes ? data : data.prefix(maxBytes)
}

// MARK: - String / argument utilities

func sessionChannelID(agentID: String, sessionID: String) -> String {
    "agent:\(agentID):session:\(sessionID)"
}

func trimmedArg(_ key: String, from arguments: [String: JSONValue]) -> String? {
    let s = arguments[key]?.asString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return s.isEmpty ? nil : s
}

func optionalLabel(_ value: String?) -> String {
    let s = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return s.isEmpty ? "(none)" : s
}

func occurrences(of needle: String, in haystack: String) -> Int {
    guard !needle.isEmpty else { return 0 }
    var count = 0
    var searchRange: Range<String.Index>? = haystack.startIndex..<haystack.endIndex
    while let range = haystack.range(of: needle, options: [], range: searchRange) {
        count += 1
        searchRange = range.upperBound..<haystack.endIndex
    }
    return count
}

// MARK: - JSON encoding

func encodeJSONValue<T: Encodable>(_ value: T) -> JSONValue {
    do {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        return try JSONDecoder().decode(JSONValue.self, from: data)
    } catch {
        return .null
    }
}

// MARK: - Session status

func statusFrom(events: [AgentSessionEvent]) -> String {
    for event in events.reversed() where event.type == .runStatus {
        if let stage = event.runStatus?.stage.rawValue {
            return stage
        }
    }
    return "idle"
}

// MARK: - Memory scope

func parseMemoryScope(from arguments: [String: JSONValue]) -> MemoryScope? {
    if let scopeObj = arguments["scope"]?.asObject {
        let scopeType = scopeObj["type"]?.asString?.lowercased()
        let scopeID = scopeObj["id"]?.asString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let scopeType, let type = MemoryScopeType(rawValue: scopeType), !scopeID.isEmpty else {
            return nil
        }
        return MemoryScope(
            type: type,
            id: scopeID,
            channelId: scopeObj["channel_id"]?.asString,
            projectId: scopeObj["project_id"]?.asString,
            agentId: scopeObj["agent_id"]?.asString
        )
    }

    let scopeType = arguments["scope_type"]?.asString?.lowercased()
    let scopeID = arguments["scope_id"]?.asString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard let scopeType, let type = MemoryScopeType(rawValue: scopeType), !scopeID.isEmpty else {
        return nil
    }
    return MemoryScope(type: type, id: scopeID)
}

// MARK: - Project helpers (pure functions)

func findProjectForChannel(store: any PersistenceStore, channelId: String, topicId: String?) async -> ProjectRecord? {
    let projects = await store.listProjects()
    if let topicId, !topicId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        let compositeId = "\(channelId):\(topicId)"
        if let found = projects.sorted(by: { $0.createdAt < $1.createdAt })
            .first(where: { $0.channels.contains(where: { $0.channelId == compositeId }) }) {
            return found
        }
    }
    return projects.sorted(by: { $0.createdAt < $1.createdAt })
        .first(where: { $0.channels.contains(where: { $0.channelId == channelId }) })
}

func normalizeTaskRef(_ raw: String) -> String? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    let token = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
    let t = token.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !t.isEmpty else { return nil }
    let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.")
    guard t.rangeOfCharacter(from: allowed.inverted) == nil, t.count <= 180 else { return nil }
    return t
}

func findTask(reference: String, in project: ProjectRecord) throws -> ProjectTask {
    let lower = reference.lowercased()
    guard let task = project.tasks.first(where: { $0.id == reference || $0.id.lowercased() == lower }) else {
        throw CoreService.ProjectError.notFound
    }
    return task
}

func taskJSONValue(_ task: ProjectTask) -> JSONValue {
    .object([
        "id": .string(task.id),
        "title": .string(task.title),
        "description": .string(task.description),
        "priority": .string(task.priority),
        "status": .string(task.status),
        "actorId": task.actorId.map { .string($0) } ?? .null,
        "teamId": task.teamId.map { .string($0) } ?? .null,
        "claimedActorId": task.claimedActorId.map { .string($0) } ?? .null,
        "claimedAgentId": task.claimedAgentId.map { .string($0) } ?? .null,
        "swarmId": task.swarmId.map { .string($0) } ?? .null,
        "swarmTaskId": task.swarmTaskId.map { .string($0) } ?? .null,
        "swarmParentTaskId": task.swarmParentTaskId.map { .string($0) } ?? .null,
        "swarmDependencyIds": task.swarmDependencyIds.map { .array($0.map { .string($0) }) } ?? .null,
        "swarmDepth": task.swarmDepth.map { .number(Double($0)) } ?? .null,
        "swarmActorPath": task.swarmActorPath.map { .array($0.map { .string($0) }) } ?? .null,
        "createdAt": .string(ISO8601DateFormatter().string(from: task.createdAt)),
        "updatedAt": .string(ISO8601DateFormatter().string(from: task.updatedAt))
    ])
}

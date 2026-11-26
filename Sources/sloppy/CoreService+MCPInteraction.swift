import Foundation
import Protocols

extension CoreService {
    func mcpInteraction(agentID: String, sessionID: String, serverID: String, toolName: String,
                        registry: MCPClientRegistry) async -> MCPToolInteraction? {
        guard let detail = try? getAgentSession(agentID: agentID, sessionID: sessionID),
              detail.summary.kind == .chat,
              let user = detail.events.reversed().compactMap(\.message).first(where: { $0.role == .user }) else { return nil }

        let allowURL = user.userId == "dashboard"
        let progressToken = UUID().uuidString
        let canPersistTasks = registry === mcpRegistry
        var capabilities: [String: JSONValue] = [:]
        if allowURL { capabilities["elicitation"] = .object(["form": .object([:]), "url": .object([:])]) }
        if canPersistTasks { capabilities["extensions"] = .object([MCPToolInteraction.tasksID: .object([:])]) }

        return MCPToolInteraction(capabilities: capabilities, progressToken: progressToken, notification: { [weak self] packet in
            guard packet["method"]?.asString == "notifications/progress", let params = packet["params"]?.asObject,
                  params["progressToken"]?.asString == progressToken, let progress = params["progress"]?.asNumber else { return }
            let total = params["total"]?.asNumber.map { " / \($0)" } ?? ""
            let detail = params["message"]?.asString.map { " · \(String($0.prefix(512)))" } ?? ""
            Task { await self?.reportSessionRunStatus(agentID: agentID, sessionID: sessionID,
                status: .init(stage: .searching, label: "MCP \(toolName)", details: "\(progress)\(total)\(detail)")) }
        }, answer: { [weak self] requests in
            guard let self else { throw CancellationError() }
            return try await self.answerMCPRequests(requests, agentID: agentID, sessionID: sessionID, serverID: serverID, allowURL: allowURL)
        }, registerTask: { [weak self] result, config in
            guard let self, canPersistTasks else { throw MCPRegistryError.invalidResult("MCP Tasks unavailable for this connection.") }
            return try await self.registerMCPTask(result, agentID: agentID, sessionID: sessionID,
                                                  serverID: serverID, toolName: toolName, config: config)
        })
    }

    private func answerMCPRequests(_ requests: [String: JSONValue], agentID: String, sessionID: String,
                                   serverID: String, allowURL: Bool) async throws -> [String: JSONValue] {
        guard requests.isEmpty || allowURL else {
            throw MCPRegistryError.invalidResult("This chat surface does not support MCP elicitation.")
        }
        guard requests.count <= 32 else { throw MCPRegistryError.invalidResult("Too many MCP input requests.") }
        var responses: [String: JSONValue] = [:]
        for key in requests.keys.sorted() {
            guard let packet = requests[key] else { continue }
            let request = try MCPElicitation(serverID: serverID, packet: packet, allowURL: allowURL).request
            responses[key] = try await awaitMCPInput(request, agentID: agentID, sessionID: sessionID)
        }
        return responses
    }

    func awaitMCPInput(_ request: PlanInputRequest, agentID: String, sessionID: String) async throws -> JSONValue {
        try Task.checkCancellation()
        let (stream, reply) = AsyncThrowingStream<JSONValue, any Error>.makeStream()
        mcpInputReplies[request.id] = reply
        defer { mcpInputReplies.removeValue(forKey: request.id) }
        let detail = try getAgentSession(agentID: agentID, sessionID: sessionID)
        let answered = Set(detail.events.compactMap { $0.inputResponse?.requestId })
        let expired = detail.events.compactMap(\.inputRequest).filter {
            $0.mode == "mcp" && !answered.contains($0.id) && mcpInputReplies[$0.id] == nil
        }
        let events = expired.map { stale in
            AgentSessionEvent(agentId: agentID, sessionId: sessionID, type: .inputResponse,
                inputResponse: .init(requestId: stale.id, status: .cancelled, answers: [], userId: "system"))
        } + [.init(agentId: agentID, sessionId: sessionID, type: .inputRequest, inputRequest: request)]
        try appendMCPEvents(agentID: agentID, sessionID: sessionID, events: events)
        let timeout = Task {
            do {
                try await Task.sleep(for: .seconds(900))
                reply.finish()
            } catch {}
        }
        defer { timeout.cancel() }
        var iterator = stream.makeAsyncIterator()
        if let result = try await iterator.next() { return result }
        try appendMCPEvents(agentID: agentID, sessionID: sessionID, events: [
            .init(agentId: agentID, sessionId: sessionID, type: .inputResponse,
                  inputResponse: .init(requestId: request.id, status: .cancelled, answers: [], userId: "system"))
        ])
        try Task.checkCancellation()
        return .object(["action": .string("cancel")])
    }

    func resolveMCPInput(agentID: String, sessionID: String, request: PlanInputRequest,
                         response: PlanInputResponse) throws -> AgentSessionMessageResponse {
        let reply = mcpInputReplies[request.id]
        let result = try MCPElicitation.wireResponse(response, for: request)
        let recorded = reply == nil
            ? PlanInputResponse(requestId: request.id, status: .cancelled, answers: [], userId: response.userId)
            : response
        let event = AgentSessionEvent(agentId: agentID, sessionId: sessionID, type: .inputResponse, inputResponse: recorded)
        let summary = try appendMCPEvents(agentID: agentID, sessionID: sessionID, events: [event])
        reply?.yield(result)
        reply?.finish()
        return AgentSessionMessageResponse(summary: summary, appendedEvents: [event], routeDecision: nil)
    }

    @discardableResult
    private func appendMCPEvents(agentID: String, sessionID: String, events: [AgentSessionEvent]) throws -> AgentSessionSummary {
        let summary = try sessionStore.appendEvents(agentID: agentID, sessionID: sessionID, events: events)
        publishLiveSessionEvents(agentID: agentID, sessionID: sessionID, summary: summary, events: events)
        return summary
    }

    private var mcpTasksDirectory: URL { workspaceRootURL.appendingPathComponent("mcp-tasks", isDirectory: true) }

    private func taskURL(_ id: String) -> URL {
        mcpTasksDirectory.appendingPathComponent(id).appendingPathExtension("json")
    }

    private func saveMCPTask(_ record: MCPRemoteTask) throws {
        try FileManager.default.createDirectory(at: mcpTasksDirectory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(record).write(to: taskURL(record.id), options: .atomic)
    }

    private func registerMCPTask(_ result: [String: JSONValue], agentID: String, sessionID: String,
                                 serverID: String, toolName: String, config: CoreConfig.MCP.Server) async throws -> MCPToolReply {
        guard let taskID = result["taskId"]?.asString, !taskID.isEmpty, taskID.utf8.count <= 4_096 else {
            throw MCPRegistryError.invalidResult("MCP server returned an invalid task handle.")
        }
        var record = MCPRemoteTask(id: UUID().uuidString, agentID: agentID, sessionID: sessionID, serverID: serverID,
                                  toolName: toolName, remoteID: taskID, serverFingerprint: try MCPRemoteTask.fingerprint(config),
                                  nextPoll: Date())
        record.update(result, now: Date())
        try saveMCPTask(record)
        startMCPTask(record)
        return MCPToolReply(content: [.text(text: "MCP task \(record.id) is registered. Its result will arrive in this session.")],
                            isError: false, structuredContent: .object([
                                "taskId": .string(record.id), "status": .string(result["status"]?.asString ?? "working")
                            ]))
    }

    func resumeMCPTasks() {
        let urls = (try? FileManager.default.contentsOfDirectory(at: mcpTasksDirectory, includingPropertiesForKeys: nil)) ?? []
        for url in urls where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url), let record = try? JSONDecoder().decode(MCPRemoteTask.self, from: data),
                  UUID(uuidString: record.id) != nil, url.lastPathComponent == taskURL(record.id).lastPathComponent else { continue }
            startMCPTask(record)
        }
    }

    func stopMCPTasks() async {
        let running = Array(mcpTaskWorkers.values)
        for task in running { task.cancel() }
        for task in running { await task.value }
    }

    private func startMCPTask(_ record: MCPRemoteTask) {
        guard mcpTaskWorkers[record.id] == nil else { return }
        mcpTaskWorkers[record.id] = Task { [weak self] in await self?.pollMCPTask(record) }
    }

    func cancelMCPTask(agentID: String, sessionID: String, id: String) async throws {
        guard UUID(uuidString: id) != nil else { throw AgentSessionError.invalidPayload }
        let record = try JSONDecoder().decode(MCPRemoteTask.self, from: Data(contentsOf: taskURL(id)))
        guard record.agentID == agentID, record.sessionID == sessionID else { throw AgentSessionError.invalidPayload }
        _ = try await mcpTaskRequest("tasks/cancel", record: record)
    }

    private func mcpTaskRequest(_ method: String, record: MCPRemoteTask,
                                responses: [String: JSONValue]? = nil) async throws -> [String: JSONValue] {
        var params: [String: JSONValue] = ["taskId": .string(record.remoteID)]
        params["inputResponses"] = responses.map(JSONValue.object)
        let connection = try await mcpRegistry.connection(for: record.serverID)
        guard try MCPRemoteTask.fingerprint(connection.config) == record.serverFingerprint else {
            throw MCPRegistryError.invalidConfiguration("MCP task server settings have changed.")
        }
        return try await connection.extensionRequest(method, extensionID: MCPToolInteraction.tasksID, params: params,
            capabilities: ["extensions": .object([MCPToolInteraction.tasksID: .object([:])])])
    }

    private func pollMCPTask(_ initial: MCPRemoteTask) async {
        var record = initial
        var retryDelay: Double = 1
        defer { mcpTaskWorkers.removeValue(forKey: record.id) }
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: .seconds(max(0, record.nextPoll.timeIntervalSinceNow)))
                if let terminal = record.terminal {
                    try deliverMCPTask(record, result: terminal)
                    try FileManager.default.removeItem(at: taskURL(record.id))
                    return
                }
                if let expires = record.expiresAt, expires <= Date() {
                    record.terminal = ["status": .string("expired")]
                    try saveMCPTask(record)
                    continue
                }
                let result = try await mcpTaskRequest("tasks/get", record: record)
                guard result["resultType"]?.asString == "complete", result["taskId"]?.asString == record.remoteID,
                      ["working", "input_required", "completed", "failed", "cancelled"].contains(result["status"]?.asString ?? "") else {
                    throw MCPRegistryError.invalidResult("MCP task status response is invalid.")
                }
                record.update(result, now: Date())
                if result["status"]?.asString == "input_required", let requests = result["inputRequests"]?.asObject {
                    let detail = try getAgentSession(agentID: record.agentID, sessionID: record.sessionID)
                    let user = detail.events.reversed().compactMap(\.message).first { $0.role == .user }
                    let unanswered = requests.filter { record.inputResponses[$0.key] == nil }
                    let answers = try await answerMCPRequests(unanswered, agentID: record.agentID, sessionID: record.sessionID,
                                                              serverID: record.serverID, allowURL: user?.userId == "dashboard")
                    record.inputResponses.merge(answers, uniquingKeysWith: { existing, _ in existing })
                    try saveMCPTask(record)
                    let responses = record.inputResponses.filter { requests[$0.key] != nil }
                    if !responses.isEmpty { _ = try await mcpTaskRequest("tasks/update", record: record, responses: responses) }
                } else {
                    record.inputResponses.removeAll()
                }
                try saveMCPTask(record)
                retryDelay = 1
            } catch is CancellationError {
                return
            } catch {
                logger.warning("MCP task polling will retry", metadata: ["task": "\(record.id)", "server": "\(record.serverID)"])
                record.nextPoll = Date().addingTimeInterval(retryDelay)
                retryDelay = min(60, retryDelay * 2)
            }
        }
    }

    private func deliverMCPTask(_ record: MCPRemoteTask, result: [String: JSONValue]) throws {
        let detail = try getAgentSession(agentID: record.agentID, sessionID: record.sessionID)
        guard !detail.events.contains(where: { $0.id == record.id }) else { return }
        let status = result["status"]?.asString ?? "failed"
        let payload: JSONValue = .object([
            "taskId": .string(record.id), "server": .string(record.serverID), "status": .string(status),
            "result": result["result"] ?? .null, "error": result["error"] ?? .null
        ])
        let ok = status == "completed" && result["result"]?.asObject?["isError"]?.asBool != true
        let callID = record.id + "-call"
        try appendMCPEvents(agentID: record.agentID, sessionID: record.sessionID, events: [
            .init(id: callID, agentId: record.agentID, sessionId: record.sessionID, type: .toolCall,
                  toolCall: .init(tool: record.toolName, arguments: ["taskId": .string(record.id)], reason: "MCP task result")),
            .init(id: record.id, agentId: record.agentID, sessionId: record.sessionID, type: .toolResult,
                  toolResult: .init(tool: record.toolName, ok: ok, data: payload, callEventId: callID))
        ])
    }
}

struct MCPActiveSkillKey: Hashable {
    let sessionID: String
    let serverID: String
    let uri: String
    let connection: ObjectIdentifier
    let configurationFingerprint: String
}

extension CoreService {
    func useMCPSkill(agentID: String, sessionID: String, serverID: String, uri: String,
                     fileURI: String?, registry: MCPClientRegistry) async throws -> JSONValue {
        let detail = try getAgentSession(agentID: agentID, sessionID: sessionID)
        guard detail.summary.kind == .chat else {
            throw MCPRegistryError.invalidResult("MCP skill approval requires an interactive chat.")
        }
        let (skill, connection) = try await registry.remoteSkill(serverID: serverID, uri: uri)
        let key = MCPActiveSkillKey(sessionID: sessionID, serverID: serverID, uri: uri,
            connection: ObjectIdentifier(connection), configurationFingerprint: try MCPRemoteTask.fingerprint(connection.config))
        let isActive = mcpActiveSkills[key] == skill
        let target = fileURI ?? uri
        guard skill.files[target] != nil, isActive || target == uri else {
            throw MCPRegistryError.invalidResult("Activate the skill before reading files from its manifest.")
        }
        if !isActive {
            let name = skill.frontmatter["name"]?.asString ?? ""
            let description = String((skill.frontmatter["description"]?.asString ?? "").prefix(2_000))
            let input = PlanInputRequest(mode: "mcp", title: "Activate MCP skill from \(serverID)",
                questions: [.init(id: "response", question: "\(name)\n\(description)",
                    options: [.init(id: "accept", label: "Activate skill"), .init(id: "decline", label: "Decline")],
                    allowCustomAnswer: false)])
            let answer = try await awaitMCPInput(input, agentID: agentID, sessionID: sessionID)
            guard answer.asObject?["action"]?.asString == "accept" else { throw AgentSessionError.invalidPayload }
        }
        guard try await registry.connection(for: serverID) === connection else { throw CancellationError() }
        let contents = try await connection.readResource(uri: target)
        let bytes = try skill.verifiedFile(target, contents: contents)
        mcpActiveSkills[key] = skill
        var result: [String: JSONValue] = ["server": .string(serverID), "uri": .string(target),
            "files": .array(skill.files.keys.sorted().map(JSONValue.string))]
        result["mimeType"] = contents.first?.mimeType.map(JSONValue.string)
        if let text = String(data: bytes, encoding: .utf8) {
            result["content"] = .string(text)
        } else {
            result["blob"] = .string(bytes.base64EncodedString())
        }
        return .object(result)
    }
}

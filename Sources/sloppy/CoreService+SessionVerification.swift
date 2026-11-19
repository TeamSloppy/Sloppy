import Foundation
import Protocols

extension CoreService {
    private struct SessionVerificationProfile: Decodable {
        var projectId: String
        var alias: String
        var nodeId: String
        var commit: String
        var tree: String
        var executable: String
        var operation: String?
    }

    static func isSessionVerificationCommand(_ content: String) -> Bool {
        content.split(maxSplits: 1, whereSeparator: \.isWhitespace).first == "/verify"
    }

    /// An operator can register a fixed check for an already reviewed commit.
    /// Chat text never supplies a command, a destination, or executable arguments.
    func runSessionVerificationCommand(
        agentID: String, sessionID: String, request: AgentSessionPostMessageRequest
    ) async throws -> AgentSessionMessageResponse {
        let parts = request.content.split(whereSeparator: \.isWhitespace).map(String.init)
        let detail = try getAgentSession(agentID: agentID, sessionID: sessionID)
        guard parts.count == 3, let projectID = detail.summary.projectId,
              !request.spawnSubSession, request.attachments.isEmpty, !detail.summary.isWorker,
              detail.summary.parentSessionId == nil else { throw AgentSessionError.invalidPayload }
        if detail.summary.kind == .longChat,
           try getLongChat(agentID: agentID, sessionID: sessionID).userId != request.userId {
            throw AgentSessionError.invalidPayload
        }
        let id = request.clientMessageId ?? UUID().uuidString
        guard UUID(uuidString: id) != nil else { throw AgentSessionError.invalidPayload }
        if let prior = detail.events.first(where: { $0.message?.id == id })?.message {
            guard prior.userId == request.userId, prior.segments.compactMap(\.text).joined() == request.content else {
                throw AgentSessionError.invalidPayload
            }
            return .init(summary: detail.summary, appendedEvents: [], routeDecision: nil)
        }
        let profile = try verificationProfile(projectID: projectID, alias: parts[1], commit: parts[2])
        guard activeVerificationNodes.insert(profile.nodeId).inserted else { throw AgentSessionError.invalidPayload }
        defer { activeVerificationNodes.remove(profile.nodeId) }

        let commandEvent = AgentSessionEvent(agentId: agentID, sessionId: sessionID, type: .message,
            message: .init(id: id, role: .user, segments: [.init(kind: .text, text: request.content)], userId: request.userId))
        let recorded = try await appendAgentSessionEvents(agentID: agentID, sessionID: sessionID, request: .init(events: [commandEvent]))
        let reply: String
        do {
            let result = try await runForegroundProcess(command: profile.executable, arguments: [], cwd: workspaceRootURL,
                timeoutMs: 60_000, maxOutputBytes: 12_000)
            let resultFields = result.asObject ?? [:]
            let stdout = resultFields["stdout"]?.asString ?? ""
            let stderr = resultFields["stderr"]?.asString ?? ""
            let exit = resultFields["exitCode"]?.asInt ?? -1
            let lines = Set(stdout.split(whereSeparator: \.isNewline).map(String.init))
            let inputConfirmed = lines.contains("Commit: \(profile.commit)") && lines.contains("Tree: \(profile.tree)")
            let status = resultFields["timedOut"]?.asBool == true ? "Timed out" :
                (exit == 0 && inputConfirmed ? "Passed" : "Failed (exit \(exit))")
            let log = (stdout + "\n" + stderr).split(separator: "\n", omittingEmptySubsequences: false)
                .map { "    \($0)" }.joined(separator: "\n")
            reply = "Machine: \(profile.alias) · \(profile.nodeId)\n\nCommit: `\(profile.commit)`\n\nTree: `\(profile.tree)`\n\nStatus: **\(status)**\n\nLog\n\n\(log)"
        } catch {
            reply = "Machine: \(profile.alias)\n\nCommit: `\(profile.commit)`\n\nStatus: **Failed to start**\n\n\(error.localizedDescription)"
        }
        let result = AgentSessionEvent(agentId: agentID, sessionId: sessionID, type: .message,
            message: .init(id: "verification-" + id, role: .assistant, segments: [.init(kind: .text, text: reply)]))
        let response = try await appendAgentSessionEvents(agentID: agentID, sessionID: sessionID, request: .init(events: [result]))
        return .init(summary: response.summary, appendedEvents: recorded.appendedEvents + response.appendedEvents, routeDecision: nil)
    }

    private func verificationProfile(projectID: String, alias: String, commit: String?, operation: String? = nil) throws -> SessionVerificationProfile {
        let url = workspaceRootURL.appendingPathComponent("machine-verification.json")
        guard Self.isPrivateVerificationFile(url), let data = try? Data(contentsOf: url),
              let profiles = try? JSONDecoder().decode([SessionVerificationProfile].self, from: data) else {
            throw AgentSessionError.invalidPayload
        }
        let matching = profiles.filter {
            $0.projectId == projectID && $0.alias == alias && $0.operation == operation && (commit == nil || $0.commit == commit)
        }
        guard matching.count == 1, let profile = matching.first,
              Self.isFullVerificationObjectID(profile.commit), Self.isFullVerificationObjectID(profile.tree),
              profile.executable.hasPrefix("/"), Self.isPrivateVerificationFile(URL(fileURLWithPath: profile.executable)),
              FileManager.default.isExecutableFile(atPath: profile.executable),
              let target = try remoteExecutionTargets().first(where: { $0.projectId == projectID && $0.alias == alias }),
              target.nodeId == profile.nodeId, target.allowedPeerIds.contains(try nodeConfigStore.load().identity.nodeId),
              try nodeMeshStore.listNodes().contains(where: { $0.id == target.nodeId && $0.status == .online }),
              try nodeMeshStore.listSharedProjects().contains(where: { project in
                  project.id == target.sharedProjectId && project.members.contains { $0.nodeId == target.nodeId }
              }) else { throw AgentSessionError.invalidPayload }
        return profile
    }

    private static func isPrivateVerificationFile(_ url: URL) -> Bool {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              attrs[.type] as? FileAttributeType == .typeRegular,
              let permissions = attrs[.posixPermissions] as? NSNumber else { return false }
        return permissions.intValue & 0o077 == 0
    }

    private static func isFullVerificationObjectID(_ value: String) -> Bool {
        [40, 64].contains(value.utf8.count) && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    static func studioBuildAliasIsExplicit(_ alias: String, in content: String) -> Bool {
        guard alias.first == "$", alias.count > 1 else { return false }
        return content.split(whereSeparator: \.isWhitespace).contains { word in
            guard word.first == "$" else { return false }
            let suffix = word.dropFirst().prefix { character in
                character == "_" || character == "-" || (character.isASCII && (character.isLetter || character.isNumber))
            }
            return alias.dropFirst() == suffix
        }
    }

    func queueStudioMachineBuild(agentID: String, sessionID: String, sourceID: String, alias: String) throws -> JSONValue {
        let storage = try longChats()
        let conversation = try storage.conversation(sessionId: sessionID)
        guard !longChatIsStopping, conversation.agentId == agentID, let projectID = conversation.projectId,
              let index = storage.state.turns.firstIndex(where: { $0.id == sourceID && $0.sessionId == sessionID }),
              storage.state.turns[index].request.userId == conversation.userId else { throw AgentSessionError.invalidPayload }
        let turn = storage.state.turns[index]
        guard turn.allowsMachineBuild == true, !turn.isNotification, turn.peerOrigin == nil,
              turn.request.mode != .ask, turn.request.mode != .plan,
              Self.studioBuildAliasIsExplicit(alias, in: turn.request.content) else {
            throw RemoteExecutionError.forbidden
        }
        if let existing = turn.machineBuild {
            guard existing.alias == alias else { throw AgentSessionError.invalidPayload }
            return .object(["accepted": .bool(true), "machine": .string(alias), "commit": .string(existing.commit),
                            "status": .string(existing.result == nil ? "queued" : "reported")])
        }
        let profile = try verificationProfile(projectID: projectID, alias: alias, commit: nil, operation: "studio_build")
        guard !activeVerificationNodes.contains(profile.nodeId) else { throw AgentSessionError.invalidPayload }
        // Persist the claim before launching. An interrupted turn can never submit it again.
        try storage.transaction { state in
            state.turns[index].machineBuild = .init(alias: alias, nodeId: profile.nodeId, commit: profile.commit)
        }
        activeVerificationNodes.insert(profile.nodeId)
        studioMachineBuildTasks[sourceID] = Task { [weak self] in
            await self?.performStudioMachineBuild(turn: turn, profile: profile)
        }
        return .object(["accepted": .bool(true), "machine": .string(alias), "commit": .string(profile.commit), "status": .string("queued")])
    }

    private func performStudioMachineBuild(turn: LongChatFileStore.Turn, profile: SessionVerificationProfile) async {
        defer {
            activeVerificationNodes.remove(profile.nodeId)
            studioMachineBuildTasks.removeValue(forKey: turn.id)
        }
        let header = "Studio · \(profile.alias)\n\nCommit: `\(profile.commit)`\n\nTree: `\(profile.tree)`"
        do {
            try publishStudioMachineBuildMessage(
                turn, suffix: "queued", text: "\(header)\n\nStatus: **Queued**")
            let response = try await runForegroundProcess(command: profile.executable, arguments: [], cwd: workspaceRootURL,
                timeoutMs: 2_400_000, maxOutputBytes: 32_000,
                outputArtifacts: ToolOutputArtifactStore(workspaceRootURL: workspaceRootURL, agentID: turn.agentId, sessionID: turn.sessionId))
            let fields = response.asObject ?? [:]
            let stdout = fields["stdout"]?.asString ?? ""
            let stderr = fields["stderr"]?.asString ?? ""
            let output = stdout.split(whereSeparator: \.isNewline).map(String.init)
            let verified = output.contains("Commit: \(profile.commit)") && output.contains("Tree: \(profile.tree)")
            let exit = fields["exitCode"]?.asInt ?? -1
            let status: String
            if Task.isCancelled { status = "Interrupted" }
            else if fields["timedOut"]?.asBool == true { status = "Timed out" }
            else if exit != 0 { status = "Build failed (exit \(exit))" }
            else if !verified { status = "Build failed (revision was not confirmed)" }
            else { status = "Built" }
            let log = (stdout + "\n" + stderr).split(separator: "\n", omittingEmptySubsequences: false)
                .map { "    \($0)" }.joined(separator: "\n")
            let truncated = fields["stdoutTruncated"]?.asBool == true || fields["stderrTruncated"]?.asBool == true
            let text = "\(header)\n\nStatus: **\(status)**\n\n\(truncated ? "Log preview" : "Log")\n\n\(log)"
            try finishStudioMachineBuild(turn, text: text)
        } catch {
            try? finishStudioMachineBuild(turn, text: "\(header)\n\nStatus: **Build failed**\n\n\(error.localizedDescription)")
        }
    }

    private func finishStudioMachineBuild(_ turn: LongChatFileStore.Turn, text: String) throws {
        try longChats().transaction { state in
            if let index = state.turns.firstIndex(where: { $0.id == turn.id }) {
                state.turns[index].machineBuild?.result = text
            }
        }
        try publishStudioMachineBuildMessage(turn, suffix: "result", text: text)
    }

    private func publishStudioMachineBuildMessage(_ turn: LongChatFileStore.Turn, suffix: String, text: String) throws {
        let id = "studio-build-\(suffix)-\(turn.id)"
        let detail = try sessionStore.loadSession(agentID: turn.agentId, sessionID: turn.sessionId)
        guard !detail.events.contains(where: { $0.id == id }) else { return }
        let event = AgentSessionEvent(id: id, agentId: turn.agentId, sessionId: turn.sessionId, type: .message,
            message: .init(id: id, role: .assistant, segments: [.init(kind: .text, text: text)]))
        let summary = try sessionStore.appendEvents(agentID: turn.agentId, sessionID: turn.sessionId, events: [event])
        publishLiveSessionEvents(agentID: turn.agentId, sessionID: turn.sessionId, summary: summary, events: [event])
    }

    func recoverStudioMachineBuilds(_ storage: LongChatFileStore) {
        for turn in storage.state.turns {
            guard let build = turn.machineBuild else { continue }
            let text = build.result ?? "Studio · \(build.alias)\n\nCommit: `\(build.commit)`\n\nStatus: **Interrupted**\n\nCore restarted before receiving the result. Check the machine before retrying."
            do {
                if build.result == nil { try finishStudioMachineBuild(turn, text: text) }
                else { try publishStudioMachineBuildMessage(turn, suffix: "result", text: text) }
            } catch {
                logger.warning("studio_build.report_recovery_failed", metadata: ["session_id": .string(turn.sessionId), "error": .string(error.localizedDescription)])
            }
        }
    }
}

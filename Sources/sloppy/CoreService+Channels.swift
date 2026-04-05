import Foundation
import AgentRuntime
import Protocols
import Logging

// MARK: - Channels

extension CoreService {
    public func postChannelMessage(channelId: String, request: ChannelMessageRequest) async -> ChannelRouteDecision {
        await waitForStartup()

        let trimmedContent = request.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedContent.lowercased() == "/abort" {
            let cancelled = await runtime.abortChannel(channelId: channelId, reason: "Aborted by user")
            let reason = cancelled > 0
                ? "Aborted \(cancelled) active worker(s)."
                : "No active workers to abort."
            return ChannelRouteDecision(action: .respond, reason: reason, confidence: 1.0, tokenBudget: 0)
        }

        if let approvalReference = TaskApprovalCommandParser.parse(request.content) {
            return await handleTaskApprovalCommand(channelId: channelId, reference: approvalReference)
        }
        if let plannedDecision = await handleVisorTaskPlan(channelId: channelId, request: request) {
            return plannedDecision
        }

        let enrichedContent = await enrichMessageWithTaskReferences(request.content)
        let nextRequest = ChannelMessageRequest(
            userId: request.userId,
            content: enrichedContent,
            topicId: request.topicId
        )
        return await runtime.postMessage(channelId: channelId, request: nextRequest)
    }

    /// Controls channel processing: abort active workers on this channel.
    public func controlChannel(channelId: String, action: AgentRunControlAction) async -> ChannelControlResponse {
        await waitForStartup()
        switch action {
        case .interrupt:
            let cancelled = await runtime.abortChannel(channelId: channelId, reason: "Interrupted by user")
            return ChannelControlResponse(
                channelId: channelId,
                action: action,
                cancelledWorkers: cancelled,
                message: cancelled > 0
                    ? "Aborted \(cancelled) active worker(s)."
                    : "No active workers to abort."
            )
        case .pause, .resume:
            return ChannelControlResponse(
                channelId: channelId,
                action: action,
                cancelledWorkers: 0,
                message: "Action \(action.rawValue) acknowledged."
            )
        }
    }

    /// Routes interactive message into a running worker.
    public func postChannelRoute(channelId: String, workerId: String, request: ChannelRouteRequest) async -> Bool {
        await waitForStartup()
        return await runtime.routeMessage(channelId: channelId, workerId: workerId, message: request.message)
    }

    /// Delivers an outbound message to the channel plugin responsible for this channelId.
    @discardableResult
    public func deliverToChannelPlugin(channelId: String, userId: String = "system", content: String) async -> Bool {
        await channelDelivery.deliver(channelId: channelId, userId: userId, content: content)
    }

    /// Returns current state snapshot for a channel.
    public func getChannelState(channelId: String) async -> ChannelSnapshot? {
        await waitForStartup()
        return await runtime.channelState(channelId: channelId)
    }

    /// Returns known visor bulletins, preferring in-memory runtime state.
    public func listChannelEvents(
        channelId: String,
        limit: Int = 50,
        cursor: String? = nil,
        before: Date? = nil,
        after: Date? = nil
    ) async -> ChannelEventsResponse {
        let boundedLimit = min(max(limit, 1), 200)
        let parsedCursor = Self.decodeEventCursor(cursor)
        let events = await store.listChannelEvents(
            channelId: channelId,
            limit: boundedLimit,
            cursor: parsedCursor,
            before: before,
            after: after
        )
        let nextCursor = events.last.map(Self.encodeEventCursor)
        return ChannelEventsResponse(channelId: channelId, items: events, nextCursor: nextCursor)
    }

    public func listChannelSessions(
        status: ChannelSessionStatus? = nil,
        agentID: String? = nil
    ) async throws -> [ChannelSessionSummary] {
        await waitForStartup()

        let board = try? getActorBoard()
        let filteredChannelIDs: Set<String>?
        if let agentID {
            guard let normalizedAgentID = normalizedAgentID(agentID) else {
                throw AgentStorageError.invalidID
            }
            _ = try getAgent(id: normalizedAgentID)
            filteredChannelIDs = boundChannelIDs(agentID: normalizedAgentID, board: board)
        } else {
            filteredChannelIDs = nil
        }

        let timeoutByChannel = channelSessionTimeouts(
            board: board,
            limitToChannelIDs: filteredChannelIDs
        )
        let globalDefault = globalChannelInactivityTimeoutMinutes()
        _ = try await channelSessionStore.expireInactiveSessions(
            timeoutByChannel: timeoutByChannel,
            globalDefaultTimeoutMinutes: globalDefault
        )
        return try await channelSessionStore.listSessions(
            status: status,
            channelIds: filteredChannelIDs
        )
    }

    public func getChannelSession(sessionID: String) async throws -> ChannelSessionDetail {
        await waitForStartup()
        return try await channelSessionStore.loadSessionDetail(sessionID: sessionID)
    }


    /// Returns one dashboard project by identifier.
    func prepareChannelSession(channelId: String) async throws {
        let normalizedChannelID = normalizeWhitespace(channelId)
        guard !normalizedChannelID.isEmpty else {
            return
        }

        let board = try? getActorBoard()
        let timeoutByChannel = channelSessionTimeouts(
            board: board,
            limitToChannelIDs: Set([normalizedChannelID])
        )
        let globalDefault = globalChannelInactivityTimeoutMinutes()
        _ = try await channelSessionStore.expireInactiveSessions(
            timeoutByChannel: timeoutByChannel,
            globalDefaultTimeoutMinutes: globalDefault
        )
    }

    func globalChannelInactivityTimeoutMinutes() -> Int? {
        let days = currentConfig.channels.channelInactivityDays
        guard days > 0 else { return nil }
        return days * 24 * 60
    }

    func channelSessionTimeouts(
        board: ActorBoardSnapshot?,
        limitToChannelIDs: Set<String>? = nil
    ) -> [String: Int] {
        guard let board else {
            return [:]
        }

        var timeoutByChannel: [String: Int] = [:]
        let sortedNodes = board.nodes.sorted { left, right in
            if left.createdAt == right.createdAt {
                return left.id < right.id
            }
            return left.createdAt < right.createdAt
        }

        for node in sortedNodes {
            let channelID = normalizeWhitespace(node.channelId ?? "")
            let agentID = normalizeWhitespace(node.linkedAgentId ?? "")
            guard !channelID.isEmpty, !agentID.isEmpty else {
                continue
            }
            if let limitToChannelIDs, !limitToChannelIDs.contains(channelID) {
                continue
            }
            if timeoutByChannel[channelID] != nil {
                continue
            }

            guard let config = try? getAgentConfig(agentID: agentID) else {
                continue
            }
            guard config.channelSessions.autoCloseEnabled else {
                continue
            }
            timeoutByChannel[channelID] = max(1, config.channelSessions.autoCloseAfterMinutes)
        }

        return timeoutByChannel
    }

    func boundChannelIDs(agentID: String, board: ActorBoardSnapshot?) -> Set<String> {
        guard let board else {
            return []
        }

        return Set(
            board.nodes.compactMap { node in
                guard normalizeWhitespace(node.linkedAgentId ?? "") == agentID else {
                    return nil
                }
                let channelID = normalizeWhitespace(node.channelId ?? "")
                return channelID.isEmpty ? nil : channelID
            }
        )
    }

    func linkedAgentID(forChannelID channelID: String, board: ActorBoardSnapshot?) -> String? {
        guard let board else {
            return nil
        }

        let normalizedChannelID = normalizeWhitespace(channelID)
        for node in board.nodes {
            guard normalizeWhitespace(node.channelId ?? "") == normalizedChannelID else {
                continue
            }
            let linkedAgentID = normalizeWhitespace(node.linkedAgentId ?? "")
            if !linkedAgentID.isEmpty {
                return linkedAgentID
            }
        }
        return nil
    }

}

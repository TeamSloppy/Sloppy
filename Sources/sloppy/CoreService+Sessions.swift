import Foundation
import AgentRuntime
import Protocols

// MARK: - Agent Sessions

extension CoreService {
    public func listAgentSessions(agentID: String) throws -> [AgentSessionSummary] {
        guard let normalizedAgentID = normalizedAgentID(agentID) else {
            throw AgentSessionError.invalidAgentID
        }

        _ = try getAgent(id: normalizedAgentID)

        do {
            return try sessionStore.listSessions(agentID: normalizedAgentID)
        } catch {
            throw mapSessionStoreError(error)
        }
    }

    /// Creates a session for a given agent.
    public func createAgentSession(agentID: String, request: AgentSessionCreateRequest) async throws -> AgentSessionSummary {
        await waitForStartup()
        guard let normalizedAgentID = normalizedAgentID(agentID) else {
            throw AgentSessionError.invalidAgentID
        }

        _ = try getAgent(id: normalizedAgentID)
        await refreshAgentMemoryFile(agentID: normalizedAgentID)

        do {
            let session = try await sessionOrchestrator.createSession(agentID: normalizedAgentID, request: request)
            if !currentConfig.onboarding.completed,
               request.title?.localizedCaseInsensitiveContains("onboarding") == true {
                logger.info(
                    "onboarding.session.created",
                    metadata: [
                        "agent_id": .string(normalizedAgentID),
                        "session_id": .string(session.id),
                        "title": .string(request.title ?? "")
                    ]
                )
            }
            return session
        } catch {
            throw mapSessionOrchestratorError(error)
        }
    }

    /// Loads one session with its full event history.
    public func getAgentSession(agentID: String, sessionID: String) throws -> AgentSessionDetail {
        guard let normalizedAgentID = normalizedAgentID(agentID) else {
            throw AgentSessionError.invalidAgentID
        }

        guard let normalizedSessionID = normalizedSessionID(sessionID) else {
            throw AgentSessionError.invalidSessionID
        }

        _ = try getAgent(id: normalizedAgentID)

        do {
            return try sessionStore.loadSession(agentID: normalizedAgentID, sessionID: normalizedSessionID)
        } catch {
            throw mapSessionStoreError(error)
        }
    }

    public func canStreamAgentSessionEvents(agentID: String, sessionID: String) -> Bool {
        do {
            let identifiers = try validatedStreamIdentifiers(agentID: agentID, sessionID: sessionID)
            _ = try getAgentSession(agentID: identifiers.agentID, sessionID: identifiers.sessionID)
            return true
        } catch {
            return false
        }
    }

    /// Streams incremental session updates over a long-lived connection.
    public func streamAgentSessionEvents(agentID: String, sessionID: String) throws -> AsyncStream<AgentSessionStreamUpdate> {
        let identifiers = try validatedStreamIdentifiers(agentID: agentID, sessionID: sessionID)
        let detail = try getAgentSession(agentID: identifiers.agentID, sessionID: identifiers.sessionID)
        let streamKey = sessionStreamKey(agentID: identifiers.agentID, sessionID: identifiers.sessionID)

        return AsyncStream(bufferingPolicy: .bufferingNewest(128)) { continuation in
            let listenerID = UUID()
            let readyCursor = max(detail.events.count, currentLiveSessionStreamCursor(for: streamKey))
            setLiveSessionStreamCursor(readyCursor, for: streamKey)
            registerLiveSessionStreamContinuation(
                key: streamKey,
                listenerID: listenerID,
                continuation: continuation
            )

            continuation.yield(
                AgentSessionStreamUpdate(
                    kind: .sessionReady,
                    cursor: readyCursor,
                    summary: detail.summary
                )
            )

            let heartbeatTask = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 12_000_000_000)
                    if Task.isCancelled {
                        break
                    }
                    guard isLiveSessionStreamContinuationRegistered(key: streamKey, listenerID: listenerID) else {
                        break
                    }

                    continuation.yield(
                        AgentSessionStreamUpdate(
                            kind: .heartbeat,
                            cursor: nextLiveSessionStreamCursor(for: streamKey),
                            summary: detail.summary
                        )
                    )
                }
            }

            continuation.onTermination = { _ in
                heartbeatTask.cancel()
                Task {
                    await self.unregisterLiveSessionStreamContinuation(key: streamKey, listenerID: listenerID)
                }
            }
        }
    }

    func publishLiveSessionDelta(agentID: String, sessionID: String, chunk: String) {
        let normalized = chunk.replacingOccurrences(of: "\r\n", with: "\n")
        let trimmed = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }

        publishLiveSessionUpdate(
            agentID: agentID,
            sessionID: sessionID,
            update: AgentSessionStreamUpdate(
            kind: .sessionDelta,
            cursor: 0,
            message: normalized
            )
        )
    }

    func publishLiveSessionEvents(
        agentID: String,
        sessionID: String,
        summary: AgentSessionSummary,
        events: [AgentSessionEvent]
    ) {
        for event in events {
            publishLiveSessionUpdate(
                agentID: agentID,
                sessionID: sessionID,
                update: AgentSessionStreamUpdate(
                    kind: .sessionEvent,
                    cursor: 0,
                    summary: summary,
                    event: event
                )
            )
        }
    }

    func publishLiveSessionClosed(agentID: String, sessionID: String, message: String) {
        publishLiveSessionUpdate(
            agentID: agentID,
            sessionID: sessionID,
            update: AgentSessionStreamUpdate(
                kind: .sessionClosed,
                cursor: 0,
                message: message
            )
        )
    }

    func publishLiveSessionUpdate(
        agentID: String,
        sessionID: String,
        update: AgentSessionStreamUpdate
    ) {
        let key = sessionStreamKey(agentID: agentID, sessionID: sessionID)
        guard let listeners = liveSessionStreamContinuations[key], !listeners.isEmpty else {
            return
        }

        var published = update
        published.cursor = nextLiveSessionStreamCursor(for: key)
        for continuation in listeners.values {
            continuation.yield(published)
        }
    }

    func registerLiveSessionStreamContinuation(
        key: String,
        listenerID: UUID,
        continuation: AsyncStream<AgentSessionStreamUpdate>.Continuation
    ) {
        var listeners = liveSessionStreamContinuations[key] ?? [:]
        listeners[listenerID] = continuation
        liveSessionStreamContinuations[key] = listeners
    }

    func unregisterLiveSessionStreamContinuation(key: String, listenerID: UUID) {
        guard var listeners = liveSessionStreamContinuations[key] else {
            return
        }

        listeners.removeValue(forKey: listenerID)
        if listeners.isEmpty {
            liveSessionStreamContinuations.removeValue(forKey: key)
            liveSessionStreamCursor.removeValue(forKey: key)
        } else {
            liveSessionStreamContinuations[key] = listeners
        }
    }

    func isLiveSessionStreamContinuationRegistered(key: String, listenerID: UUID) -> Bool {
        liveSessionStreamContinuations[key]?[listenerID] != nil
    }

    func currentLiveSessionStreamCursor(for key: String) -> Int {
        liveSessionStreamCursor[key] ?? 0
    }

    func setLiveSessionStreamCursor(_ value: Int, for key: String) {
        liveSessionStreamCursor[key] = value
    }

    func nextLiveSessionStreamCursor(for key: String) -> Int {
        let baseline = max(1_000_000, liveSessionStreamCursor[key] ?? 1_000_000)
        let next = baseline + 1
        liveSessionStreamCursor[key] = next
        return next
    }

    func sessionStreamKey(agentID: String, sessionID: String) -> String {
        "\(agentID)::\(sessionID)"
    }

    func validatedStreamIdentifiers(
        agentID: String,
        sessionID: String
    ) throws -> (agentID: String, sessionID: String) {
        guard let normalizedAgentID = normalizedAgentID(agentID) else {
            throw AgentSessionError.invalidAgentID
        }

        guard let normalizedSessionID = normalizedSessionID(sessionID) else {
            throw AgentSessionError.invalidSessionID
        }

        _ = try getAgent(id: normalizedAgentID)
        return (normalizedAgentID, normalizedSessionID)
    }

    /// Deletes one session and its attachment directory.
    public func deleteAgentSession(agentID: String, sessionID: String) async throws {
        guard let normalizedAgentID = normalizedAgentID(agentID) else {
            throw AgentSessionError.invalidAgentID
        }

        guard let normalizedSessionID = normalizedSessionID(sessionID) else {
            throw AgentSessionError.invalidSessionID
        }

        _ = try getAgent(id: normalizedAgentID)

        do {
            try sessionStore.deleteSession(agentID: normalizedAgentID, sessionID: normalizedSessionID)
            publishLiveSessionClosed(
                agentID: normalizedAgentID,
                sessionID: normalizedSessionID,
                message: "Session was deleted."
            )
            await acpSessionManager.removeSession(agentID: normalizedAgentID, sloppySessionID: normalizedSessionID)
            await toolExecution.cleanupSessionProcesses(normalizedSessionID)
        } catch {
            throw mapSessionStoreError(error)
        }
    }

    /// Appends user message, run-status events and assistant reply into session JSONL.
    public func postAgentSessionMessage(
        agentID: String,
        sessionID: String,
        request: AgentSessionPostMessageRequest
    ) async throws -> AgentSessionMessageResponse {
        await waitForStartup()
        guard let normalizedAgentID = normalizedAgentID(agentID) else {
            throw AgentSessionError.invalidAgentID
        }

        guard let normalizedSessionID = normalizedSessionID(sessionID) else {
            throw AgentSessionError.invalidSessionID
        }

        _ = try getAgent(id: normalizedAgentID)
        if request.userId == "onboarding" {
            logger.info(
                "onboarding.message.posted",
                metadata: [
                    "agent_id": .string(normalizedAgentID),
                    "session_id": .string(normalizedSessionID),
                    "content_chars": .stringConvertible(request.content.count)
                ]
            )
        }

        do {
            return try await sessionOrchestrator.postMessage(
                agentID: normalizedAgentID,
                sessionID: normalizedSessionID,
                request: request
            )
        } catch {
            throw mapSessionOrchestratorError(error)
        }
    }

    /// Appends control signal (pause/resume/interrupt) and corresponding status.
    public func controlAgentSession(
        agentID: String,
        sessionID: String,
        request: AgentSessionControlRequest
    ) async throws -> AgentSessionMessageResponse {
        await waitForStartup()
        guard let normalizedAgentID = normalizedAgentID(agentID) else {
            throw AgentSessionError.invalidAgentID
        }

        guard let normalizedSessionID = normalizedSessionID(sessionID) else {
            throw AgentSessionError.invalidSessionID
        }

        _ = try getAgent(id: normalizedAgentID)

        do {
            return try await sessionOrchestrator.controlSession(
                agentID: normalizedAgentID,
                sessionID: normalizedSessionID,
                request: request
            )
        } catch {
            throw mapSessionOrchestratorError(error)
        }
    }

    public func appendAgentSessionEvents(
        agentID: String,
        sessionID: String,
        request: AgentSessionAppendEventsRequest
    ) async throws -> AgentSessionMessageResponse {
        await waitForStartup()
        guard let normalizedAgentID = normalizedAgentID(agentID) else {
            throw AgentSessionError.invalidAgentID
        }

        guard let normalizedSessionID = normalizedSessionID(sessionID) else {
            throw AgentSessionError.invalidSessionID
        }

        _ = try getAgent(id: normalizedAgentID)

        do {
            return try await sessionOrchestrator.appendSessionEvents(
                agentID: normalizedAgentID,
                sessionID: normalizedSessionID,
                events: request.events
            )
        } catch {
            throw mapSessionOrchestratorError(error)
        }
    }

}

import Foundation
import AgentRuntime
import PluginSDK
import Protocols
import SloppyRuntime

// MARK: - Agent Sessions

extension CoreService {
    public func listAgentSessions(
        agentID: String,
        projectID: String? = nil,
        limit: Int? = nil,
        offset: Int = 0
    ) throws -> [AgentSessionSummary] {
        guard let normalizedAgentID = normalizedAgentID(agentID) else {
            throw AgentSessionError.invalidAgentID
        }

        _ = try getAgent(id: normalizedAgentID)

        do {
            _ = deleteExpiredAgentSessionsIfNeeded()
            var sessions = try sessionStore.listSessions(agentID: normalizedAgentID)
            let longChatIDs = Set(sessions.filter { $0.kind == .longChat }.map(\.id))
            sessions.removeAll { $0.parentSessionId.map(longChatIDs.contains) == true }
            if let filter = projectID?.trimmingCharacters(in: .whitespacesAndNewlines), !filter.isEmpty {
                sessions = sessions.filter { ($0.projectId ?? "").caseInsensitiveCompare(filter) == .orderedSame }
            }
            return Self.paginatedAgentSessions(sessions, limit: limit, offset: offset)
        } catch {
            throw mapSessionStoreError(error)
        }
    }

    public func listAllAgentSessions(
        includeWorkers: Bool = false, query: String? = nil, projectID: String? = nil,
        agentID: String? = nil, limit: Int? = nil, offset: Int = 0
    ) throws -> [AgentSessionSummary] {
        _ = deleteExpiredAgentSessionsIfNeeded()
        return try SessionToolQuery.list(
            agentID: agentID, projectID: projectID, query: query,
            limit: limit, offset: offset, includeWorkers: includeWorkers,
            catalog: agentCatalogStore, store: sessionStore)
    }

    /// Creates a session for a given agent.
    public func createAgentSession(agentID: String, request: AgentSessionCreateRequest, userID: String? = nil) async throws -> AgentSessionSummary {
        await waitForStartup()
        await deleteExpiredSessionsIfNeeded()
        guard let normalizedAgentID = normalizedAgentID(agentID) else {
            throw AgentSessionError.invalidAgentID
        }

        _ = try getAgent(id: normalizedAgentID)

        guard request.kind != .longChat, request.kind != .longChatWorker else { throw AgentSessionError.invalidPayload }
        if let parentID = request.parentSessionId,
           (try? getAgentSession(agentID: normalizedAgentID, sessionID: parentID).summary.kind) == .longChat {
            throw AgentSessionError.invalidPayload
        }
        if let userID, request.kind == .chat, let projectID = request.projectId,
           request.forkFromSessionId == nil,
           request.parentSessionId == nil, request.taskId == nil, request.workspaceId == nil,
           request.separateChat != true,
           try agentCatalogStore.getAgentRuntimeConfig(agentID: normalizedAgentID).type == .native {
            return try await openLongChat(agentID: normalizedAgentID, userID: userID, projectID: projectID)
        }
        let checkpointSessionID = request.checkpointSessionId
            .flatMap { normalizedSessionID($0.trimmingCharacters(in: .whitespacesAndNewlines)) }

        var request = request
        let forkedEvents = try forkedSessionEvents(agentID: normalizedAgentID, request: &request)

        do {
            let session = try await sessionOrchestrator.createSession(agentID: normalizedAgentID, request: request)
            do {
                try initializeSessionApprovalPolicy(session)
            } catch {
                try? sessionStore.deleteSession(agentID: normalizedAgentID, sessionID: session.id)
                throw error
            }
            if !forkedEvents.isEmpty {
                let copies = try sessionStore.makeHistoricalEvents(forkedEvents, agentID: normalizedAgentID, sessionID: session.id)
                _ = try sessionStore.appendEvents(agentID: normalizedAgentID, sessionID: session.id, events: copies)
                try await sessionOrchestrator.prepareSessionContext(agentID: normalizedAgentID, sessionID: session.id)
            }
            if request.separateChat == true || (userID == nil && request.projectId != nil) {
                do {
                    try longChats().transaction { state in
                        state.separateSessionIds = (state.separateSessionIds ?? []) + [session.id]
                    }
                } catch {
                    try? sessionStore.deleteSession(agentID: normalizedAgentID, sessionID: session.id)
                    throw error
                }
            }
            if let parentSessionID = session.parentSessionId {
                try await toolExecution.desktopComputerBridge.inheritAssignment(
                    parentSessionID: parentSessionID, agentID: normalizedAgentID, sessionID: session.id
                )
            }
            if let checkpointSessionID {
                await scheduleAgentMemoryCheckpoint(
                    agentID: normalizedAgentID,
                    sessionID: checkpointSessionID,
                    reason: "new_session_command"
                )
            }
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

    /// Resolves the conversation history a forked session starts with and detaches the request from its source.
    ///
    /// Forks carry their own copy of the history, so the parent link is dropped to keep the model from also
    /// recovering the source session's later turns.
    private func forkedSessionEvents(agentID: String, request: inout AgentSessionCreateRequest) throws -> [AgentSessionEvent] {
        guard let rawSourceID = request.forkFromSessionId else { return [] }
        let beforeMessageID = request.forkBeforeMessageId
        let throughMessageID = request.forkThroughMessageId
        guard beforeMessageID == nil || throughMessageID == nil else { throw AgentSessionError.invalidPayload }
        request.forkFromSessionId = nil
        request.forkBeforeMessageId = nil
        request.forkThroughMessageId = nil
        request.parentSessionId = nil
        guard let sourceID = normalizedSessionID(rawSourceID.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw AgentSessionError.invalidSessionID
        }
        let source: AgentSessionDetail
        do {
            source = try sessionStore.loadSession(agentID: agentID, sessionID: sourceID)
        } catch {
            throw mapSessionStoreError(error)
        }
        var events = source.events
        if let beforeMessageID {
            guard let cut = events.firstIndex(where: { $0.message?.id == beforeMessageID }) else {
                throw AgentSessionError.invalidPayload
            }
            events = Array(events[..<cut])
        }
        if let throughMessageID {
            guard let cut = events.firstIndex(where: { $0.message?.id == throughMessageID }) else {
                throw AgentSessionError.invalidPayload
            }
            events = Array(events[...cut])
        }
        let history: Set<AgentSessionEventType> = [.message, .toolCall, .toolResult]
        // A cut may omit the later admission/cancellation rows. Determine eligibility from
        // the complete source before copied records become non-authoritative history.
        return SessionInputLifecycle.contextEvents(events, canonical: source.events).filter { history.contains($0.type) }
    }

    public func renameAgentSession(agentID: String, sessionID: String, title: String) throws -> AgentSessionSummary {
        guard let agentID = normalizedAgentID(agentID) else { throw AgentSessionError.invalidAgentID }
        guard let sessionID = normalizedSessionID(sessionID) else { throw AgentSessionError.invalidSessionID }
        do {
            _ = try getAgent(id: agentID)
            return try sessionStore.renameSession(agentID: agentID, sessionID: sessionID, title: title)
        } catch AgentStorageError.notFound {
            throw AgentSessionError.agentNotFound
        } catch {
            throw mapSessionStoreError(error)
        }
    }

    /// Loads one session with its full event history.
    public func getAgentSession(
        agentID: String, sessionID: String, eventLimit: Int? = nil, before: String? = nil
    ) throws -> AgentSessionDetail {
        guard let normalizedAgentID = normalizedAgentID(agentID) else {
            throw AgentSessionError.invalidAgentID
        }

        guard let normalizedSessionID = normalizedSessionID(sessionID) else {
            throw AgentSessionError.invalidSessionID
        }

        _ = try getAgent(id: normalizedAgentID)

        do {
            if let eventLimit {
                return try sessionStore.loadSessionPage(
                    agentID: normalizedAgentID, sessionID: normalizedSessionID, limit: eventLimit, before: before, excludingDerivedWork: true
                )
            }
            guard before == nil else { throw AgentSessionError.invalidPayload }
            var detail = try sessionStore.loadSession(agentID: normalizedAgentID, sessionID: normalizedSessionID)
            detail.events.removeAll { $0.runtimeMetadata?.derivedSource != nil }
            return detail
        } catch {
            logger.error("session.read.failed", metadata: ["agent_id": .string(normalizedAgentID),
                "session_id": .string(normalizedSessionID), "error": .string(String(describing: error))])
            throw mapSessionStoreError(error)
        }
    }

    /// Bounded reads for canonical tool outputs; ordinary attachments keep their compatible endpoint.
    public func getAgentSessionAttachmentChunk(agentID: String, sessionID: String, attachmentID: String,
        offset: Int, limit: Int) throws -> ToolOutputArtifactChunk? {
        guard let artifact = try sessionStore.toolOutputArtifactReferences(agentID: agentID, sessionID: sessionID)
            .first(where: { $0.attachment.id == attachmentID }) else { return nil }
        return try sessionStore.readToolOutputArtifactChunk(artifact, offset: min(offset, artifact.attachment.sizeBytes), limit: limit)
    }

    /// Only attachment IDs present in this session can be retrieved. Never accepts a client path.
    public func getAgentSessionAttachment(agentID: String, sessionID: String, attachmentID: String) throws -> (data: Data, mediaType: String) {
        let detail = try getAgentSession(agentID: agentID, sessionID: sessionID)
        if let artifact = detail.events.compactMap(\.runtimeMetadata?.toolOutputArtifact).first(where: { $0.attachment.id == attachmentID }) {
            let bytes = try sessionStore.readInputAttachment(agentID: agentID, sessionID: sessionID, attachment: artifact.attachment)
            guard ContentDigest.sha256(bytes) == artifact.sha256 else { throw AgentSessionError.sessionNotFound }
            return (bytes, artifact.attachment.mimeType)
        }
        guard let attachment = detail.events.compactMap(\.message).flatMap(\.segments)
            .compactMap(\.attachment).first(where: { $0.id == attachmentID }),
              let url = try sessionStore.resolveAttachmentFileURL(agentID: agentID, attachment: attachment) else {
            throw AgentSessionError.sessionNotFound
        }
        // Resolve symlinks and require the stored asset to remain within its agent's sessions.
        let root = try agentCatalogStore.directoryURL(agentID: agentID)
            .appendingPathComponent("sessions").resolvingSymlinksInPath().standardizedFileURL.path + "/"
        let target = url.resolvingSymlinksInPath().standardizedFileURL
        guard target.path.hasPrefix(root),
              let size = try target.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= 25 * 1_024 * 1_024 else { throw AgentSessionError.sessionNotFound }
        let data = try Data(contentsOf: target)
        guard data.count <= 25 * 1_024 * 1_024 else { throw AgentSessionError.sessionNotFound }
        return (data, attachment.mimeType)
    }

    public func getAgentSessionFilePath(agentID: String, sessionID: String) throws -> String {
        guard let normalizedAgentID = normalizedAgentID(agentID) else {
            throw AgentSessionError.invalidAgentID
        }

        guard let normalizedSessionID = normalizedSessionID(sessionID) else {
            throw AgentSessionError.invalidSessionID
        }

        _ = try getAgent(id: normalizedAgentID)

        do {
            return try sessionStore.sessionFilePath(agentID: normalizedAgentID, sessionID: normalizedSessionID)
        } catch {
            throw mapSessionStoreError(error)
        }
    }

    public func prepareAgentSessionContext(agentID: String, sessionID: String) async throws -> AgentSessionSummary {
        await waitForStartup()
        guard let normalizedAgentID = normalizedAgentID(agentID) else {
            throw AgentSessionError.invalidAgentID
        }

        guard let normalizedSessionID = normalizedSessionID(sessionID) else {
            throw AgentSessionError.invalidSessionID
        }

        _ = try getAgent(id: normalizedAgentID)
        let detail = try getAgentSession(agentID: normalizedAgentID, sessionID: normalizedSessionID)

        do {
            try await sessionOrchestrator.prepareSessionContext(
                agentID: normalizedAgentID,
                sessionID: normalizedSessionID
            )
            return detail.summary
        } catch {
            throw mapSessionOrchestratorError(error)
        }
    }

    public func hasLiveAgentRuntimeSession(agentID: String, sessionID: String) async throws -> Bool {
        await waitForStartup()
        guard let normalizedAgentID = normalizedAgentID(agentID) else {
            throw AgentSessionError.invalidAgentID
        }

        guard let normalizedSessionID = normalizedSessionID(sessionID) else {
            throw AgentSessionError.invalidSessionID
        }

        _ = try getAgent(id: normalizedAgentID)
        _ = try getAgentSession(agentID: normalizedAgentID, sessionID: normalizedSessionID)

        return await sessionOrchestrator.hasLiveRuntimeSession(
            agentID: normalizedAgentID,
            sessionID: normalizedSessionID
        )
    }

    /// Adds a directory as a session-scoped tool root. The first added directory also becomes
    /// the default current directory for sessions that do not already have one.
    public func addAgentSessionDirectory(
        agentID: String,
        sessionID: String,
        request: AgentSessionDirectoryRequest
    ) async throws -> AgentSessionDirectoryResponse {
        await waitForStartup()
        guard let normalizedAgentID = normalizedAgentID(agentID) else {
            throw AgentSessionError.invalidAgentID
        }
        guard let normalizedSessionID = normalizedSessionID(sessionID) else {
            throw AgentSessionError.invalidSessionID
        }

        _ = try getAgent(id: normalizedAgentID)
        let detail: AgentSessionDetail
        do {
            detail = try sessionStore.loadSession(agentID: normalizedAgentID, sessionID: normalizedSessionID)
        } catch {
            throw mapSessionStoreError(error)
        }

        let existingContext = await toolContextForSession(
            sessionID: normalizedSessionID,
            sessionTitle: detail.summary.title,
            projectID: detail.summary.projectId,
            taskID: detail.summary.taskId
        )
        let resolvedPath = try resolvedSessionDirectoryPath(
            request.path,
            baseDirectory: existingContext.workingDirectory
        )
        let workingDirectory = existingContext.workingDirectory ?? resolvedPath
        let roots = appendingUniqueRoot(resolvedPath, to: existingContext.extraRoots)
        sessionAddedRoots[normalizedSessionID] = appendingUniqueRoot(
            resolvedPath,
            to: sessionAddedRoots[normalizedSessionID] ?? []
        )

        sessionExtraRoots[normalizedSessionID] = roots
        sessionWorkingDirectories[normalizedSessionID] = workingDirectory

        return AgentSessionDirectoryResponse(
            path: resolvedPath,
            workingDirectory: workingDirectory,
            directories: roots
        )
    }

    public func canStreamAgentSessionEvents(agentID: String, sessionID: String) -> Bool {
        do {
            let identifiers = try validatedStreamIdentifiers(agentID: agentID, sessionID: sessionID)
            _ = try getAgentSession(agentID: identifiers.agentID, sessionID: identifiers.sessionID, eventLimit: 1)
            return true
        } catch {
            return false
        }
    }

    /// Streams incremental session updates over a long-lived connection.
    public func streamAgentSessionEvents(agentID: String, sessionID: String) throws -> AsyncStream<AgentSessionStreamUpdate> {
        let identifiers = try validatedStreamIdentifiers(agentID: agentID, sessionID: sessionID)
        let detail = try getAgentSession(agentID: identifiers.agentID, sessionID: identifiers.sessionID, eventLimit: 1)
        let streamKey = sessionStreamKey(agentID: identifiers.agentID, sessionID: identifiers.sessionID)

        return AsyncStream(bufferingPolicy: .bufferingNewest(128)) { continuation in
            let listenerID = UUID()
            let readyCursor = max(1_000_000, currentLiveSessionStreamCursor(for: streamKey))
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

                    yieldLiveSessionUpdate(
                        AgentSessionStreamUpdate(
                            kind: .heartbeat,
                            cursor: currentLiveSessionStreamCursor(for: streamKey),
                            summary: detail.summary
                        ),
                        to: continuation
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
        guard !normalized.isEmpty else {
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
        for event in events where event.runtimeMetadata?.derivedSource == nil {
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
            yieldLiveSessionUpdate(published, to: continuation)
        }
    }

    /// End a lagging connection so consumers resync from persisted history.
    func yieldLiveSessionUpdate(
        _ update: AgentSessionStreamUpdate,
        to continuation: AsyncStream<AgentSessionStreamUpdate>.Continuation
    ) {
        if case .dropped = continuation.yield(update) {
            logger.warning("Session stream overflow; closing connection for history resync")
            continuation.finish()
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
        if (try? getAgentSession(agentID: agentID, sessionID: sessionID).summary.kind) == .longChat {
            throw AgentSessionError.invalidPayload
        }

        guard let normalizedAgentID = normalizedAgentID(agentID) else {
            throw AgentSessionError.invalidAgentID
        }

        guard let normalizedSessionID = normalizedSessionID(sessionID) else {
            throw AgentSessionError.invalidSessionID
        }

        _ = try getAgent(id: normalizedAgentID)

        do {
            try await launches.deleteSession(agentID: normalizedAgentID, sessionID: normalizedSessionID)
            try sessionStore.deleteSession(agentID: normalizedAgentID, sessionID: normalizedSessionID)
            publishLiveSessionClosed(
                agentID: normalizedAgentID,
                sessionID: normalizedSessionID,
                message: "Session was deleted."
            )
            await acpSessionManager.removeSession(agentID: normalizedAgentID, sloppySessionID: normalizedSessionID)
            await toolExecution.cleanupSessionProcesses(normalizedSessionID)
            await toolLoopGuard.cleanup(sessionID: normalizedSessionID)
            sessionExtraRoots.removeValue(forKey: normalizedSessionID)
            sessionWorkingDirectories.removeValue(forKey: normalizedSessionID)
            sessionAddedRoots.removeValue(forKey: normalizedSessionID)
            sessionSubagentToolAllowList.removeValue(forKey: normalizedSessionID)
            sessionToolApprovalBypass.remove(normalizedSessionID)
            sessionToolApprovalRequired.remove(normalizedSessionID)
        } catch {
            throw mapSessionStoreError(error)
        }
    }

    private func replayNativeSessionInput(agentID: String, sessionID: String,
        request: AgentSessionPostMessageRequest, peerOrigin: AgentSessionPeerOrigin?) throws -> AgentSessionMessageResponse? {
        guard let messageID = request.clientMessageId else { return nil }
        let current = activeNativeSessionInputs[sessionStreamKey(agentID: agentID, sessionID: sessionID)]
        let active = current?.messageID == messageID ? current : nil
        let fingerprint = try? NativeSessionDelivery.fingerprint(request, peerOrigin: peerOrigin)
        if let active, fingerprint != active.fingerprint {
            logger.notice("session.native_retry.rejected", metadata: ["session_id": .string(sessionID),
                "message_id": .string(messageID), "reason": .string("active_fingerprint_mismatch"),
                "active_fingerprint": .string(active.fingerprint), "request_fingerprint": .string(fingerprint ?? "unavailable")])
            throw AgentSessionError.invalidPayload
        }
        let detail = try getAgentSession(agentID: agentID, sessionID: sessionID)
        let resolution: NativeSessionDelivery.Resolution
        do { resolution = try NativeSessionDelivery.resolve(request, peerOrigin: peerOrigin, detail: detail) }
        catch {
            logger.error("session.native_retry.resolution_failed", metadata: ["session_id": .string(sessionID),
                "message_id": .string(messageID), "event_count": .stringConvertible(detail.events.count),
                "recorded_user_count": .stringConvertible(detail.events.filter { $0.message?.id == messageID }.count),
                "accepted_fingerprint_matches": .stringConvertible(detail.events.contains {
                    !$0.isHistorical && $0.runtimeMetadata?.inputMessageId == messageID && $0.runtimeMetadata?.requestFingerprint == fingerprint
                }), "error": .string(String(describing: error))])
            throw mapSessionOrchestratorError(error)
        }
        switch resolution {
        case .delivered(let response): return response
        case .unfinished:
            guard active != nil else { return nil }
            return .init(summary: detail.summary, appendedEvents: [], routeDecision: nil, replayed: true)
        case .fresh:
            guard active != nil else { return nil }
            // The original owner has not committed acceptance. Do not acknowledge or queue a second owner.
            logger.notice("session.native_retry.rejected", metadata: ["session_id": .string(sessionID),
                "message_id": .string(messageID), "reason": .string("acceptance_not_committed")])
            throw AgentSessionError.invalidPayload
        }
    }

    /// Appends user message, run-status events and assistant reply into session JSONL.
    public func postAgentSessionMessage(
        agentID: String,
        sessionID: String,
        request: AgentSessionPostMessageRequest,
        longChatWorkerDelivery: Bool = false,
        userMessageAlreadyPersisted: Bool = false,
        peerOrigin: AgentSessionPeerOrigin? = nil,
        inboxDelivery: Bool = false,
        peerConversation: Bool = false
    ) async throws -> AgentSessionMessageResponse {
        guard !nativeDerivedWorkIsStopping, let ownershipLease = await toolApprovalService.currentOwnershipLease(),
              !nativeDerivedWorkIsStopping else { throw AgentSessionError.workspaceUnavailable }
        defer { withExtendedLifetime(ownershipLease) {} }
        var effectiveRequest = AgentSessionOrchestrator.requestByApplyingOneShotModeCommand(request)
        if peerConversation { effectiveRequest.mode = .ask }
        await waitForStartup()
        guard let normalizedAgentID = normalizedAgentID(agentID) else {
            throw AgentSessionError.invalidAgentID
        }

        guard let normalizedSessionID = normalizedSessionID(sessionID) else {
            throw AgentSessionError.invalidSessionID
        }

        _ = try getAgent(id: normalizedAgentID)
        if try getAgentSession(agentID: normalizedAgentID, sessionID: normalizedSessionID).summary.kind == .longChat {
            return try enqueueLongChatMessage(agentID: normalizedAgentID, sessionID: normalizedSessionID, request: effectiveRequest)
        }
        let workerSummary = try getAgentSession(agentID: normalizedAgentID, sessionID: normalizedSessionID).summary
        let hasLongChatParent = workerSummary.parentSessionId.map {
            (try? getAgentSession(agentID: normalizedAgentID, sessionID: $0).summary.kind) == .longChat
        } ?? false
        if !peerConversation, (workerSummary.kind == .longChatWorker || hasLongChatParent), longChatParent(of: normalizedSessionID) == nil {
            throw AgentSessionError.invalidPayload
        }
        if !peerConversation, let (conversation, task) = longChatParent(of: normalizedSessionID) {
            guard task.attempts.last?.sessionId == normalizedSessionID else { throw AgentSessionError.invalidPayload }
            effectiveRequest = try longChatWorkerRequest(conversation: conversation, task: task, request: effectiveRequest)
            if !longChatWorkerDelivery {
                guard effectiveRequest.userId == conversation.userId else { throw AgentSessionError.invalidPayload }
                return try enqueueLongChatWorkerMessage(conversation: conversation, task: task, request: effectiveRequest)
            }
            try await restoreLongChatWorkerScope(agentID: normalizedAgentID, childID: normalizedSessionID)
        }
        if peerConversation && peerOrigin == nil { throw AgentSessionError.invalidPayload }
        if effectiveRequest.clientMessageId == nil {
            let runtime: AgentRuntimeConfig
            do { runtime = try agentCatalogStore.getAgentRuntimeConfig(agentID: normalizedAgentID) }
            catch { throw AgentSessionError.storageFailure }
            if runtime.type == .native, runtime.effectiveNativeEngine == .unified {
                // The ID exposed by the first journal row also belongs to the active owner.
                effectiveRequest.clientMessageId = UUID().uuidString
            }
        }
        if let replay = try replayNativeSessionInput(agentID: normalizedAgentID,
            sessionID: normalizedSessionID, request: effectiveRequest, peerOrigin: peerOrigin) {
            return replay
        }
        await cancelNativeDerivedRuns(sessionID: normalizedSessionID)
        if sessionMessageControlIsActive(agentID: normalizedAgentID, sessionID: normalizedSessionID) {
            if inboxDelivery { throw CancellationError() }
            return try enqueueSessionInboxMessage(agentID: normalizedAgentID, sessionID: normalizedSessionID,
                request: effectiveRequest, origin: peerOrigin)
        }
        if !inboxDelivery {
            let detail = try getAgentSession(agentID: normalizedAgentID, sessionID: normalizedSessionID)
            let pendingInput = NativeSessionDelivery.firstUnfinishedInput(in: detail)
            let pendingID = pendingInput.map { $0.inputMessageId ?? $0.userTurnId }
            let resumesAcceptedInput = pendingID != nil && pendingID == effectiveRequest.clientMessageId
            if activeSessionMessageRuns.contains(normalizedSessionID)
                || (!resumesAcceptedInput && (pendingInput != nil
                    || (!longChatWorkerDelivery && sessionMessageStorage?.entries.contains(where: { $0.sessionId == normalizedSessionID && $0.state == .queued }) == true))) {
                return try enqueueSessionInboxMessage(agentID: normalizedAgentID, sessionID: normalizedSessionID,
                                                     request: effectiveRequest, origin: peerOrigin)
            }
        }
        let ownedInput: NativeSessionDelivery.ActiveInput?
        if let messageID = effectiveRequest.clientMessageId {
            let runtime: AgentRuntimeConfig
            do { runtime = try agentCatalogStore.getAgentRuntimeConfig(agentID: normalizedAgentID) }
            catch { throw AgentSessionError.storageFailure }
            if runtime.type == .native, runtime.effectiveNativeEngine == .unified {
                guard let fingerprint = try? NativeSessionDelivery.fingerprint(effectiveRequest, peerOrigin: peerOrigin) else {
                    throw AgentSessionError.invalidPayload
                }
                ownedInput = .init(messageID: messageID, fingerprint: fingerprint)
            } else { ownedInput = nil }
        } else { ownedInput = nil }
        let inputKey = sessionStreamKey(agentID: normalizedAgentID, sessionID: normalizedSessionID)
        if let ownedInput { activeNativeSessionInputs[inputKey] = ownedInput }
        if !inboxDelivery { activeSessionMessageRuns.insert(normalizedSessionID) }
        activePeerSessionOrigins[normalizedSessionID] = peerOrigin
        defer {
            if let ownedInput, activeNativeSessionInputs[inputKey] == ownedInput {
                activeNativeSessionInputs.removeValue(forKey: inputKey)
            }
            activePeerSessionOrigins.removeValue(forKey: normalizedSessionID)
            if peerConversation { peerConversationSessions.remove(normalizedSessionID) }
            if !inboxDelivery {
                activeSessionMessageRuns.remove(normalizedSessionID)
                scheduleSessionInbox(agentID: normalizedAgentID, sessionID: normalizedSessionID)
            }
        }
        // Own preparation and actor dispatch as well as the model/tool portion of this input.
        let operationID = UUID()
        let admittedRequest = effectiveRequest
        let operation = Task {
            try await self.runAdmittedSessionMessage(agentID: normalizedAgentID, sessionID: normalizedSessionID,
                request: admittedRequest, userMessageAlreadyPersisted: userMessageAlreadyPersisted,
                peerOrigin: peerOrigin, peerConversation: peerConversation)
        }
        sessionMessageOperations[inputKey] = (operationID, operation)
        defer {
            if sessionMessageOperations[inputKey]?.id == operationID { sessionMessageOperations.removeValue(forKey: inputKey) }
        }
        return try await withTaskCancellationHandler {
            try await operation.value
        } onCancel: { operation.cancel() }
    }

    private func runAdmittedSessionMessage(agentID normalizedAgentID: String, sessionID normalizedSessionID: String,
        request effectiveRequest: AgentSessionPostMessageRequest, userMessageAlreadyPersisted: Bool,
        peerOrigin: AgentSessionPeerOrigin?, peerConversation: Bool) async throws -> AgentSessionMessageResponse {
        try Task.checkCancellation()
        try Task.checkCancellation()
        if effectiveRequest.userId == "onboarding" {
            logger.info(
                "onboarding.message.posted",
                metadata: [
                    "agent_id": .string(normalizedAgentID),
                    "session_id": .string(normalizedSessionID),
                    "content_chars": .stringConvertible(effectiveRequest.content.count)
                ]
            )
        }

        if effectiveRequest.mode == .debug {
            do {
                let detail = try sessionStore.loadSession(agentID: normalizedAgentID, sessionID: normalizedSessionID)
                await ensureDebugDirectoryForSessionIfNeeded(
                    chatMode: effectiveRequest.mode,
                    sessionID: normalizedSessionID,
                    sessionTitle: detail.summary.title,
                    projectID: detail.summary.projectId
                )
            } catch {
                throw mapSessionStoreError(error)
            }
        }

        let bypassToolUsageLimits = Self.shouldBypassToolUsageLimits(userID: effectiveRequest.userId)
        if bypassToolUsageLimits {
            sessionToolUsageLimitBypass.insert(normalizedSessionID)
        }
        defer {
            if bypassToolUsageLimits {
                sessionToolUsageLimitBypass.remove(normalizedSessionID)
            }
        }

        do {
            if !["system_task_worker", "memory_checkpoint", "onboarding", "goal", "goal_loop"].contains(effectiveRequest.userId.lowercased()) {
                await toolLoopGuard.beginTurn(sessionID: normalizedSessionID)
            }
            // Test-only suspension at the existing awaited preparation boundary.
            if let observer = sessionMessagePreparationForTests { await observer() }
            if let execution = projectExecutionSessions[normalizedSessionID] {
                let pickupEnabled = await store.project(id: execution.projectID)?.automaticTaskPickupEnabled == true
                guard pickupEnabled, execution.generation == projectStopGenerations[execution.projectID, default: 0] else {
                    throw CancellationError()
                }
            }
            try Task.checkCancellation()
            let response = try await sessionOrchestrator.postMessage(
                agentID: normalizedAgentID,
                sessionID: normalizedSessionID,
                request: effectiveRequest,
                userMessageAlreadyPersisted: userMessageAlreadyPersisted,
                additionalContext: SessionCommunicationPolicy.instructions + (peerConversation
                    ? "\n[Communication turn] The delegated task is closed. Discuss evidence only; do not change resources or call agent_delegate.finish."
                    : ""),
                peerOrigin: peerOrigin, peerConversation: peerConversation
            )
            if response.replayed == true { return response }
            if !peerConversation { await reconcileLongChatWorker(agentID: normalizedAgentID, childID: normalizedSessionID) }
            let uid = effectiveRequest.userId.lowercased()
            let resumedInput = effectiveRequest.clientMessageId.flatMap { id in
                (try? sessionStore.loadSession(agentID: normalizedAgentID, sessionID: normalizedSessionID))
                    .map { NativeSessionDelivery.isResumedInput(id, in: $0) }
            } ?? false
            let skipUserTurnCount = resumedInput || uid == "system_task_worker" || uid == "memory_checkpoint" || uid == "onboarding" || uid == "goal" || uid == "goal_loop"
            if !skipUserTurnCount && peerOrigin == nil {
                do {
                    let count = try sessionStore.incrementUserTurnCount(
                        agentID: normalizedAgentID,
                        sessionID: normalizedSessionID
                    )
                    if count >= CoreService.agentMemoryCheckpointUserTurnThreshold {
                        await scheduleAgentMemoryCheckpoint(
                            agentID: normalizedAgentID,
                            sessionID: normalizedSessionID,
                            reason: "user_turn_threshold"
                        )
                    }
                } catch {
                    logger.warning(
                        "memory.checkpoint.user_turn_count_failed",
                        metadata: ["error": .string(error.localizedDescription)]
                    )
                }
            }
            if peerOrigin == nil {
                maybeScheduleSelfImprovementProposalReviewAfterTurn(
                    agentID: normalizedAgentID,
                    sessionID: normalizedSessionID,
                    response: response,
                    userID: effectiveRequest.userId
                )
                await scheduleGoalContinuationIfNeeded(
                    agentID: normalizedAgentID,
                    sessionID: normalizedSessionID,
                    request: effectiveRequest,
                    response: response
                )
            }
            await reconcileWorkflowAgentSession(agentID: normalizedAgentID, sessionID: normalizedSessionID, response: response)
            return response
        } catch {
            logger.error("session.message.failed", metadata: ["agent_id": .string(normalizedAgentID),
                "session_id": .string(normalizedSessionID), "message_id": .string(effectiveRequest.clientMessageId ?? "generated"),
                "error": .string(String(describing: error))])
            // Internal delivery settlement needs the typed stop before API error mapping.
            if error is CancellationError { throw error }
            if let failure = error as? ModelStepFailure, failure.category == .cancelled { throw failure }
            throw mapSessionOrchestratorError(error)
        }
    }

    public func startAgentSessionGoal(
        agentID: String,
        sessionID: String,
        request: AgentSessionGoalStartRequest
    ) async throws -> AgentSessionGoalRecord {
        await waitForStartup()
        guard let normalizedAgentID = normalizedAgentID(agentID) else {
            throw AgentSessionError.invalidAgentID
        }
        guard let normalizedSessionID = normalizedSessionID(sessionID) else {
            throw AgentSessionError.invalidSessionID
        }
        _ = try getAgent(id: normalizedAgentID)
        _ = try getAgentSession(agentID: normalizedAgentID, sessionID: normalizedSessionID)

        let objective = request.objective.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !objective.isEmpty else {
            throw AgentSessionError.invalidPayload
        }

        let goal = await sessionGoalController.start(
            agentID: normalizedAgentID,
            sessionID: normalizedSessionID,
            objective: objective,
            maxAttempts: request.maxAttempts ?? 8
        )
        let userID = request.userId.trimmingCharacters(in: .whitespacesAndNewlines)
        _ = try await postAgentSessionMessage(
            agentID: normalizedAgentID,
            sessionID: normalizedSessionID,
            request: AgentSessionPostMessageRequest(
                userId: userID.isEmpty ? "goal" : userID,
                content: SloppyTUIGoalPromptFormatter.initialPrompt(objective: objective),
                reasoningEffort: request.reasoningEffort,
                mode: request.mode
            )
        )
        return (await sessionGoalController.goal(agentID: normalizedAgentID, sessionID: normalizedSessionID)) ?? goal
    }

    public func getAgentSessionGoal(agentID: String, sessionID: String) async throws -> AgentSessionGoalRecord? {
        guard let normalizedAgentID = normalizedAgentID(agentID) else {
            throw AgentSessionError.invalidAgentID
        }
        guard let normalizedSessionID = normalizedSessionID(sessionID) else {
            throw AgentSessionError.invalidSessionID
        }
        return await sessionGoalController.goal(agentID: normalizedAgentID, sessionID: normalizedSessionID)
    }

    public func pauseAgentSessionGoal(agentID: String, sessionID: String) async throws -> AgentSessionGoalRecord? {
        guard let normalizedAgentID = normalizedAgentID(agentID) else {
            throw AgentSessionError.invalidAgentID
        }
        guard let normalizedSessionID = normalizedSessionID(sessionID) else {
            throw AgentSessionError.invalidSessionID
        }
        return await sessionGoalController.pause(agentID: normalizedAgentID, sessionID: normalizedSessionID)
    }

    public func resumeAgentSessionGoal(agentID: String, sessionID: String) async throws -> AgentSessionGoalRecord? {
        guard let normalizedAgentID = normalizedAgentID(agentID) else {
            throw AgentSessionError.invalidAgentID
        }
        guard let normalizedSessionID = normalizedSessionID(sessionID) else {
            throw AgentSessionError.invalidSessionID
        }
        guard let goal = await sessionGoalController.resume(agentID: normalizedAgentID, sessionID: normalizedSessionID) else {
            return nil
        }
        if goal.status == .active {
            _ = try await postAgentSessionMessage(
                agentID: normalizedAgentID,
                sessionID: normalizedSessionID,
                request: AgentSessionPostMessageRequest(
                    userId: "goal_loop",
                    content: SloppyTUIGoalPromptFormatter.continuationPrompt(goal: goal)
                )
            )
        }
        return await sessionGoalController.goal(agentID: normalizedAgentID, sessionID: normalizedSessionID)
    }

    public func clearAgentSessionGoal(agentID: String, sessionID: String) async throws -> AgentSessionGoalRecord? {
        guard let normalizedAgentID = normalizedAgentID(agentID) else {
            throw AgentSessionError.invalidAgentID
        }
        guard let normalizedSessionID = normalizedSessionID(sessionID) else {
            throw AgentSessionError.invalidSessionID
        }
        return await sessionGoalController.clear(agentID: normalizedAgentID, sessionID: normalizedSessionID)
    }

    private func scheduleGoalContinuationIfNeeded(
        agentID: String,
        sessionID: String,
        request: AgentSessionPostMessageRequest,
        response: AgentSessionMessageResponse
    ) async {
        let userID = request.userId.lowercased()
        guard userID == "goal" || userID == "goal_loop" else {
            return
        }
        guard let evaluation = await sessionGoalController.evaluateTurn(
            agentID: agentID,
            sessionID: sessionID,
            events: response.appendedEvents
        ),
              evaluation.shouldContinue,
              let prompt = evaluation.continuationPrompt?.trimmingCharacters(in: .whitespacesAndNewlines),
              !prompt.isEmpty
        else {
            return
        }

        Task { [weak self] in
            do {
                _ = try await self?.postAgentSessionMessage(
                    agentID: agentID,
                    sessionID: sessionID,
                    request: AgentSessionPostMessageRequest(
                        userId: "goal_loop",
                        content: prompt,
                        reasoningEffort: request.reasoningEffort,
                        mode: request.mode
                    )
                )
            } catch {
                self?.logger.warning(
                    "session.goal.continuation_failed",
                    metadata: [
                        "agent_id": .string(agentID),
                        "session_id": .string(sessionID),
                        "error": .string(error.localizedDescription)
                    ]
                )
            }
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

        let interrupting = request.action == .interrupt || request.action == .interruptTree
        var targets: [String] = []
        var queuedAtAdmission: Set<String> = []
        var queuedCancellations: [String: [AgentInputTransition]] = [:]
        var controlEventIDs: [String: String] = [:]
        var barrierKeys: [String] = []
        defer {
            for key in barrierKeys {
                let depth = sessionControlDepth[key, default: 0]
                if depth <= 1 { sessionControlDepth.removeValue(forKey: key) }
                else { sessionControlDepth[key] = depth - 1 }
            }
            if !barrierKeys.isEmpty {
                for target in targets { scheduleSessionInbox(agentID: normalizedAgentID, sessionID: target) }
            }
        }
        do {
            let summaries = request.action == .interruptTree
                ? try sessionStore.listSessions(agentID: normalizedAgentID, includeHeartbeat: true) : []
            targets = AgentSessionOrchestrator.controlTargetSessionIDs(sessionID: normalizedSessionID,
                action: request.action, sessions: summaries)
            let targetIDs = Set(targets)
            queuedAtAdmission = interrupting ? Set(try sessionMessageInbox().entries.filter {
                $0.agentId == normalizedAgentID && targetIDs.contains($0.sessionId) && $0.state == .queued
            }.map(\.id)) : []
            if interrupting {
                for target in targets {
                    let detail = try sessionStore.loadSession(agentID: normalizedAgentID, sessionID: target)
                    let queued = try SessionInputLifecycle.states(in: detail.events).values
                        .filter { $0.latest.disposition == .queued && $0.owner == nil }
                        .sorted { $0.latest.messageId < $1.latest.messageId }
                    queuedCancellations[target] = queued.map {
                        .init(messageId: $0.latest.messageId, fingerprint: $0.latest.fingerprint,
                            disposition: .cancelled, delivery: .delivered)
                    }
                    queuedAtAdmission.formUnion(queued.map(\.latest.messageId))
                }
            }
            controlEventIDs = Dictionary(uniqueKeysWithValues: targets.map { ($0, UUID().uuidString) })
            barrierKeys = interrupting ? targets.map { sessionStreamKey(agentID: normalizedAgentID, sessionID: $0) } : []
            for key in barrierKeys { sessionControlDepth[key, default: 0] += 1 }
            if interrupting { for target in targets { await cancelNativeDerivedRuns(sessionID: target) } }
            let operations: [String: Task<AgentSessionMessageResponse, Error>] = interrupting
                ? Dictionary(uniqueKeysWithValues: targets.compactMap { target in
                    guard let operation = sessionMessageOperations[sessionStreamKey(agentID: normalizedAgentID, sessionID: target)] else { return nil }
                    return (target, operation.task)
                }) : [:]
            if interrupting, let observer = sessionControlAdmissionForTests { await observer() }
            let response = try await sessionOrchestrator.controlSession(
                agentID: normalizedAgentID, sessionID: normalizedSessionID, request: request,
                targetSessionIDs: targets, controlEventIDs: controlEventIDs,
                queuedInputCancellations: queuedCancellations,
                onInterruptAccepted: { target in operations[target]?.cancel() })
            if interrupting {
                let interruptedIDs = Set(response.appendedEvents.map(\.sessionId))
                try cancelQueuedSessionMessages(agentID: normalizedAgentID, sessionIDs: interruptedIDs, inputIDs: queuedAtAdmission)
                for target in interruptedIDs { await toolExecution.cleanupSessionProcesses(target) }
            }
            await reconcileWorkflowAgentSession(agentID: normalizedAgentID, sessionID: normalizedSessionID)
            return response
        } catch {
            if interrupting {
                // A tree can stop earlier targets before a later target fails. Honor those
                // exact durable controls while the admission barrier is still held.
                let interruptedIDs = Set(targets.filter { target in
                    guard let eventID = controlEventIDs[target],
                          let detail = try? sessionStore.loadSession(agentID: normalizedAgentID, sessionID: target) else { return false }
                    return detail.events.contains { !$0.isHistorical && $0.id == eventID &&
                        $0.type == .runControl && $0.runControl?.action == request.action }
                })
                try cancelQueuedSessionMessages(agentID: normalizedAgentID, sessionIDs: interruptedIDs, inputIDs: queuedAtAdmission)
                for target in interruptedIDs { await toolExecution.cleanupSessionProcesses(target) }
            }
            throw mapSessionOrchestratorError(error)
        }
    }

    private func cancelQueuedSessionMessages(agentID: String, sessionIDs: Set<String>, inputIDs: Set<String>) throws {
        guard !sessionIDs.isEmpty else { return }
        for target in sessionIDs { sessionMessageRunners[target]?.cancel() }
        guard !inputIDs.isEmpty else { return }
        let storage = try sessionMessageInbox()
        try storage.transaction { entries in
            for index in entries.indices where entries[index].agentId == agentID &&
                sessionIDs.contains(entries[index].sessionId) && inputIDs.contains(entries[index].id) && entries[index].state == .queued {
                entries[index].state = .failed
                entries[index].error = "Session interrupted by the user before delivery."
            }
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

    func addChannelSessionDirectory(
        channelID: String,
        request: AgentSessionDirectoryRequest
    ) async throws -> AgentSessionDirectoryResponse {
        let normalizedChannelID = channelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedChannelID.isEmpty else {
            throw AgentSessionError.invalidSessionID
        }

        let existingContext = await toolContextForChannel(channelID: normalizedChannelID)
        let resolvedPath = try resolvedSessionDirectoryPath(
            request.path,
            baseDirectory: existingContext.workingDirectory
        )
        let workingDirectory = existingContext.workingDirectory ?? resolvedPath
        let roots = appendingUniqueRoot(resolvedPath, to: existingContext.extraRoots)
        channelAddedRoots[normalizedChannelID] = appendingUniqueRoot(
            resolvedPath,
            to: channelAddedRoots[normalizedChannelID] ?? []
        )

        channelExtraRoots[normalizedChannelID] = roots
        channelWorkingDirectories[normalizedChannelID] = workingDirectory

        return AgentSessionDirectoryResponse(
            path: resolvedPath,
            workingDirectory: workingDirectory,
            directories: roots
        )
    }

    func resolvedSessionDirectoryPath(_ rawPath: String, baseDirectory: String?) throws -> String {
        var trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AgentSessionError.invalidPayload
        }

        if (trimmed.hasPrefix("\"") && trimmed.hasSuffix("\"")) ||
            (trimmed.hasPrefix("'") && trimmed.hasSuffix("'")) {
            trimmed = String(trimmed.dropFirst().dropLast())
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !trimmed.isEmpty else {
            throw AgentSessionError.invalidPayload
        }

        let expanded = (trimmed as NSString).expandingTildeInPath
        let candidate: URL
        if (expanded as NSString).isAbsolutePath {
            candidate = URL(fileURLWithPath: expanded, isDirectory: true)
        } else {
            let base = baseDirectory?.trimmingCharacters(in: .whitespacesAndNewlines)
            let basePath = base?.isEmpty == false ? base! : workspaceRootURL.path
            let baseURL = URL(fileURLWithPath: basePath, isDirectory: true)
            candidate = baseURL.appendingPathComponent(expanded, isDirectory: true)
        }

        let resolved = candidate.resolvingSymlinksInPath().standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: resolved.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            throw AgentSessionError.invalidPayload
        }
        return resolved.path
    }

    func appendingUniqueRoot(_ root: String, to roots: [String]) -> [String] {
        var result = roots
        if !result.contains(root) {
            result.append(root)
        }
        var seen = Set<String>()
        return result.filter { seen.insert($0).inserted }
    }

    private static func paginatedAgentSessions(
        _ sessions: [AgentSessionSummary],
        limit: Int?,
        offset: Int
    ) -> [AgentSessionSummary] {
        let start = min(max(0, offset), sessions.count)
        let tail = sessions[start...]
        guard let limit else {
            return Array(tail)
        }
        return Array(tail.prefix(max(0, limit)))
    }

    private static func shouldBypassToolUsageLimits(userID: String) -> Bool {
        let normalized = userID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "tui" || normalized == "onboarding"
    }

}

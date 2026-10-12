import Foundation
import Observation
import SloppyClientCore
import SloppyClientUI
import SwiftUI
import UniformTypeIdentifiers

extension ChatScreenViewModel {
    func disconnectCurrentSession() {
        cancelDictationIfNeeded()
        let manager = socketManager
        if let agentId = selectedAgent?.id,
           let sessionId = selectedSessionId ?? activeComposerDraftKey,
           isSending || !messageQueue.isEmpty {
            let key = deliveryKey(agentId: agentId, sessionId: sessionId)
            suspendedDeliveries[key] = SuspendedChatDelivery(
                queue: messageQueue, optimisticMessages: transcript.optimisticMessages,
                isSending: isSending,
                isAwaitingResponse: isAwaitingAgentResponse || isStopping || pendingToolApproval != nil || activeInputRequest != nil,
                selectedModel: ChatModelSelection.requestOverride(for: selectedModelId),
                reasoningEffort: selectedModelSupportsReasoningEffort ? selectedReasoningEffort.payloadValue : nil
            )
            if let streamTask { backgroundStreams[key] = (manager, streamTask) }
        } else {
            streamTask?.cancel()
            if let manager { Task { await manager.disconnect() } }
        }
        hydrationGeneration &+= 1
        earlierMessagesTask?.cancel()
        earlierMessagesTask = nil
        isLoadingEarlierMessages = false
        transcriptLoadError = nil
        historyPage = nil
        latestHydratedEventIDs = nil
        isEarlierPageLoadError = false
        hydrationTask?.cancel()
        hydrationTask = nil
        hydrationRequested = false
        streamStateRevision &+= 1
        streamCursorTracker = ChatStreamCursorTracker()
        usageRefreshTask?.cancel()
        usageRefreshTask = nil
        approvalRefreshTask?.cancel()
        approvalRefreshTask = nil
        isSending = false
        streamTask = nil
        cancelPendingStreamingAssistantText()
        clearActiveStreamingAssistantTurn()
        socketManager = nil
        isAwaitingAgentResponse = false
        isStopping = false
        isLoadingTranscript = false
        activeInputRequest = nil
        isSubmittingInputResponse = false
        inputRequestErrorMessage = nil
        pendingToolApproval = nil
        toolApprovalErrorMessage = nil
        activeRunStatus = nil
        contextTokenUsage = nil
        semanticDecisionUsage = nil
        computerUseActivity = nil
        isComputerUsePreviewHidden = false
        clearWorkingTreeSourceControl()
        messageQueue = ChatMessageQueue()
        queuedMessages = []
        resolvedToolApprovalIDs = []
    }

    func connectToSession(agentId: String, sessionId: String) async {
        guard isCurrentSession(agentId: agentId, sessionId: sessionId) else { return }
        defer {
            if isCurrentSession(agentId: agentId, sessionId: sessionId) {
                isLoadingTranscript = false
            }
        }

        if let cached = await cacheStore.loadSessionDetail(agentId: agentId, sessionId: sessionId) {
            guard isCurrentSession(agentId: agentId, sessionId: sessionId) else { return }
            applyHydratedSession(cached)
            historyPage = cached.historyPage
        }

        let key = deliveryKey(agentId: agentId, sessionId: sessionId)
        backgroundHydrationIDs.removeValue(forKey: key)
        backgroundHydrations.removeValue(forKey: key)?.cancel()
        if let delivery = suspendedDeliveries.removeValue(forKey: key) {
            messageQueue = delivery.queue
            queuedMessages = delivery.queue.messages
            isSending = delivery.isSending
            isAwaitingAgentResponse = delivery.isAwaitingResponse
            sendErrorMessage = delivery.errorMessage
            for message in delivery.optimisticMessages { transcript.upsert(message) }
        }
        if let (manager, task) = backgroundStreams.removeValue(forKey: key) {
            socketManager = manager
            streamTask = task
            requestSessionHydration(agentId: agentId, sessionId: sessionId)
            await hydrationTask?.value
            await sendNextQueuedMessageIfIdle()
            return
        }

        let manager: SessionSocketManager?
        let stream: AsyncStream<ChatStreamUpdate>
        if let sessionStreamProvider {
            manager = nil
            stream = await sessionStreamProvider(agentId, sessionId)
        } else {
            let socket = SessionSocketManager(endpoint: apiClient.endpoint, agentId: agentId, sessionId: sessionId)
            manager = socket
            socketManager = socket
            stream = await socket.connect()
        }
        guard isCurrentSession(agentId: agentId, sessionId: sessionId) else {
            await manager?.disconnect()
            return
        }
        // Keep delivery alive if the tab releases its view model while messages are queued.
        // Disconnect/cancellation releases this ownership when the stream ends.
        streamTask = Task { @MainActor in
            defer { Task { await manager?.disconnect() } }
            for await update in stream {
                guard !Task.isCancelled else { return }
                if self.isCurrentSession(agentId: agentId, sessionId: sessionId) {
                    self.handleStreamUpdate(update, agentId: agentId, sessionId: sessionId)
                } else {
                    self.handleBackgroundStreamUpdate(update, agentId: agentId, sessionId: sessionId)
                }
            }
        }
        // Consume live events while history and auxiliary data are fetched.
        requestSessionHydration(agentId: agentId, sessionId: sessionId)
        await hydrationTask?.value
        await sendNextQueuedMessageIfIdle()
    }

    private func requestSessionHydration(agentId: String, sessionId: String) {
        guard isCurrentSession(agentId: agentId, sessionId: sessionId) else { return }
        hydrationRequested = true
        guard hydrationTask == nil else { return }
        let generation = hydrationGeneration
        hydrationTask = Task { @MainActor in
            defer { if hydrationGeneration == generation { hydrationTask = nil } }
            while hydrationRequested && !Task.isCancelled {
                hydrationRequested = false
                await hydrateSession(agentId: agentId, sessionId: sessionId)
            }
        }
    }

    func hydrateSession(agentId: String, sessionId: String) async {
        let generation = hydrationGeneration
        let revision = streamStateRevision
        var detail: ChatSessionDetail
        do {
            detail = try await apiClient.fetchAgentSession(agentId: agentId, sessionId: sessionId, eventLimit: 64)
            // Status-only pages cannot be scrolled. Find the first renderable
            // history page while keeping the latest control-state snapshot.
            while transcript.isEmpty, detail.messages.isEmpty,
                  let page = detail.historyPage, page.hasMore, let before = page.nextBefore {
                let earlier = try await apiClient.fetchAgentSession(
                    agentId: agentId, sessionId: sessionId, eventLimit: 64, before: before
                )
                guard generation == hydrationGeneration, !Task.isCancelled else { return }
                detail.events.insert(contentsOf: earlier.events, at: 0)
                detail.historyPage = earlier.historyPage
            }
        } catch {
            guard generation == hydrationGeneration, !Task.isCancelled else { return }
            transcriptLoadError = error.localizedDescription
            isEarlierPageLoadError = false
            isLoadingTranscript = false
            return
        }
        guard generation == hydrationGeneration else { return }
        guard isCurrentSession(agentId: agentId, sessionId: sessionId) else { return }
        guard !Task.isCancelled else { return }
        applyHydratedSession(detail, appliesStatus: revision == streamStateRevision)
        isLoadingTranscript = false
        transcriptLoadError = nil
        let incomingIDs = Set(detail.events.isEmpty ? detail.messages.map(\.id) : detail.events.map(\.id))
        // After a long disconnect the new tail can be disjoint from the loaded
        // history. Move the cursor to that gap so scrolling can recover it.
        if latestHydratedEventIDs == nil
            || (!incomingIDs.isEmpty && latestHydratedEventIDs?.isDisjoint(with: incomingIDs) == true) {
            historyPage = detail.historyPage
        }
        latestHydratedEventIDs = incomingIDs
        scheduleAuxiliaryRefresh(agentId: agentId, sessionId: sessionId)
        await sendNextQueuedMessageIfIdle()
        await cacheStore.cacheSessionDetail(agentId: agentId, detail: detail)
    }

    /// A single request per upper-edge crossing; loaded history survives tail refreshes.
    public func loadEarlierMessages() {
        guard !isLoadingTranscript, !isLoadingEarlierMessages else { return }
        if transcript.hasEarlierMessages {
            transcript.revealEarlierMessages()
            return
        }
        guard let agentID = selectedAgent?.id, let sessionID = selectedSessionId,
              historyPage?.hasMore == true, let before = historyPage?.nextBefore else { return }
        let generation = hydrationGeneration
        isLoadingEarlierMessages = true
        transcriptLoadError = nil
        earlierMessagesTask = Task { @MainActor in
            defer {
                if generation == hydrationGeneration {
                    isLoadingEarlierMessages = false
                    earlierMessagesTask = nil
                }
            }
            do {
                var detail = try await apiClient.fetchAgentSession(
                    agentId: agentID, sessionId: sessionID, eventLimit: 64, before: before
                )
                while detail.messages.isEmpty, let page = detail.historyPage,
                      page.hasMore, let nextBefore = page.nextBefore, nextBefore != before {
                    guard generation == hydrationGeneration, !Task.isCancelled else { return }
                    detail = try await apiClient.fetchAgentSession(
                        agentId: agentID, sessionId: sessionID, eventLimit: 64, before: nextBefore
                    )
                }
                guard generation == hydrationGeneration, !Task.isCancelled,
                      isCurrentSession(agentId: agentID, sessionId: sessionID) else { return }
                transcript.reconcile(with: detail.messages, revealingEarlier: true)
                historyPage = detail.historyPage
            } catch {
                guard generation == hydrationGeneration, !Task.isCancelled else { return }
                transcriptLoadError = error.localizedDescription
                isEarlierPageLoadError = true
            }
        }
    }

    public func retryTranscriptLoad() {
        if !isEarlierPageLoadError, let agentID = selectedAgent?.id, let sessionID = selectedSessionId {
            isLoadingTranscript = true
            requestSessionHydration(agentId: agentID, sessionId: sessionID)
        } else {
            loadEarlierMessages()
        }
    }

    private func applyHydratedSession(_ detail: ChatSessionDetail, appliesStatus: Bool = true) {
        let messages = detail.messages
        let optimisticIDs = Set(transcript.optimisticMessages.map(\.id))
        for message in messages where message.role == .user && optimisticIDs.contains("optimistic-user-\(message.id)") {
            transcript.acknowledgeUserMessage(message)
        }
        if appliesStatus, let status = detail.latestRunStatus, !status.stage.isWorking,
           let placeholderID = currentStreamingAssistantMessageId(for: detail.summary.id),
           let placeholder = transcript.messages.first(where: { $0.id == placeholderID }),
           let final = messages.last(where: { $0.role == .assistant && $0.createdAt >= placeholder.createdAt }) {
            transcript.replaceStreamingAssistant(messageId: placeholderID, with: final)
            cancelPendingStreamingAssistantText(for: detail.summary.id)
        }
        transcript.reconcile(with: messages)
        guard appliesStatus else { return }
        if let runStatus = detail.latestRunStatus {
            handleRunStatus(runStatus, sessionId: detail.summary.id)
        } else {
            refreshWorkingTreeSourceControl()
        }
        let previousInputRequestID = activeInputRequest?.id
        activeInputRequest = detail.pendingInputRequest
        if activeInputRequest?.id != previousInputRequestID {
            inputRequestErrorMessage = nil
        }
        if activeInputRequest != nil {
            isAwaitingAgentResponse = false
        }
        for presentation in detail.planArtifactPresentations {
            presentPlanArtifactIfNeeded(presentation)
        }
    }

    private func presentPlanArtifactIfNeeded(_ presentation: ChatPlanArtifactPresentation) {
        guard presentedPlanArtifactEventIDs.insert(presentation.eventID).inserted else { return }
        onPlanArtifact(presentation)
    }

    func handleStreamUpdate(
        _ update: ChatStreamUpdate,
        agentId: String,
        sessionId: String
    ) {
        guard isCurrentSession(agentId: agentId, sessionId: sessionId) else { return }
        if streamCursorTracker.observe(update) {
            requestSessionHydration(agentId: agentId, sessionId: sessionId)
        }
        if update.kind == .sessionEvent { streamStateRevision &+= 1 }
        switch update.kind {
        case .sessionReady:
            if hydrationTask == nil {
                requestSessionHydration(agentId: agentId, sessionId: sessionId)
            }
        case .sessionEvent, .sessionDelta:
            if update.kind == .sessionDelta, let text = update.messageText {
                scheduleStreamingAssistantText(text, sessionId: sessionId, mode: .append)
            } else if let msg = update.message {
                upsertMessage(msg, sessionId: sessionId)
                updateComputerUseActivity(from: msg)
            }
            if let runStatus = update.streamEvent?.runStatus {
                handleRunStatus(runStatus, sessionId: sessionId)
                if runStatus.selectedModel != nil {
                    scheduleAuxiliaryRefresh(agentId: agentId, sessionId: sessionId)
                }
            }
            if let inputRequest = update.streamEvent?.inputRequest {
                flushPendingStreamingAssistantText()
                streamingTurnTracker.completeNextTurn(for: sessionId)
                activeInputRequest = inputRequest
                inputRequestErrorMessage = nil
                isAwaitingAgentResponse = false
                isStopping = false
            }
            if let inputResponse = update.streamEvent?.inputResponse,
               inputResponse.requestId == activeInputRequest?.id {
                activeInputRequest = nil
                inputRequestErrorMessage = nil
            }
        case .sessionClosed, .sessionError:
            isAwaitingAgentResponse = false
            isStopping = false
            activeRunStatus = nil
            flushPendingStreamingAssistantText()
            streamingTurnTracker.clear(sessionId: sessionId)
            refreshWorkingTreeSourceControl()
        case .heartbeat:
            break
        }
    }

    func isCurrentSession(agentId: String, sessionId: String) -> Bool {
        selectedAgent?.id == agentId && selectedSessionId == sessionId
    }

    private func upsertMessage(_ message: ChatMessage, sessionId: String) {
        let isAssistantResponse = message.role == .assistant
            && message.segments.contains(where: { $0.kind == .text })

        if isAssistantResponse {
            cancelPendingStreamingAssistantText(for: sessionId)
            if let streamingMessageId = streamingTurnTracker.claimFinalMessageId(for: sessionId) {
                transcript.replaceStreamingAssistant(
                    messageId: streamingMessageId,
                    with: message
                )
            } else {
                transcript.upsert(message)
            }
            speakFinishedReply(message)
            return
        } else if message.role == .user {
            transcript.acknowledgeUserMessage(message)
            return
        }

        transcript.upsert(
            message,
            before: currentStreamingAssistantMessageId(for: sessionId)
        )
    }

    private func updateComputerUseActivity(from message: ChatMessage) {
        let previousActivity = computerUseActivity
        computerUseActivity = ChatComputerUseEventReducer.reduce(
            current: computerUseActivity,
            message: message
        )
        if previousActivity == nil, computerUseActivity != nil {
            isComputerUsePreviewHidden = false
        }
    }

    enum StreamingTextUpdateMode {
        case append
        case replace
    }

    func scheduleStreamingAssistantText(
        _ text: String,
        sessionId: String,
        mode: StreamingTextUpdateMode
    ) {
        guard !text.isEmpty else { return }
        let messageId = ensureActiveStreamingAssistantTurn(for: sessionId)
        if let pendingMessageId = pendingStreamingAssistantMessageId,
           pendingMessageId != messageId {
            flushPendingStreamingAssistantText()
        }
        pendingStreamingSessionId = sessionId
        pendingStreamingAssistantMessageId = messageId
        isAwaitingAgentResponse = true
        switch mode {
        case .append:
            pendingStreamingAssistantText = (pendingStreamingAssistantText ?? "") + text
            if pendingStreamingTextUpdateMode != .replace {
                pendingStreamingTextUpdateMode = .append
            }
        case .replace:
            pendingStreamingAssistantText = text
            pendingStreamingTextUpdateMode = .replace
        }

        guard streamingFlushTask == nil else {
            return
        }

        streamingFlushTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 33_000_000)
            guard !Task.isCancelled else { return }
            flushPendingStreamingAssistantText()
        }
    }

    func flushPendingStreamingAssistantText() {
        streamingFlushTask?.cancel()
        streamingFlushTask = nil
        guard pendingStreamingSessionId != nil,
              let messageId = pendingStreamingAssistantMessageId,
              let text = pendingStreamingAssistantText,
              let mode = pendingStreamingTextUpdateMode else {
            streamingFlushTask = nil
            return
        }

        pendingStreamingSessionId = nil
        pendingStreamingAssistantMessageId = nil
        pendingStreamingAssistantText = nil
        pendingStreamingTextUpdateMode = nil
        streamingFlushTask = nil
        applyStreamingAssistantText(text, messageId: messageId, mode: mode)
    }

    private func cancelPendingStreamingAssistantText(for sessionId: String? = nil) {
        guard sessionId == nil || pendingStreamingSessionId == sessionId else {
            return
        }

        streamingFlushTask?.cancel()
        streamingFlushTask = nil
        pendingStreamingSessionId = nil
        pendingStreamingAssistantMessageId = nil
        pendingStreamingAssistantText = nil
        pendingStreamingTextUpdateMode = nil
    }

    private func applyStreamingAssistantText(
        _ text: String,
        messageId: String,
        mode: StreamingTextUpdateMode
    ) {
        switch mode {
        case .append:
            transcript.appendStreamingAssistantText(text, messageId: messageId)
        case .replace:
            transcript.upsert(
                ChatMessage(
                    id: messageId,
                    role: .assistant,
                    segments: [ChatMessageSegment(kind: .text, text: text)]
                )
            )
        }
    }
}

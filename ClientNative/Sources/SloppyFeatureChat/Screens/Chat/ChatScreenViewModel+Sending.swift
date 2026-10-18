import Foundation
import Observation
import SloppyClientCore
import SloppyClientUI
import SwiftUI
import UniformTypeIdentifiers

extension ChatScreenViewModel {
    public func prepareLaunch() {
        guard let agent = selectedAgent, selectedSessionId != nil,
              !isSending, !isAwaitingAgentResponse, activeInputRequest == nil else { return }
        sendMessageImmediately(
            content: "Prepare Play for the result of this chat. Inspect the exact checkout/worktree and runnable projects you worked on. Save verified build and launch recipes using session.launch.configure, with one configuration per target (web, macOS app, or iOS Simulator). Recommend the target relevant to this work. Use current uncommitted files. Do not merge, deploy, or install into /Applications. If this is only a library with no runnable target, explain that clearly.",
            attachments: [], quotes: [], agent: agent, clearsComposer: false, references: []
        )
    }

    @discardableResult
    public func sendMessage(content: String) -> Bool {
        guard let agent = selectedAgent,
              activeInputRequest == nil else {
            return false
        }
        let attachments = composerAttachments
        let quotes = composerQuotes
        guard !content.isEmpty || !attachments.isEmpty || !quotes.isEmpty else { return false }

        requestComposerFocus()
        if willQueueMessage {
            enqueueMessage(content: content, attachments: attachments, quotes: quotes)
            Task { @MainActor in
                await sendNextQueuedMessageIfIdle()
            }
            return true
        }

        sendMessageImmediately(content: content, attachments: attachments, quotes: quotes, agent: agent)
        return true
    }

    public func cancelQueuedMessage(id: UUID) {
        messageQueue.cancel(id: id)
        queuedMessages = messageQueue.messages
    }

    private func enqueueMessage(
        content: String,
        attachments: [ChatComposerAttachment],
        quotes: [ChatComposerQuote]
    ) {
        messageQueue.enqueue(content: content, attachments: attachments, quotes: quotes, references: composerDraft.references)
        queuedMessages = messageQueue.messages
        clearActiveComposerDraft()
    }

    private func sendMessageImmediately(
        content: String,
        attachments: [ChatComposerAttachment],
        quotes: [ChatComposerQuote],
        agent: APIAgentRecord,
        clearsComposer: Bool = true,
        references: [ChatComposerReference]? = nil
    ) {
        let references = references ?? composerDraft.references
        let messageContent = ChatComposerQuote.messageContent(content, quotes: quotes, attachments: attachments)
        sendErrorMessage = nil
        clearWorkingTreeSourceControl()
        if clearsComposer { clearActiveComposerDraft() }
        streamStateRevision &+= 1
        isSending = true
        isAwaitingAgentResponse = true
        activeRunStatus = nil
        Task { @MainActor [responseNotificationScheduler] in
            await responseNotificationScheduler.prepareAuthorization()
        }
        var optimisticSegments: [ChatMessageSegment] = []
        if !messageContent.isEmpty {
            optimisticSegments.append(ChatMessageSegment(kind: .text, text: messageContent))
        }
        optimisticSegments += attachments.map {
            ChatMessageSegment(kind: .attachment, attachment: $0.messageAttachment)
        }
        let clientMessageId = UUID().uuidString
        let sendModel = ChatModelSelection.requestOverride(for: selectedModelId)
        let sendReasoningEffort = selectedModelSupportsReasoningEffort ? selectedReasoningEffort.payloadValue : nil
        let optimistic = ChatMessage(
            id: "optimistic-user-\(clientMessageId)",
            role: .user,
            segments: optimisticSegments
        )
        if let sessionId = selectedSessionId {
            beginStreamingAssistantTurn(for: sessionId)
        }
        transcript.append(optimistic)

        if selectedSessionId == nil {
            let originDraftKey = activeComposerDraftKey
            let projectId = activeProjectId
            let taskId = activeTaskId
            let separateChat = createsSeparateProjectChat
            Task { @MainActor in
                do {
                    let summary = try await apiClient.createAgentSession(
                        agentId: agent.id,
                        title: taskId.map(taskSessionTitle(for:)),
                        projectId: projectId,
                        taskId: taskId,
                        separateChat: separateChat
                    )
                    upsertSessionSummary(summary)
                    guard selectedAgent?.id == agent.id, selectedSessionId == nil,
                          activeComposerDraftKey == originDraftKey else {
                        if let originDraftKey {
                            let oldKey = deliveryKey(agentId: agent.id, sessionId: originDraftKey)
                            let newKey = deliveryKey(agentId: agent.id, sessionId: summary.id)
                            suspendedDeliveries[newKey] = suspendedDeliveries.removeValue(forKey: oldKey)
                        }
                        await postMessage(
                            content: messageContent, draftContent: content, attachments: attachments,
                            quotes: quotes, agentId: agent.id, sessionId: summary.id, optimistic: optimistic,
                            selectedModel: sendModel, reasoningEffort: sendReasoningEffort, references: references
                        )
                        return
                    }
                    selectedSessionId = summary.id
                    rememberCurrentModelSelection(agentId: agent.id, sessionId: summary.id)
                    beginStreamingAssistantTurn(for: summary.id)
                    settings.lastSessionId = summary.id
                    syncComposerDraft(
                        toSessionId: summary.id,
                        projectId: activeProjectId,
                        taskId: activeTaskId,
                        agentId: agent.id
                    )
                    await connectToSession(agentId: agent.id, sessionId: summary.id)
                    await postMessage(
                        content: messageContent,
                        draftContent: content,
                        attachments: attachments,
                        quotes: quotes,
                        agentId: agent.id,
                        sessionId: summary.id,
                        optimistic: optimistic, selectedModel: sendModel, reasoningEffort: sendReasoningEffort, references: references
                    )
                } catch {
                    guard selectedAgent?.id == agent.id, selectedSessionId == nil,
                          activeComposerDraftKey == originDraftKey else {
                        if let originDraftKey {
                            composerDraftsByKey[originDraftKey] = StoredComposerDraft(text: content, attachments: attachments, quotes: quotes, references: references)
                            let key = deliveryKey(agentId: agent.id, sessionId: originDraftKey)
                            suspendedDeliveries[key]?.isSending = false
                            suspendedDeliveries[key]?.isAwaitingResponse = false
                            suspendedDeliveries[key]?.errorMessage = "Could not create session: \(error.localizedDescription)"
                        }
                        return
                    }
                    isSending = false
                    isAwaitingAgentResponse = false
                    activeRunStatus = nil
                    transcript.removeAll { $0.id == optimistic.id }
                    restoreComposerDraft(content: content, attachments: attachments, quotes: quotes, references: references)
                    sendErrorMessage = "Could not create session: \(error.localizedDescription)"
                }
            }
            return
        }

        guard let sessionId = selectedSessionId else { return }
        Task { @MainActor in
            await postMessage(
                content: messageContent,
                draftContent: content,
                attachments: attachments,
                quotes: quotes,
                agentId: agent.id,
                sessionId: sessionId,
                optimistic: optimistic, selectedModel: sendModel, reasoningEffort: sendReasoningEffort, references: references
            )
        }
    }

    public func submitInputResponse(_ answers: [ChatPlanInputAnswer]) {
        answerInputRequest(status: .answered, answers: answers)
    }

    public func cancelInputRequest() {
        answerInputRequest(status: .cancelled, answers: [])
    }

    private func answerInputRequest(
        status: ChatPlanInputResponseStatus,
        answers: [ChatPlanInputAnswer]
    ) {
        guard let agentId = selectedAgent?.id,
              let sessionId = selectedSessionId,
              let inputRequest = activeInputRequest,
              !isSubmittingInputResponse else {
            return
        }

        isSubmittingInputResponse = true
        clearWorkingTreeSourceControl()
        inputRequestErrorMessage = nil
        if status == .answered {
            _ = ensureActiveStreamingAssistantTurn(for: sessionId)
        }
        Task { @MainActor in
            defer { isSubmittingInputResponse = false }
            do {
                let summary = try await apiClient.answerSessionInputRequest(
                    agentId: agentId,
                    sessionId: sessionId,
                    requestId: inputRequest.id,
                    request: ChatPlanInputAnswerRequest(
                        status: status,
                        answers: answers
                    )
                )
                guard isCurrentSession(agentId: agentId, sessionId: sessionId),
                      activeInputRequest?.id == inputRequest.id else {
                    return
                }
                activeInputRequest = nil
                upsertSessionSummary(summary)
                if status == .answered {
                    isAwaitingAgentResponse = true
                    activeRunStatus = nil
                }
                await hydrateSession(agentId: agentId, sessionId: sessionId)
            } catch {
                guard isCurrentSession(agentId: agentId, sessionId: sessionId),
                      activeInputRequest?.id == inputRequest.id else {
                    return
                }
                if status == .answered {
                    streamingTurnTracker.completeNextTurn(for: sessionId)
                }
                inputRequestErrorMessage = "Answers were not sent: \(error.localizedDescription)"
            }
        }
    }

    private func postMessage(
        content: String,
        draftContent: String,
        attachments: [ChatComposerAttachment],
        quotes: [ChatComposerQuote],
        agentId: String,
        sessionId: String,
        optimistic: ChatMessage,
        selectedModel: String?,
        reasoningEffort: String?,
        references: [ChatComposerReference] = []
    ) async {
        let key = deliveryKey(agentId: agentId, sessionId: sessionId)
        defer {
            if isCurrentSession(agentId: agentId, sessionId: sessionId) {
                isSending = false
                Task { @MainActor in
                    guard isCurrentSession(agentId: agentId, sessionId: sessionId) else { return }
                    await sendNextQueuedMessageIfIdle()
                }
            } else {
                suspendedDeliveries[key]?.isSending = false
                drainBackgroundQueue(agentId: agentId, sessionId: sessionId)
            }
        }
        do {
            let receipt = try await apiClient.postSessionMessageWithReceipt(
                agentId: agentId, sessionId: sessionId, content: content,
                attachments: attachments.map(\.upload), selectedModel: selectedModel,
                reasoningEffort: reasoningEffort,
                clientMessageId: String(optimistic.id.dropFirst("optimistic-user-".count))
            )
            upsertSessionSummary(receipt.summary)
            let persisted = receipt.appendedEvents.compactMap(\.message).first { $0.role == .user }
            if isCurrentSession(agentId: agentId, sessionId: sessionId) {
                // Older Core versions do not echo clientMessageId; the POST receipt still
                // identifies precisely which optimistic submission was persisted.
                if let persisted {
                    transcript.acknowledgeUserMessage(persisted, optimisticID: optimistic.id)
                }
                await hydrateSession(agentId: agentId, sessionId: sessionId)
            } else {
                if persisted != nil {
                    suspendedDeliveries[key]?.optimisticMessages.removeAll { $0.id == optimistic.id }
                }
                if let status = receipt.appendedEvents.compactMap(\.runStatus).last {
                    suspendedDeliveries[key]?.isAwaitingResponse = status.stage.isWorking || status.stage == .paused
                    if status.stage == .paused {
                        refreshBackgroundDelivery(agentId: agentId, sessionId: sessionId)
                    }
                }
            }
        } catch {
            let isCurrent = isCurrentSession(agentId: agentId, sessionId: sessionId)
            let isPresent = isCurrent
                ? transcript.optimisticMessages.contains { $0.id == optimistic.id }
                : suspendedDeliveries[key]?.optimisticMessages.contains { $0.id == optimistic.id } == true
            guard ChatMessageSendFailurePolicy.shouldRestoreDraft(
                after: error, optimisticMessageIsPresent: isPresent
            ) else { return }
            let errorMessage = "Message was not sent: \(error.localizedDescription)"
            if isCurrent {
                transcript.removeAll { $0.id == optimistic.id }
                isAwaitingAgentResponse = false
                activeRunStatus = nil
                restoreComposerDraft(content: draftContent, attachments: attachments, quotes: quotes, references: references)
                sendErrorMessage = errorMessage
            } else {
                suspendedDeliveries[key]?.optimisticMessages.removeAll { $0.id == optimistic.id }
                suspendedDeliveries[key]?.isAwaitingResponse = false
                suspendedDeliveries[key]?.errorMessage = errorMessage
                composerDraftsByKey["session:\(sessionId)"] = StoredComposerDraft(
                    text: draftContent, attachments: attachments, quotes: quotes, references: references
                )
            }
        }
    }

    func deliveryKey(agentId: String, sessionId: String) -> String {
        "\(agentId):\(sessionId)"
    }

    func handleBackgroundStreamUpdate(_ update: ChatStreamUpdate, agentId: String, sessionId: String) {
        let key = deliveryKey(agentId: agentId, sessionId: sessionId)
        guard suspendedDeliveries[key] != nil else { return }
        if update.kind == .sessionReady || update.kind == .heartbeat || update.kind == .sessionError {
            refreshBackgroundDelivery(agentId: agentId, sessionId: sessionId)
        }
        if update.kind == .sessionEvent { suspendedDeliveries[key]?.revision &+= 1 }
        if let message = update.message, message.role == .user {
            suspendedDeliveries[key]?.optimisticMessages.removeAll { $0.id == "optimistic-user-\(message.id)" }
        }
        if let status = update.streamEvent?.runStatus {
            if status.stage == .paused { refreshBackgroundDelivery(agentId: agentId, sessionId: sessionId) }
            suspendedDeliveries[key]?.isAwaitingResponse = status.stage.isWorking || status.stage == .paused
        }
        if update.streamEvent?.inputRequest != nil {
            suspendedDeliveries[key]?.isAwaitingResponse = true
        }
        drainBackgroundQueue(agentId: agentId, sessionId: sessionId)
    }

    private func refreshBackgroundDelivery(agentId: String, sessionId: String) {
        let key = deliveryKey(agentId: agentId, sessionId: sessionId)
        guard backgroundHydrations[key] == nil, let revision = suspendedDeliveries[key]?.revision else { return }
        let requestID = UUID()
        backgroundHydrationIDs[key] = requestID
        backgroundHydrations[key] = Task { @MainActor in
            defer {
                if backgroundHydrationIDs[key] == requestID {
                    backgroundHydrationIDs[key] = nil
                    backgroundHydrations[key] = nil
                }
            }
            guard let detail = try? await apiClient.fetchAgentSession(agentId: agentId, sessionId: sessionId, eventLimit: 64),
                  !Task.isCancelled, suspendedDeliveries[key]?.revision == revision else { return }
            if let status = detail.latestRunStatus {
                var blocked = status.stage.isWorking || detail.pendingInputRequest != nil
                if status.stage == .paused {
                    guard let approvals = try? await apiClient.fetchPendingToolApprovals(),
                          !Task.isCancelled, suspendedDeliveries[key]?.revision == revision else { return }
                    blocked = blocked || approvals.contains {
                        $0.status == "pending" && ($0.displaySessionId == sessionId || $0.sessionId == sessionId)
                            && ($0.agentId == nil || $0.agentId == agentId)
                    }
                }
                suspendedDeliveries[key]?.isAwaitingResponse = blocked
            }
            let persistedIDs = Set(detail.messages.filter { $0.role == .user }.map { "optimistic-user-\($0.id)" })
            suspendedDeliveries[key]?.optimisticMessages.removeAll { persistedIDs.contains($0.id) }
            drainBackgroundQueue(agentId: agentId, sessionId: sessionId)
        }
    }

    private func drainBackgroundQueue(agentId: String, sessionId: String) {
        let key = deliveryKey(agentId: agentId, sessionId: sessionId)
        guard var delivery = suspendedDeliveries[key], !delivery.isSending,
              !delivery.isAwaitingResponse else { return }
        guard let message = delivery.queue.dequeue() else {
            if let (manager, task) = backgroundStreams.removeValue(forKey: key) {
                task.cancel()
                Task { await manager?.disconnect() }
            }
            return
        }
        let content = ChatComposerQuote.messageContent(message.content, quotes: message.quotes, attachments: message.attachments)
        let optimistic = ChatMessage(
            id: "optimistic-user-\(UUID().uuidString)", role: .user,
            segments: (content.isEmpty ? [] : [ChatMessageSegment(kind: .text, text: content)])
                + message.attachments.map { ChatMessageSegment(kind: .attachment, attachment: $0.messageAttachment) }
        )
        delivery.isSending = true
        delivery.isAwaitingResponse = true
        delivery.optimisticMessages.append(optimistic)
        suspendedDeliveries[key] = delivery
        Task { @MainActor in
            await postMessage(
                content: content, draftContent: message.content, attachments: message.attachments,
                quotes: message.quotes, agentId: agentId, sessionId: sessionId, optimistic: optimistic,
                selectedModel: delivery.selectedModel, reasoningEffort: delivery.reasoningEffort, references: message.references
            )
        }
    }

    func sendNextQueuedMessageIfIdle() async {
        guard !isSending,
              !isAwaitingAgentResponse,
              !isStopping,
              !isDrainingQueuedMessages,
              approvalRefreshTask == nil,
              activeInputRequest == nil,
              pendingToolApproval == nil,
              let agent = selectedAgent,
              let message = messageQueue.dequeue() else {
            return
        }

        isDrainingQueuedMessages = true
        queuedMessages = messageQueue.messages
        sendMessageImmediately(
            content: message.content,
            attachments: message.attachments,
            quotes: message.quotes,
            agent: agent, clearsComposer: false, references: message.references
        )
        isDrainingQueuedMessages = false
    }
}

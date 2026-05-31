import Foundation
#if canImport(AppKit)
import AppKit
#endif
import ChannelPluginSupport
import Logging
import Protocols
import TauTUI

@MainActor
extension SloppyTUIScreen {
    func updateLiveAssistantDraftTarget(_ target: String) {
        guard !target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        let current = liveAssistantDraft ?? ""
        if !SloppyTUILiveDraftPolicy.shouldInterpolate(current: current, target: target) {
            setLiveAssistantDraftImmediately(target)
            return
        }

        liveAssistantTarget = target
        if liveAssistantDraft == nil {
            liveAssistantDraft = ""
        }
        startLiveAssistantInterpolation()
    }

    func setLiveAssistantDraftImmediately(_ value: String) {
        liveAssistantInterpolationTask?.cancel()
        liveAssistantInterpolationTask = nil
        liveAssistantTarget = value
        liveAssistantDraft = value
        renderTimeline()
    }

    func settleLiveAssistantDraft() {
        liveAssistantInterpolationTask?.cancel()
        liveAssistantInterpolationTask = nil
        if let liveAssistantTarget {
            liveAssistantDraft = liveAssistantTarget
        }
        liveAssistantTarget = nil
        renderTimeline()
    }

    func clearLiveAssistantDraft() {
        liveAssistantInterpolationTask?.cancel()
        liveAssistantInterpolationTask = nil
        liveAssistantTarget = nil
        liveAssistantDraft = nil
        renderTimeline()
    }

    func startLiveAssistantInterpolation() {
        guard liveAssistantInterpolationTask == nil else {
            advanceLiveAssistantInterpolation()
            return
        }

        liveAssistantInterpolationTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: SloppyTUIStreamTyping.intervalNanoseconds)
                guard !Task.isCancelled else { break }
                await MainActor.run {
                    self?.advanceLiveAssistantInterpolation()
                }
            }
        }
        advanceLiveAssistantInterpolation()
    }

    func advanceLiveAssistantInterpolation() {
        guard let target = liveAssistantTarget, let current = liveAssistantDraft else {
            liveAssistantInterpolationTask?.cancel()
            liveAssistantInterpolationTask = nil
            return
        }
        guard current != target else {
            liveAssistantInterpolationTask?.cancel()
            liveAssistantInterpolationTask = nil
            return
        }
        guard target.hasPrefix(current) else {
            setLiveAssistantDraftImmediately(target)
            return
        }

        let remaining = target.count - current.count
        let baseCharacters = max(
            1,
            Int(ceil(SloppyTUIStreamTyping.charactersPerSecond * SloppyTUIStreamTyping.intervalSeconds))
        )
        let catchupTicks = max(
            1,
            Int(ceil(SloppyTUIStreamTyping.maxCatchupSeconds / SloppyTUIStreamTyping.intervalSeconds))
        )
        let catchupCharacters = max(baseCharacters, Int(ceil(Double(remaining) / Double(catchupTicks))))
        let nextCount = current.count + min(remaining, catchupCharacters)
        let next = String(target.prefix(nextCount))
        liveAssistantDraft = next
        renderTimeline()
        if next == target {
            liveAssistantInterpolationTask?.cancel()
            liveAssistantInterpolationTask = nil
        }
    }

    func startThinkingAnimation() {
        thinkingAnimationTask?.cancel()
        thinkingFrame = 0
        thinkingWord = SloppyTUITheme.waitingWord(seed: session.id + String(Date().timeIntervalSince1970))
        thinkingAnimationTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 220_000_000)
                guard !Task.isCancelled else { break }
                await MainActor.run {
                    guard let self, self.liveAssistantDraft != nil else { return }
                    self.thinkingFrame += 1
                    self.renderTimeline()
                }
            }
        }
    }

    func updateSendProgress(_ progress: SloppyTUISendProgress) {
        liveRunStage = nil
        liveRunStatusLine = progress.statusLine
        markSendTiming(progress.stage.rawValue)
        refreshStaticChrome()
        renderTimeline()
    }

    func resetSendTiming() {
        let now = Date()
        sendTimingStart = now
        sendTimingLast = now
        sendTimingFirstStreamEventMarked = false
        sendTimingFirstModelChunkMarked = false
        sendTimingFirstToolCallMarked = false
        logger.debug("tui.send_timing start")
    }

    func markFirstStreamEventIfNeeded() {
        guard !sendTimingFirstStreamEventMarked else { return }
        sendTimingFirstStreamEventMarked = true
        markSendTiming("first_stream_event")
    }

    func markFirstModelChunkIfNeeded() {
        guard !sendTimingFirstModelChunkMarked else { return }
        sendTimingFirstModelChunkMarked = true
        markSendTiming("first_model_chunk")
    }

    func markFirstToolCallIfNeeded() {
        guard !sendTimingFirstToolCallMarked else { return }
        sendTimingFirstToolCallMarked = true
        markSendTiming("first_tool_call")
    }

    func markSendTiming(_ stage: String) {
        guard let start = sendTimingStart else { return }
        let now = Date()
        let previous = sendTimingLast ?? start
        sendTimingLast = now
        let elapsedMs = Int(now.timeIntervalSince(start) * 1000)
        let deltaMs = Int(now.timeIntervalSince(previous) * 1000)
        logger.debug(
            "tui.send_timing \(stage)",
            metadata: [
                "elapsed_ms": .stringConvertible(elapsedMs),
                "delta_ms": .stringConvertible(deltaMs),
                "agent_id": .string(agent.id),
                "session_id": .string(session.id)
            ]
        )
    }

    func stopThinkingAnimation() {
        thinkingAnimationTask?.cancel()
        thinkingAnimationTask = nil
        thinkingFrame = 0
        thinkingWord = "thinking"
    }

    func appendLocalCard(_ text: String, autoDismissAfter seconds: TimeInterval? = nil) {
        nextLocalCardID += 1
        let id = nextLocalCardID
        localCards.append(SloppyTUILocalCard(id: id, block: .local(text)))
        if localCards.count > 24 {
            let removed = localCards.prefix(localCards.count - 24)
            for card in removed {
                localCardDismissTasks.removeValue(forKey: card.id)?.cancel()
            }
            localCards.removeFirst(localCards.count - 24)
        }
        let dismissAfter = seconds ?? inferredLocalCardDismissDelay(for: text)
        if let dismissAfter {
            scheduleLocalCardDismissal(id: id, after: dismissAfter)
        }
        renderTimeline()
    }

    func dismissFirstStartBootstrapCard() {
        dismissLocalCards { block in
            if case .local(let text) = block.block {
                return text == Self.firstStartBootstrapCard
            }
            return false
        }
    }

    func dismissModelSwitchCards() {
        dismissLocalCards { block in
            if case .local(let text) = block.block {
                return text.hasPrefix("Model switched to ")
            }
            return false
        }
    }

    func clearLocalCards() {
        cancelLocalCardDismissTasks()
        localCards.removeAll()
        workspaceDiffPreview = nil
    }

    func dismissLocalCardsForUserMessage() {
        transientNoticeTask?.cancel()
        transientNoticeTask = nil
        transientNoticeLine = nil
        clearLocalCards()
    }

    func dismissLocalCards(where shouldDismiss: (SloppyTUILocalCard) -> Bool) {
        let removedIDs = localCards.filter(shouldDismiss).map(\.id)
        guard !removedIDs.isEmpty else { return }
        for id in removedIDs {
            localCardDismissTasks.removeValue(forKey: id)?.cancel()
        }
        localCards.removeAll(where: shouldDismiss)
    }

    func scheduleLocalCardDismissal(id: Int, after seconds: TimeInterval) {
        localCardDismissTasks[id]?.cancel()
        localCardDismissTasks[id] = Task { [weak self] in
            let nanoseconds = UInt64(max(0, seconds) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self else { return }
                self.localCardDismissTasks[id] = nil
                self.localCards.removeAll { $0.id == id }
                self.renderTimeline()
            }
        }
    }

    func cancelLocalCardDismissTasks() {
        for task in localCardDismissTasks.values {
            task.cancel()
        }
        localCardDismissTasks.removeAll()
    }

    func inferredLocalCardDismissDelay(for text: String) -> TimeInterval? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return SloppyTUILocalCardBehavior.autoDismissSeconds }
        let lines = trimmed.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count <= SloppyTUILocalCardBehavior.autoDismissLineLimit,
              trimmed.count <= SloppyTUILocalCardBehavior.autoDismissCharacterLimit,
              !trimmed.hasPrefix("## ")
        else {
            return nil
        }
        return SloppyTUILocalCardBehavior.autoDismissSeconds
    }

    func showSystemNotice(_ text: String, autoDismissAfter seconds: TimeInterval = 6) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        transientNoticeLine = value
        transientNoticeTask?.cancel()
        transientNoticeTask = Task { [weak self] in
            let nanoseconds = UInt64(max(0, seconds) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.transientNoticeLine == value else { return }
                self.transientNoticeLine = nil
                self.transientNoticeTask = nil
                self.refreshStaticChrome()
            }
        }
        refreshStaticChrome()
    }

    func refreshStaticChrome(statusLine: String? = nil) {
        header.text = SloppyTUITheme.header(
            project: project.name,
            agent: agent.displayName,
            session: SloppyTUITheme.sessionHeaderTitle(session)
        )
        let context = pendingContext == nil ? "" : "  context: queued"
        let attachments = pendingUploads.isEmpty ? "" : "  attachments: \(pendingUploads.count)"
        let queue = queuedMessages.isEmpty ? "" : "  queue: \(queuedMessages.count) ctrl+b cancel"
        let pet = state.petEnabled ? "  pet: \(terminalPetFace())" : ""
        let transcript = transcriptExpanded ? "  transcript: full" : ""
        let parent = session.parentSessionId == nil ? "" : "  parent: ctrl+p"
        let elapsed = elapsedStatusContext()
        let defaultStatus = SloppyTUITheme.sessionStatusLine(
            context: context + queue + pet + transcript + parent + elapsed.idleSuffix,
            attachments: attachments,
            sessionID: hasPersistedSession ? session.id : "not created"
        )
        let busyStatus = (statusLine ?? shellRunStatusLine ?? liveRunStatusLine).map { $0 + elapsed.busySuffix }
        status.text = SloppyTUITheme.status(
            busyStatus ?? defaultStatus,
            isBusy: busyStatus != nil
        )
        refreshTerminalTitle()
        requestRender()
    }

    func refreshTerminalTitle() {
        terminal?.write(SloppyTUITheme.terminalTitleEscape(
            SloppyTUITheme.terminalTitle(
                status: terminalTitleStatus(),
                session: session,
                agent: agent.displayName
            )
        ))
    }

    func terminalTitleStatus() -> String {
        if isInterruptingRun {
            return "interrupting"
        }
        if isRunningShellCommand {
            return "shell"
        }
        if let liveRunStage {
            return liveRunStage.rawValue
        }
        if pendingPlanInputRequest != nil {
            return "waiting"
        }
        if isPosting {
            return "sending"
        }
        if shellModeEnabled {
            return "shell"
        }
        return hasPersistedSession ? "idle" : "draft"
    }

    func elapsedStatusContext() -> (busySuffix: String, idleSuffix: String) {
        if let taskStartedAt {
            let elapsed = SloppyTUITheme.elapsed(Date().timeIntervalSince(taskStartedAt))
            return ("  elapsed: \(elapsed)", "  elapsed: \(elapsed)")
        }
        if let lastTaskElapsed {
            return ("", "  last run: \(SloppyTUITheme.elapsed(lastTaskElapsed))")
        }
        return ("", "")
    }

    func runStatusLine(_ status: AgentRunStatusEvent) -> String {
        let label = status.label.trimmingCharacters(in: .whitespacesAndNewlines)
        let details = status.details?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !label.isEmpty, !details.isEmpty {
            return "\(label) - \(details)"
        }
        if !label.isEmpty {
            return label
        }
        return status.stage.rawValue
    }

    func notifyForRunStatus(_ status: AgentRunStatusEvent) {
        switch status.stage {
        case .done:
            let body = sessionDisplayNotificationBody(fallback: status.details)
            let metadata = [
                "source": "tui",
                "agentId": agent.id,
                "sessionId": session.id
            ]
            Task {
                await desktopNotificationService.notify(
                    category: "session_done",
                    title: "Sloppy finished",
                    body: body,
                    metadata: metadata
                )
            }
        case .paused:
            let label = status.label.trimmingCharacters(in: .whitespacesAndNewlines)
            if label.caseInsensitiveCompare("Waiting for input") == .orderedSame {
                return
            }
            let isToolApproval = label.localizedCaseInsensitiveContains("approval")
            let body = sessionDisplayNotificationBody(fallback: status.details)
            let metadata = [
                "source": "tui",
                "agentId": agent.id,
                "sessionId": session.id
            ]
            Task {
                await desktopNotificationService.notify(
                    category: isToolApproval ? "tool_approval" : "input_required",
                    title: isToolApproval ? "Tool approval required" : "Input required",
                    body: body,
                    metadata: metadata
                )
            }
        case .thinking, .searching, .responding, .interrupted:
            break
        }
    }

    func notifyForInputRequest(_ inputRequest: PlanInputRequest) {
        let body = sessionDisplayNotificationBody(fallback: inputRequest.title)
        let metadata = [
            "source": "tui",
            "agentId": agent.id,
            "sessionId": session.id,
            "requestId": inputRequest.id
        ]
        Task {
            await desktopNotificationService.notify(
                category: "input_required",
                title: "Input required",
                body: body,
                metadata: metadata
            )
        }
    }

    func sessionDisplayNotificationBody(fallback: String?) -> String {
        let fallbackText = fallback?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !fallbackText.isEmpty {
            return fallbackText
        }
        let title = SloppyTUITheme.sessionDisplayTitle(session).trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty {
            return title
        }
        return agent.displayName
    }

    func terminalPetFace() -> String {
        guard let faceSet = agent.pet?.visual?.terminalFaceSet else {
            return "(o_o)"
        }
        switch petMood {
        case .happy, .interacted:
            return faceSet.happy
        case .sad:
            return faceSet.sad
        case .sleep:
            return faceSet.sleep
        default:
            return faceSet.idle
        }
    }

    func refreshSelectedModel() async {
        let config = try? await service.getAgentConfig(agentID: agent.id)
        selectedModel = config?.selectedModel ?? "default"
        selectedModelContextWindowTokens = config.map {
            contextWindowTokens(for: selectedModel, in: $0.availableModels)
        } ?? 0
        await refreshTokenUsage(includeCost: true)
        refreshStaticChrome()
    }

    func requestRender() {
        tui?.requestRender()
    }

    var shouldRenderWelcome: Bool {
        SloppyTUIWelcomeVisibility.shouldRender(
            welcomeDismissed: welcomeDismissed,
            hasPersistedSession: hasPersistedSession,
            hasSessionCards: !sessionCards.isEmpty,
            hasLiveAssistantDraft: liveAssistantDraft != nil,
            hasQueuedMessages: !queuedMessages.isEmpty,
            hasLocalCards: !localCards.isEmpty,
            hasTransientNotice: transientNoticeLine != nil
        )
    }
}

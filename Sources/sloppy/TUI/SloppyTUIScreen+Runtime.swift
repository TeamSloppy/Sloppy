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
    func streamSession() {
        guard hasPersistedSession else {
            streamTask?.cancel()
            streamTask = nil
            sessionStreamReadyKey = nil
            resumeSessionStreamReadyWaiters()
            return
        }
        streamTask?.cancel()
        sessionStreamReadyKey = nil
        let streamKey = currentSessionStreamKey()
        streamTask = Task { [weak self] in
            guard let self else { return }
            do {
                let stream = try await self.service.streamAgentSessionEvents(agentID: self.agent.id, sessionID: self.session.id)
                for await update in stream {
                    guard !Task.isCancelled else { break }
                    await MainActor.run {
                        if update.kind == .sessionReady {
                            self.markSessionStreamReady(streamKey: streamKey)
                        } else if update.kind == .sessionDelta, let message = update.message {
                            self.markFirstStreamEventIfNeeded()
                            self.markFirstModelChunkIfNeeded()
                            self.updateLiveAssistantDraftTarget(message)
                        } else if update.kind == .sessionEvent, let event = update.event {
                            self.markFirstStreamEventIfNeeded()
                            if event.toolCall != nil {
                                self.markFirstToolCallIfNeeded()
                                self.lastAgentToolActivityAt = Date()
                            }
                            if event.toolResult != nil {
                                self.lastAgentToolActivityAt = Date()
                            }
                            var shouldRefreshTokenUsageAfterRun = false
                            if let status = event.runStatus {
                                if let tokenUsage = status.tokenUsage {
                                    self.lastTurnTokenUsage = tokenUsage
                                }
                                if status.stage == .done || status.stage == .interrupted {
                                    self.liveRunStage = nil
                                    self.liveRunStatusLine = nil
                                    self.markSendTiming("final_status")
                                    shouldRefreshTokenUsageAfterRun = true
                                } else {
                                    self.liveRunStage = status.stage
                                    self.liveRunStatusLine = self.runStatusLine(status)
                                }
                                self.refreshStaticChrome()
                                self.notifyForRunStatus(status)
                            }
                            if let inputRequest = event.inputRequest {
                                self.settleLiveAssistantDraft()
                                self.notifyForInputRequest(inputRequest)
                            }
                            if self.isFinalAssistantMessage(event) {
                                self.clearLiveAssistantDraft()
                                self.stopThinkingAnimation()
                            }
                            Task {
                                if shouldRefreshTokenUsageAfterRun {
                                    await self.refreshTokenUsage(includeCost: true)
                                }
                                await self.reloadSession()
                            }
                        } else if update.kind == .sessionClosed {
                            self.clearLiveAssistantDraft()
                            self.stopThinkingAnimation()
                            self.appendLocalCard(update.message ?? "Session closed.")
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    self.markSessionStreamReady(streamKey: streamKey)
                    self.appendLocalCard("Session stream failed: \(String(describing: error))")
                }
            }
        }
    }

    func waitForCurrentSessionStreamReady() async {
        guard hasPersistedSession else { return }
        let streamKey = currentSessionStreamKey()
        if sessionStreamReadyKey == streamKey {
            return
        }
        if streamTask == nil {
            streamSession()
        }
        await withCheckedContinuation { continuation in
            sessionStreamReadyWaiters.append(continuation)
        }
    }

    func markSessionStreamReady(streamKey: String) {
        guard streamKey == currentSessionStreamKey() else { return }
        sessionStreamReadyKey = streamKey
        resumeSessionStreamReadyWaiters()
    }

    func resumeSessionStreamReadyWaiters() {
        let waiters = sessionStreamReadyWaiters
        sessionStreamReadyWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }

    func currentSessionStreamKey() -> String {
        "\(agent.id):\(session.id)"
    }

    func streamChanges() {
        changeTask?.cancel()
        changeTask = Task { [weak self] in
            guard let self else { return }
            do {
                let stream = try await self.service.streamProjectWorkingTreeChanges(projectID: self.project.id)
                for await batch in stream {
                    guard !Task.isCancelled else { break }
                    await MainActor.run {
                        self.lastChangeBatch = batch
                        self.scheduleProjectSourceControlFooterRefresh()
                        self.scheduleAutoDiffPreview(for: batch)
                        self.scheduleProjectFileReindex()
                    }
                }
            } catch {
                // Keep workspace watching silent so the timeline only shows agent output.
            }
        }
    }

    func scheduleProjectSourceControlFooterRefresh() {
        projectSourceControlFooterTask?.cancel()
        let service = service
        let projectID = project.id
        projectSourceControlFooterTask = Task { [weak self] in
            do {
                let sourceControl = try await service.projectWorkingTreeSourceControl(projectID: projectID)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self, self.project.id == projectID else { return }
                    self.updateProjectSourceControlFooter(sourceControl)
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self, self.project.id == projectID else { return }
                    self.projectSourceControlFooterStatus = SloppyTUISourceControlFooterStatus(
                        providerId: self.project.sourceControlProviderId,
                        isRepository: false,
                        message: String(describing: error)
                    )
                    self.refreshStaticChrome()
                }
            }
        }
    }

    func updateProjectSourceControlFooter(_ sourceControl: ProjectWorkingTreeSourceControlResponse) {
        projectSourceControlFooterStatus = SloppyTUISourceControlFooterStatus(sourceControl)
        refreshStaticChrome()
    }

    func scheduleAutoDiffPreview(for batch: ProjectWorkingTreeChangeBatch) {
        guard shouldAutoShowDiff(for: batch) else {
            return
        }

        autoDiffTask?.cancel()
        autoDiffTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled, let self else { return }
            do {
                let sourceControl = try await self.service.projectWorkingTreeSourceControl(projectID: self.project.id)
                let rootURL = try? await self.service.resolveProjectWorkspaceRoot(projectID: self.project.id)
                await MainActor.run {
                    self.updateAutoDiffPreview(sourceControl, rootURL: rootURL)
                }
            } catch {
                // Diff preview is opportunistic; /diff remains available for explicit errors.
            }
        }
    }

    func shouldAutoShowDiff(for batch: ProjectWorkingTreeChangeBatch) -> Bool {
        guard !batch.changes.isEmpty else {
            return false
        }
        if isPosting || liveRunStatusLine != nil {
            return true
        }
        guard let lastAgentToolActivityAt else {
            return false
        }
        return Date().timeIntervalSince(lastAgentToolActivityAt) < 45
    }

    func updateAutoDiffPreview(_ sourceControl: ProjectWorkingTreeSourceControlResponse, rootURL: URL?) {
        updateProjectSourceControlFooter(sourceControl)
        if let rootURL,
           updateSessionDiffPreview(rootURL: rootURL) {
            return
        }

        dismissAutoDiffPreview()
    }

    @discardableResult
    func updateSessionDiffPreview(rootURL: URL) -> Bool {
        guard hasPersistedSession,
              let sessionDiff = try? sessionUndoManagers.sessionDiff(
                  sessionID: session.id,
                  rootURL: rootURL,
                  maxCharacters: 96 * 1024
              ),
              sessionDiff.hasChanges else {
            return false
        }

        workspaceDiffPreview = SloppyTUIWorkspaceDiffPreview(
            branch: "session",
            linesAdded: sessionDiff.linesAdded,
            linesDeleted: sessionDiff.linesDeleted,
            diff: sessionDiff.diff,
            truncated: sessionDiff.truncated
        )
        renderTimeline()
        return true
    }

    func dismissAutoDiffPreview() {
        guard workspaceDiffPreview != nil else {
            return
        }
        workspaceDiffPreview = nil
        renderTimeline()
    }

    func loadProjectFileIndex() {
        projectFileIndexTask?.cancel()
        projectFileIndexLoading = true
        requestRender()
        projectFileIndexTask = Task { [weak self] in
            guard let self else { return }
            do {
                if service.isRemote {
                    let entries = try await service.searchProjectFiles(projectID: project.id, query: "", limit: ProjectFileIndex.defaultLimit)
                    applyProjectFileIndex(ProjectFileIndex(
                        projectId: project.id,
                        rootPath: "remote:\(project.id)",
                        truncated: entries.count >= ProjectFileIndex.defaultLimit,
                        entries: entries.map { ProjectFileIndexEntry(path: $0.path, type: $0.type) }
                    ))
                    return
                }
                let rootURL = try await service.resolveProjectWorkspaceRoot(projectID: project.id)
                projectFileRootURL = rootURL

                let additionalRoots = indexedAdditionalDirectoryURLs(projectRootURL: rootURL)
                let rootPath = projectFileIndexRootPath(rootURL: rootURL, additionalRootURLs: additionalRoots)
                let workspaceRoot = runtime.workspaceRoot
                let projectID = project.id
                let cached = await Task.detached(priority: .utility) {
                    ProjectFileIndexStore(workspaceRoot: workspaceRoot).load(projectId: projectID, rootPath: rootPath)
                }.value
                if let cached {
                    applyProjectFileIndex(cached)
                    scheduleProjectFileReindex(afterNanoseconds: 5_000_000_000)
                    return
                }

                rebuildProjectFileIndex(rootURL: rootURL, reason: .initialBuild)
            } catch {
                projectFileRootURL = nil
                applyProjectFileIndex(nil)
            }
        }
    }

    func scheduleProjectFileReindex(afterNanoseconds delay: UInt64 = 1_200_000_000) {
        guard let rootURL = projectFileRootURL else {
            loadProjectFileIndex()
            return
        }

        projectFileReindexTask?.cancel()
        projectFileReindexTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            self?.rebuildProjectFileIndex(rootURL: rootURL, reason: .scheduledRebuild)
        }
    }

    func rebuildProjectFileIndex(
        rootURL: URL,
        reason: SloppyTUIProjectFileIndexStatusPolicy.RebuildReason
    ) {
        projectFileReindexTask?.cancel()
        projectFileIndexLoading = true
        let showsIndexingStatus = SloppyTUIProjectFileIndexStatusPolicy.shouldShowIndexingStatus(
            hasCachedIndex: projectFileIndex != nil,
            reason: reason
        )
        if showsIndexingStatus {
            beginOperationStatus(.indexing, label: "Indexing search", detail: project.name)
        }
        requestRender()
        let projectID = project.id
        let workspaceRoot = runtime.workspaceRoot
        let additionalRoots = indexedAdditionalDirectoryURLs(projectRootURL: rootURL)
        let rootPath = projectFileIndexRootPath(rootURL: rootURL, additionalRootURLs: additionalRoots)
        projectFileReindexTask = Task { [weak self] in
            let buildTask = Task.detached(priority: .utility) {
                var index = ProjectFileIndex.build(
                    projectId: projectID,
                    rootURL: rootURL,
                    additionalRootURLs: additionalRoots
                )
                index.rootPath = rootPath
                guard !Task.isCancelled else {
                    return nil as ProjectFileIndex?
                }
                ProjectFileIndexStore(workspaceRoot: workspaceRoot).save(index)
                return index as ProjectFileIndex?
            }
            let index = await withTaskCancellationHandler {
                await buildTask.value
            } onCancel: {
                buildTask.cancel()
            }

            guard !Task.isCancelled, let index else { return }
            self?.applyProjectFileIndex(index)
        }
    }

    func applyProjectFileIndex(_ index: ProjectFileIndex?) {
        projectFileIndex = index
        projectFileIndexLookup = index?.makeLookup()
        projectFileIndexLoading = false
        projectFileIndexGeneration += 1
        projectFileSearchCache = nil
        endOperationStatus(.indexing)
        requestRender()
    }

    func reloadSkillSlashCommands() async {
        do {
            let response = try await service.buildAgentChatSlashCommands(agentID: agent.id)
            let skills = response.commands
                .filter { $0.source == "skill" }
                .compactMap { item -> SloppyTUISlashCommand? in
                    let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else { return nil }
                    return SloppyTUISlashCommand(
                        name,
                        item.description,
                        argument: item.argument ?? "message",
                        invocationPrefix: "@",
                        skillId: item.skillId
                    )
                }
            skillSlashCommands = skills
            skillSlashCommandNames = Set(skills.map { $0.name.lowercased() })
            requestRender()
        } catch {
            skillSlashCommands = []
            skillSlashCommandNames = []
        }
    }

    func reloadSession() async {
        sessionReloadGeneration += 1
        let reloadGeneration = sessionReloadGeneration
        let reloadAgentID = agent.id
        let reloadSessionID = session.id
        guard hasPersistedSession else {
            sessionCards = []
            subSessionCards = []
            pendingToolApproval = nil
            invalidateSessionTimelineCache()
            lastRenderedSessionEventIDs = []
            renderTimeline()
            refreshStaticChrome()
            return
        }
        let detail = try? await service.getAgentSession(agentID: reloadAgentID, sessionID: reloadSessionID)
        guard reloadGeneration == sessionReloadGeneration,
              hasPersistedSession,
              agent.id == reloadAgentID,
              session.id == reloadSessionID else {
            return
        }
        var blocks: [SloppyTUITimelineBlock] = []
        var children: [SloppyTUISubSessionCard] = []
        let events = detail?.events ?? []
        let childStatuses = await subSessionStatuses(for: childSessionIDs(in: events))
        let answeredInputRequestIDs = Set(events.compactMap { event -> String? in
            event.type == .inputResponse ? event.inputResponse?.requestId : nil
        })
        let pendingInputRequest = SloppyTUIPlanInputState.latestUnansweredRequest(in: events)
        let latestBuildProgressID = events.reversed().first { event in
            event.type == .buildProgress && event.buildProgress != nil
        }?.id
        lastRenderedSessionEventIDs = Set(events.map(\.id))
        for event in events {
            if let message = event.message {
                let body = message.segments
                    .filter { $0.kind == .text }
                    .compactMap(\.text)
                    .joined(separator: "\n")
                let thinking = message.segments
                    .filter { $0.kind == .thinking }
                    .compactMap(\.text)
                    .joined(separator: "\n")
                let attachments = message.segments
                    .filter { $0.kind == .attachment }
                    .compactMap(\.attachment)
                if !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let displayBody = SloppyTUITimelineDisplay.messageText(role: message.role, text: body)
                    if message.role == .assistant, SloppyTUITheme.isModelProviderError(body) {
                        blocks.append(.error(body))
                    } else {
                        blocks.append(.message(role: message.role, text: displayBody))
                    }
                }
                if !thinking.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    blocks.append(.thinking(thinking))
                }
                for attachment in attachments {
                    blocks.append(.attachment(name: attachment.name, mimeType: attachment.mimeType, sizeBytes: attachment.sizeBytes))
                }
            } else if let subSession = event.subSession {
                let card = SloppyTUISubSessionCard(
                    childSessionId: subSession.childSessionId,
                    title: subSession.title,
                    status: childStatuses[subSession.childSessionId] ?? .starting
                )
                children.append(card)
                blocks.append(.subSession(childSessionId: card.childSessionId, title: card.title, status: card.status))
            } else if event.type == .memoryCheckpoint, let checkpoint = event.memoryCheckpoint {
                blocks.append(.memoryCheckpoint(checkpoint))
            } else if let toolCall = event.toolCall {
                let display = SloppyTUITimelineDisplay.toolCallDisplay(tool: toolCall.tool, arguments: toolCall.arguments)
                blocks.append(.toolCall(
                    tool: toolCall.tool,
                    reason: toolCall.reason,
                    summary: display.summary,
                    details: display.details
                ))
            } else if let toolResult = event.toolResult {
                blocks.append(.toolResult(
                    tool: SloppyTUITimelineDisplay.toolResultTitle(toolResult),
                    rawTool: toolResult.tool,
                    ok: toolResult.ok,
                    error: toolResult.error?.message,
                    durationMs: toolResult.durationMs,
                    details: toolResultDisplay(toolResult)
                ))
            } else if event.type == .inputRequest, let inputRequest = event.inputRequest {
                if !answeredInputRequestIDs.contains(inputRequest.id) {
                    blocks.append(.inputRequest(inputRequest))
                }
            } else if event.id == latestBuildProgressID, let progress = event.buildProgress {
                blocks.append(.buildProgress(progress))
            } else if event.type == .planArtifact, let artifact = event.planArtifact?.artifact {
                blocks.append(.planArtifact(artifact))
            }
        }
        sessionCards = blocks
        subSessionCards = children
        invalidateSessionTimelineCache()
        updatePendingPlanInputRequest(pendingInputRequest)
        await refreshPendingToolApproval()
        await refreshTokenUsage(includeCost: false)
        if sessionListMode != .hidden {
            refreshSessionList()
        }
        renderTimeline()
    }

    func prepareCurrentSessionContext() async {
        guard hasPersistedSession else {
            return
        }
        let prepareAgentID = agent.id
        let prepareSessionID = session.id
        do {
            _ = try await service.prepareAgentSessionContext(agentID: prepareAgentID, sessionID: prepareSessionID)
        } catch {
            guard hasPersistedSession,
                  agent.id == prepareAgentID,
                  session.id == prepareSessionID else {
                return
            }
            appendLocalCard("Session context restore failed: \(String(describing: error))", autoDismissAfter: 8)
        }
    }

    func childSessionIDs(in events: [AgentSessionEvent]) -> [String] {
        var seen: Set<String> = []
        var ids: [String] = []
        for event in events {
            guard let childSessionID = event.subSession?.childSessionId,
                  seen.insert(childSessionID).inserted else {
                continue
            }
            ids.append(childSessionID)
        }
        return ids
    }

    func subSessionStatuses(for childSessionIDs: [String]) async -> [String: SloppyTUISubSessionStatus] {
        var statuses: [String: SloppyTUISubSessionStatus] = [:]
        for childSessionID in childSessionIDs {
            guard let detail = try? await service.getAgentSession(agentID: agent.id, sessionID: childSessionID) else {
                statuses[childSessionID] = .starting
                continue
            }
            statuses[childSessionID] = subSessionStatus(from: detail.events)
        }
        return statuses
    }

    func subSessionStatus(from events: [AgentSessionEvent]) -> SloppyTUISubSessionStatus {
        guard !events.isEmpty else {
            return .starting
        }

        let answeredInputRequestIDs = Set(events.compactMap { event -> String? in
            event.type == .inputResponse ? event.inputResponse?.requestId : nil
        })
        if let inputRequest = events.compactMap({ event -> PlanInputRequest? in
            event.type == .inputRequest ? event.inputRequest : nil
        }).last(where: { request in
            !answeredInputRequestIDs.contains(request.id)
        }) {
            return .waiting(planInputStatusLabel(inputRequest))
        }

        if let status = events.reversed().compactMap(\.runStatus).first {
            let label = status.label.trimmingCharacters(in: .whitespacesAndNewlines)
            let detail = label.isEmpty ? status.details?.trimmingCharacters(in: .whitespacesAndNewlines) : label
            switch status.stage {
            case .thinking, .searching, .responding:
                return .running(detail)
            case .paused:
                return .waiting(detail)
            case .done:
                return .done
            case .interrupted:
                return .interrupted(detail)
            }
        }

        let hasAssistantText = events.contains { event in
            guard event.type == .message,
                  let message = event.message,
                  message.role == .assistant else {
                return false
            }
            return message.segments.contains { segment in
                segment.kind == .text && segment.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            }
        }
        return hasAssistantText ? .done : .starting
    }

    func planInputStatusLabel(_ request: PlanInputRequest) -> String {
        if let title = request.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return title
        }
        if let header = request.questions.first?.header?.trimmingCharacters(in: .whitespacesAndNewlines), !header.isEmpty {
            return header
        }
        return "input needed"
    }

    func refreshTokenUsage(includeCost: Bool) async {
        let usage = await service.listTokenUsage(channelId: currentSessionChannelID())
        if includeCost {
            if let agentUsage = try? await service.getAgentTokenUsage(agentID: agent.id) {
                tokenUsageCostUSD = agentUsage.totalCostUSD
            }
        }
        tokenUsageSummary = SloppyTUITokenUsageSummary(
            promptTokens: usage.totalPromptTokens,
            completionTokens: usage.totalCompletionTokens,
            totalTokens: usage.totalTokens,
            cachedInputTokens: usage.totalCachedInputTokens,
            cacheCreationInputTokens: usage.totalCacheCreationInputTokens,
            reasoningTokens: usage.totalReasoningTokens,
            contextWindowTokens: selectedModelContextWindowTokens,
            costUSD: tokenUsageCostUSD
        )
        refreshStaticChrome()
    }

    func currentSessionChannelID() -> String {
        "agent:\(agent.id):session:\(session.id)"
    }

    func contextWindowTokens(for modelID: String, in models: [ProviderModelOption]) -> Int {
        let trimmed = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        let option = models.first { $0.id == trimmed } ?? models.first
        guard let value = option?.contextWindow else {
            return 0
        }
        return CoreService.parseContextWindowString(value)
    }

    func isFinalAssistantMessage(_ event: AgentSessionEvent) -> Bool {
        guard event.type == .message,
              let message = event.message,
              message.role == .assistant else {
            return false
        }
        return message.segments.contains { segment in
            segment.kind == .text && segment.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }
    }

    func toolResultDisplay(_ result: AgentToolResultEvent) -> String? {
        var parts: [String] = []

        if let error = result.error {
            parts.append("error code: `\(error.code)`")
            if let hint = error.hint?.trimmingCharacters(in: .whitespacesAndNewlines), !hint.isEmpty {
                parts.append("hint: \(hint)")
            }
        }

        if result.tool == "runtime.exec",
           let data = result.data?.asObject {
            if let exitCode = data["exitCode"]?.asInt {
                parts.append("exit code: `\(exitCode)`")
            }
            if data["timedOut"]?.asBool == true {
                parts.append("timed out")
            }
            if let stdout = data["stdout"]?.asString, !stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                parts.append("stdout:\n" + fencedBlock("text", stdout, maxCharacters: 6_000))
            }
            if let stderr = data["stderr"]?.asString, !stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                parts.append("stderr:\n" + fencedBlock("text", stderr, maxCharacters: 6_000))
            }
        } else if let data = result.data {
            parts.append(fencedBlock("json", prettyJSON(data), maxCharacters: 4_000))
        }

        return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
    }

    func fencedBlock(_ language: String, _ text: String, maxCharacters: Int) -> String {
        let safeText = clip(text.replacingOccurrences(of: "```", with: "` ` `"), maxCharacters: maxCharacters)
        return "```\(language)\n\(safeText)\n```"
    }

    func prettyJSON(_ value: JSONValue) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(value),
              let string = String(data: data, encoding: .utf8) else {
            return String(describing: value)
        }
        return string
    }

    func clip(_ text: String, maxCharacters: Int) -> String {
        guard text.count > maxCharacters else {
            return text
        }
        return String(text.prefix(max(0, maxCharacters - 14))) + "\n... truncated"
    }

    func shellQuote(_ value: String) -> String {
        guard !value.isEmpty else {
            return "''"
        }
        let safeCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_@%+=:,./-")
        if value.unicodeScalars.allSatisfy({ safeCharacters.contains($0) }) {
            return value
        }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

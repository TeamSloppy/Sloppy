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
    func sessionListDetail(for detail: AgentSessionDetail, tracked: SloppyTUIState.TrackedSession) -> String {
        if let request = latestUnansweredInputRequest(in: detail.events) {
            let title = request.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !title.isEmpty {
                return title
            }
            return request.questions.first?.question ?? "Waiting for input"
        }
        if postingSessionIDs.contains(tracked.sessionId) {
            return "Running"
        }
        if let status = latestRunStatus(in: detail.events),
           status.stage == .thinking || status.stage == .searching || status.stage == .responding {
            return status.details?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? status.details!
                : status.label
        }
        if let worktreePath = tracked.worktreePath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !worktreePath.isEmpty {
            return worktreePath
        }
        return detail.summary.lastMessagePreview ?? "\(detail.summary.messageCount) messages"
    }

    func latestUnansweredInputRequest(in events: [AgentSessionEvent]) -> PlanInputRequest? {
        SloppyTUIPlanInputState.latestUnansweredRequest(in: events)
    }

    func latestRunStatus(in events: [AgentSessionEvent]) -> AgentRunStatusEvent? {
        events.reversed().first { $0.type == .runStatus && $0.runStatus != nil }?.runStatus
    }

    func createSessionFromListInput() {
        let value = editor.getText().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        sessionListMode = .hidden
        editor.setText("")
        persistDraft("")
        resetToDraftSession()
        welcomeDismissed = true
        Task { @MainActor in
            await self.sendMessage(value)
        }
    }

    func openSelectedSessionFromList(reply: Bool) {
        guard sessionListEntries.indices.contains(sessionListSelectedIndex) else {
            sessionListSelectedIndex = SloppyTUISessionList.clampedSelection(
                sessionListSelectedIndex,
                entryCount: sessionListEntries.count
            )
            requestRender()
            return
        }
        let entry = sessionListEntries[sessionListSelectedIndex]
        sessionListMode = .hidden
        Task { @MainActor in
            await self.switchToTrackedSession(entry)
            if reply {
                self.editor.setText("")
                self.persistDraft("")
            }
        }
    }

    func switchToTrackedSession(_ entry: SloppyTUISessionListEntry) async {
        if entry.agentId != agent.id {
            let agents = (try? await service.listAgents(includeSystem: false)) ?? []
            if let nextAgent = agents.first(where: { $0.id == entry.agentId }) {
                agent = nextAgent
                await reloadSkillSlashCommands()
                await refreshSelectedModel()
            }
        }
        await switchSession(entry.sessionId)
    }

    func hideSelectedSessionFromList() {
        guard sessionListEntries.indices.contains(sessionListSelectedIndex) else {
            return
        }
        removeTrackedSession(sessionListEntries[sessionListSelectedIndex].sessionId)
        sessionListEntries.remove(at: sessionListSelectedIndex)
        sessionListSelectedIndex = SloppyTUISessionList.clampedSelection(
            sessionListSelectedIndex,
            entryCount: sessionListEntries.count
        )
        requestRender()
    }

    func resetToDraftSession() {
        if let checkpointSessionID = SloppyTUIDraftSessionReset.pendingCheckpointSessionID(
            currentSessionID: session.id,
            hasPersistedSession: hasPersistedSession
        ) {
            pendingDraftCheckpointSessionID = checkpointSessionID
        }

        welcomeDismissed = false
        session = SloppyTUIApp.makeDraftSession(agent: agent, projectID: project.id)
        hasPersistedSession = false
        sessionCards = []
        subSessionCards = []
        lastRenderedSessionEventIDs = []
        pendingContext = nil
        pendingUploads.removeAll()
        pendingPlanInputRequest = nil
        tokenUsageSummary = nil
        tokenUsageCostUSD = nil
        lastTurnTokenUsage = nil
        taskStartedAt = nil
        lastTaskElapsed = nil
        liveRunStage = nil
        liveRunStatusLine = nil
        activePicker = nil
        addDirectoryInput = nil
        pendingWorkspaceAccessRequest = nil
        deniedWorkspaceAccessDirectories.removeAll()
        scrollbackModeSelectionIndex = nil
        queuedMessages = SloppyTUIMessageQueue()
        isDrainingQueuedMessages = false
        sessionUndoManagers = SloppyTUISessionUndoManagers()
        clearLocalCards()
        autoDiffTask?.cancel()
        autoDiffTask = nil
        transientNoticeTask?.cancel()
        transientNoticeTask = nil
        transientNoticeLine = nil
        streamTask?.cancel()
        streamTask = nil
        clearLiveAssistantDraft()
        invalidateSessionTimelineCache()
        persistSelection()
        renderTimeline()
    }

    func stopCurrentRun() async {
        await interruptCurrentRun(
            reason: "TUI /stop",
            successMessage: "Stop requested.",
            failurePrefix: "Stop failed",
            useNotice: false
        )
    }

    func restoreCurrentSession(extraInstruction: String) async {
        guard !isPosting else {
            appendLocalCard("A message is already in flight. Use `/stop` if you need to interrupt it before restoring.")
            return
        }
        if let request = pendingPlanInputRequest {
            updatePendingPlanInputRequest(request)
            appendLocalCard("This session is waiting for input. Answer the pending question before restoring the run.", autoDismissAfter: 8)
            return
        }
        if hasPersistedSession,
           let detail = try? await service.getAgentSession(agentID: agent.id, sessionID: session.id),
           let request = SloppyTUIPlanInputState.latestUnansweredRequest(in: detail.events) {
            updatePendingPlanInputRequest(request)
            appendLocalCard("This session is waiting for input. Answer the pending question before restoring the run.", autoDismissAfter: 8)
            return
        }

        let trimmedExtra = extraInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasLiveRuntimeSession = await service.hasLiveAgentRuntimeSession(
            agentID: agent.id,
            sessionID: session.id
        )
        await sendMessage(Self.restorePrompt(
            hasLiveRuntimeSession: hasLiveRuntimeSession,
            extraInstruction: trimmedExtra
        ))
    }

    static func restorePrompt(hasLiveRuntimeSession: Bool, extraInstruction: String) -> String {
        let extra = extraInstruction.isEmpty ? "" : "\n\nAdditional recovery instruction:\n\(extraInstruction)"
        if hasLiveRuntimeSession {
            return """
            Continue executing the current task from the live session state.

            Do not start a new task and do not repeat completed work. Continue from the last reliable point, using the latest live context and tool results. If the task is already complete, report the final status clearly.\(extra)
            """
        }

        return """
        Restore this session after the previous run failed, lost network access, or was interrupted. Continue the last unfinished user task from the current session transcript.

        Do not start a new task and do not repeat completed work. Inspect the latest session context and tool results if needed, then continue from the last reliable point. If the failure was transient, retry the failed operation and proceed normally.\(extra)
        """
    }

    func makeUndoBaseline() async -> SloppyTUISessionUndoManagers.Baseline? {
        guard !service.isRemote else {
            return nil
        }
        do {
            let rootURL = try await service.resolveProjectWorkspaceRoot(projectID: project.id)
            return sessionUndoManagers.makeBaseline(sessionID: session.id, rootURL: rootURL)
        } catch {
            return nil
        }
    }

    func recordUndoPointIfNeeded(_ baseline: SloppyTUISessionUndoManagers.Baseline?) {
        guard let baseline else {
            return
        }

        switch sessionUndoManagers.recordChanges(baseline) {
        case .recorded:
            updateSessionDiffPreview(rootURL: baseline.baseline.rootURL)
        case .noChanges:
            break
        case .skipped(let reason):
            appendLocalCard(reason, autoDismissAfter: 10)
        }
    }

    func undoLastTurn() async {
        await applyUndoRedo(direction: .undo)
    }

    func redoLastTurn() async {
        await applyUndoRedo(direction: .redo)
    }

    func applyUndoRedo(direction: SloppyTUIUndoManager.ApplyDirection) async {
        guard !service.isRemote else {
            appendLocalCard("`/undo` and `/redo` are local filesystem actions and are disabled for remote Sloppy instances.", autoDismissAfter: 10)
            return
        }
        guard !isPosting else {
            appendLocalCard("A message is in flight. Use `/stop` before changing files with `/undo` or `/redo`.")
            return
        }
        guard hasPersistedSession else {
            appendLocalCard("No session yet. Send a message first or open an existing session with `/sessions`.")
            return
        }

        do {
            let rootURL = try await service.resolveProjectWorkspaceRoot(projectID: project.id)
            let result: SloppyTUIUndoManager.ApplyResult
            switch direction {
            case .undo:
                result = try sessionUndoManagers.undo(sessionID: session.id, rootURL: rootURL)
            case .redo:
                result = try sessionUndoManagers.redo(sessionID: session.id, rootURL: rootURL)
            }
            appendLocalCard(undoRedoSummary(result), autoDismissAfter: 10)
            scheduleProjectFileReindex()
        } catch let error as SloppyTUIUndoManager.Error {
            appendLocalCard(error.localizedDescription, autoDismissAfter: 8)
        } catch {
            appendLocalCard("Could not update files: \(String(describing: error))")
        }
    }

    func undoRedoSummary(_ result: SloppyTUIUndoManager.ApplyResult) -> String {
        let title: String
        switch result.direction {
        case .undo:
            title = "Undid file changes from the last turn."
        case .redo:
            title = "Redid file changes from the last undone turn."
        }

        let paths = result.paths.prefix(12).map { "- `\($0)`" }.joined(separator: "\n")
        let remaining = result.paths.count > 12 ? "\n- ...and \(result.paths.count - 12) more" : ""
        return """
        \(title)

        \(paths)\(remaining)
        """
    }

    func interruptCurrentRun(
        reason: String,
        successMessage: String,
        failurePrefix: String,
        useNotice: Bool
    ) async {
        guard hasPersistedSession else {
            if useNotice {
                showSystemNotice("No active session to interrupt.")
            } else {
                appendLocalCard("No active session to interrupt.")
            }
            return
        }
        if pendingPlanInputRequest != nil {
            let message = "This session is waiting for input. Answer or cancel the pending question instead of interrupting it."
            if useNotice {
                showSystemNotice(message)
            } else {
                appendLocalCard(message, autoDismissAfter: 8)
            }
            return
        }
        guard !isInterruptingRun else {
            return
        }
        isInterruptingRun = true
        requestRender()
        defer {
            isInterruptingRun = false
            requestRender()
        }
        do {
            _ = try await service.controlAgentSession(
                agentID: agent.id,
                sessionID: session.id,
                request: AgentSessionControlRequest(action: .interruptTree, requestedBy: "tui", reason: reason)
            )
            if useNotice {
                showSystemNotice(successMessage)
            } else {
                appendLocalCard(successMessage)
            }
        } catch {
            let message = "\(failurePrefix): \(String(describing: error))"
            if useNotice {
                showSystemNotice(message)
            } else {
                appendLocalCard(message)
            }
        }
    }

    func compactCurrentSession() async {
        guard hasPersistedSession else {
            appendLocalCard("No session yet. Send a message first or open an existing session with `/sessions`.")
            return
        }
        beginOperationStatus(.compacting, label: "Compacting context", detail: "current session")
        defer { endOperationStatus(.compacting) }
        refreshStaticChrome(statusLine: "compacting context...")
        do {
            _ = try await service.requestAgentMemoryCheckpoint(
                agentID: agent.id,
                sessionID: session.id,
                reason: "tui_compact_command"
            )
            refreshStaticChrome()
        } catch {
            appendLocalCard("Compact failed: \(String(describing: error))")
        }
    }

    func addDirectoryToCurrentSession(_ raw: String) async {
        guard let path = ChannelAddDirCommandParsing.pathTailIfCommand(raw),
              !path.isEmpty
        else {
            showAddDirectoryInput()
            return
        }

        await addDirectoryPath(path)
    }

    @discardableResult
    func addDirectoryPath(_ path: String) async -> Bool {
        guard hasPersistedSession else {
            do {
                let resolvedPath = try await resolveDraftSessionDirectoryPath(path)
                let directories = appendingUniqueDirectory(resolvedPath, to: persistedDirectoriesForCurrentSession())
                persistSessionDirectories(directories)
                loadProjectFileIndex()
                appendLocalCard("Added working directory for the next session:\n`\(resolvedPath)`", autoDismissAfter: 8)
                return true
            } catch {
                appendLocalCard("Directory not found: `\(path)`")
                return false
            }
        }

        do {
            let response = try await service.addAgentSessionDirectory(
                agentID: agent.id,
                sessionID: session.id,
                request: AgentSessionDirectoryRequest(path: path)
            )
            persistSessionDirectories(response.directories)
            loadProjectFileIndex()
            appendLocalCard("Added working directory:\n`\(response.path)`", autoDismissAfter: 8)
            return true
        } catch {
            appendLocalCard("Add directory failed: \(String(describing: error))")
            return false
        }
    }

    func completeAddDirectoryInput() {
        let candidates = addDirectoryCompletionCandidates(for: addDirectoryInput ?? "")
        guard !candidates.isEmpty else {
            requestRender()
            return
        }
        if candidates.count == 1 {
            addDirectoryInput = candidates[0]
        } else if let prefix = commonPathCompletionPrefix(candidates),
                  prefix.count > (addDirectoryInput ?? "").count {
            addDirectoryInput = prefix
        }
        requestRender()
    }

    func addDirectoryCompletionCandidates(for rawValue: String) -> [String] {
        let raw = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasSlash = raw.contains("/")
        let basePath: String
        let partial: String
        let outputPrefix: String

        if raw.isEmpty {
            basePath = runtime.cwd
            partial = ""
            outputPrefix = ""
        } else if raw.hasSuffix("/") {
            basePath = (raw as NSString).expandingTildeInPath
            partial = ""
            outputPrefix = raw
        } else if hasSlash {
            let nsRaw = raw as NSString
            basePath = (nsRaw.deletingLastPathComponent as NSString).expandingTildeInPath
            partial = nsRaw.lastPathComponent
            if let slash = raw.lastIndex(of: "/") {
                outputPrefix = String(raw[...slash])
            } else {
                outputPrefix = ""
            }
        } else {
            basePath = runtime.cwd
            partial = raw
            outputPrefix = ""
        }

        let entries = (try? FileManager.default.contentsOfDirectory(
            atPath: basePath.isEmpty ? "/" : basePath
        )) ?? []
        return entries
            .filter { entry in
                entry.hasPrefix(partial) && (!entry.hasPrefix(".") || partial.hasPrefix("."))
            }
            .compactMap { entry -> String? in
                let absolute = ((basePath.isEmpty ? "/" : basePath) as NSString).appendingPathComponent(entry)
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: absolute, isDirectory: &isDirectory),
                      isDirectory.boolValue
                else {
                    return nil
                }
                return outputPrefix + entry + "/"
            }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    func commonPathCompletionPrefix(_ candidates: [String]) -> String? {
        guard var prefix = candidates.first else { return nil }
        for candidate in candidates.dropFirst() {
            while !candidate.hasPrefix(prefix), !prefix.isEmpty {
                prefix.removeLast()
            }
        }
        return prefix
    }
}

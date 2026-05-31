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
    func submit(_ raw: String) async {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if shellModeEnabled {
            await submitShellCommand(raw: raw, value: value)
            return
        }
        guard !value.isEmpty || !pendingUploads.isEmpty else {
            return
        }
        if !value.isEmpty {
            editor.addToHistory(value)
        }
        editor.setText("")
        persistDraft("")

        if let skillInvocation = SloppyTUISkillInvocationRouter.invocationMessage(raw: value, skillCommands: skillSlashCommands) {
            welcomeDismissed = true
            dismissFirstStartBootstrapCard()
            if isPosting {
                await queueMessage(
                    skillInvocation,
                    context: pendingContext,
                    uploads: pendingUploads,
                    clearsPendingInputs: true,
                    interruptActiveRun: true
                )
                return
            }
            await sendMessage(skillInvocation)
            return
        }

        if shouldHandleSlashCommand(value) {
            await handleCommand(value)
            return
        }

        welcomeDismissed = true
        dismissFirstStartBootstrapCard()
        if isPosting {
            await queueMessage(
                value,
                context: pendingContext,
                uploads: pendingUploads,
                clearsPendingInputs: true,
                interruptActiveRun: true
            )
            return
        }
        await sendMessage(value)
    }

    func submitShellCommand(raw: String, value: String) async {
        guard !value.isEmpty else {
            return
        }
        if isRunningShellCommand {
            editor.setText(raw)
            persistDraft(raw)
            showSystemNotice("A shell command is already running.")
            return
        }
        editor.addToHistory(value)
        editor.setText("")
        persistDraft("")
        welcomeDismissed = true
        dismissFirstStartBootstrapCard()
        await executeShellCommand(value)
    }

    func executeShellCommand(_ command: String) async {
        guard !isRunningShellCommand else { return }
        isRunningShellCommand = true
        shellRunStatusLine = "Running shell command..."
        refreshStaticChrome()
        defer {
            isRunningShellCommand = false
            shellRunStatusLine = nil
            refreshStaticChrome()
        }

        let guardrails = AgentToolsGuardrails()
        do {
            let result = try await runForegroundProcess(
                command: shellExecutablePath(),
                arguments: ["-lc", command],
                cwd: URL(fileURLWithPath: runtime.cwd, isDirectory: true),
                timeoutMs: guardrails.execTimeoutMs,
                maxOutputBytes: guardrails.maxExecOutputBytes
            )
            appendLocalCard(SloppyTUIShellCommandResultFormatter.markdown(
                command: command,
                cwd: runtime.cwd,
                result: result
            ))
        } catch {
            appendLocalCard("""
            ## Shell
            ```shell
            \(command.replacingOccurrences(of: "```", with: "` ` `"))
            ```

            failed: \(String(describing: error))
            """)
        }
    }

    func shellExecutablePath() -> String {
        let environmentShell = ProcessInfo.processInfo.environment["SHELL"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let environmentShell,
           !environmentShell.isEmpty,
           FileManager.default.isExecutableFile(atPath: environmentShell) {
            return environmentShell
        }
        if FileManager.default.isExecutableFile(atPath: "/bin/bash") {
            return "/bin/bash"
        }
        return "/bin/sh"
    }

    func sendMessage(
        _ value: String,
        spawnSubSession: Bool = false,
        interruptActiveRunOnQueue: Bool = true
    ) async {
        await sendMessage(
            value,
            context: pendingContext,
            uploads: pendingUploads,
            spawnSubSession: spawnSubSession,
            clearsPendingInputsOnSuccess: true,
            interruptActiveRunOnQueue: interruptActiveRunOnQueue
        )
    }

    func sendMessage(
        _ value: String,
        context: String?,
        uploads: [AgentAttachmentUpload],
        spawnSubSession: Bool = false,
        clearsPendingInputsOnSuccess: Bool,
        interruptActiveRunOnQueue: Bool = true
    ) async {
        guard !isPosting else {
            await queueMessage(
                value,
                context: context,
                uploads: uploads,
                spawnSubSession: spawnSubSession,
                interruptActiveRun: interruptActiveRunOnQueue
            )
            return
        }

        if let accessRequest = await workspaceAccessRequest(
            value: value,
            context: context,
            uploads: uploads,
            spawnSubSession: spawnSubSession,
            clearsPendingInputsOnSuccess: clearsPendingInputsOnSuccess
        ) {
            showWorkspaceAccessPrompt(accessRequest)
            return
        }

        dismissLocalCardsForUserMessage()
        isPosting = true
        queuedMessageInterruptRequested = false
        taskStartedAt = Date()
        resetSendTiming()
        lastTaskElapsed = nil
        setLiveAssistantDraftImmediately("")
        let inlineReferenceCount = min(SloppyTUIProjectPathTokens.attachmentPaths(in: value).count, 8)
        updateSendProgress(.init(
            stage: .preparing,
            attachmentCount: uploads.count,
            inlineReferenceCount: inlineReferenceCount
        ))
        startThinkingAnimation()
        renderTimeline()
        await Task.yield()
        let content = await messageContentWithInlineAttachments(value, context: context, uploads: uploads)
        var createdSessionForThisMessage = false
        var postingSessionID: String?
        do {
            updateSendProgress(.init(
                stage: hasPersistedSession ? .snapshottingUndo : .creatingSession,
                attachmentCount: uploads.count,
                inlineReferenceCount: inlineReferenceCount,
                contentCharacters: content.count
            ))
            await Task.yield()
            createdSessionForThisMessage = try await ensurePersistedSessionForMessage()
            postingSessionID = session.id
            postingSessionIDs.insert(session.id)
            refreshSessionList()
            updateSendProgress(.init(
                stage: .snapshottingUndo,
                attachmentCount: uploads.count,
                inlineReferenceCount: inlineReferenceCount,
                contentCharacters: content.count
            ))
            await Task.yield()
            let undoBaseline = await makeUndoBaseline()
            if !runtime.config.onboarding.completed {
                updateSendProgress(.init(
                    stage: .updatingOnboarding,
                    attachmentCount: uploads.count,
                    inlineReferenceCount: inlineReferenceCount,
                    contentCharacters: content.count
                ))
                await Task.yield()
                var config = await service.getConfig()
                config.onboarding.completed = true
                _ = try await service.updateConfig(config)
            }
            let config = await service.getConfig()
            updateSendProgress(.init(
                stage: .sending,
                attachmentCount: uploads.count,
                inlineReferenceCount: inlineReferenceCount,
                contentCharacters: content.count
            ))
            await Task.yield()
            await waitForCurrentSessionStreamReady()
            markSendTiming("stream_ready")
            _ = try await service.postAgentSessionMessage(
                agentID: agent.id,
                sessionID: session.id,
                request: AgentSessionPostMessageRequest(
                    userId: config.onboarding.completed ? "tui" : "onboarding",
                    content: content,
                    attachments: uploads,
                    spawnSubSession: spawnSubSession,
                    reasoningEffort: reasoningEffort,
                    mode: chatMode
                )
            )
            if clearsPendingInputsOnSuccess {
                pendingContext = nil
                pendingUploads.removeAll()
            }
            recordUndoPointIfNeeded(undoBaseline)
            liveRunStatusLine = "Refreshing session..."
            markSendTiming("post_message_returned")
            refreshStaticChrome()
            await Task.yield()
            await reloadSession()
            await refreshTokenUsage(includeCost: true)
            petMood = .happy
        } catch {
            await deleteSessionIfStillEmptyAfterFailedFirstMessage(createdSessionForThisMessage)
            clearLiveAssistantDraft()
            petMood = .sad
            markSendTiming("failed")
            appendLocalCard("Message failed: \(String(describing: error))")
        }
        if let postingSessionID {
            postingSessionIDs.remove(postingSessionID)
            refreshSessionList()
        }
        if let taskStartedAt {
            let elapsed = Date().timeIntervalSince(taskStartedAt)
            lastTaskElapsed = elapsed
            cumulativeAgentActiveTime += elapsed
        }
        taskStartedAt = nil
        isPosting = false
        queuedMessageInterruptRequested = false
        stopThinkingAnimation()
        clearLiveAssistantDraft()
        liveRunStatusLine = nil
        markSendTiming("finished")
        refreshStaticChrome()
        renderTimeline()
        await sendNextQueuedMessageIfIdle()
    }

    func workspaceAccessRequest(
        value: String,
        context: String?,
        uploads: [AgentAttachmentUpload],
        spawnSubSession: Bool,
        clearsPendingInputsOnSuccess: Bool
    ) async -> SloppyTUIWorkspaceAccessRequest? {
        let absolutePaths = SloppyTUIProjectPathTokens.attachmentPaths(in: value)
            .filter { $0.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("/") }
        guard !absolutePaths.isEmpty else {
            return nil
        }

        let projectRootPath = ((try? await service.resolveProjectWorkspaceRoot(projectID: project.id))
            ?? URL(fileURLWithPath: runtime.cwd, isDirectory: true))
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path
        for rawPath in absolutePaths {
            guard let directory = SloppyTUIWorkspaceAccess.requiredDirectoryForAbsolutePath(
                rawPath,
                projectRootPath: projectRootPath,
                sessionDirectories: persistedDirectoriesForCurrentSession()
            ) else {
                continue
            }
            if isWorkspaceAccessDenied(directory) {
                appendLocalCard("""
                Workspace access was denied for:
                `\(directory)`

                The agent was not started. Run `/add_dir \(shellQuote(directory))` or retry after choosing allow.
                """, autoDismissAfter: 12)
                return SloppyTUIWorkspaceAccessRequest(
                    directoryPath: directory,
                    originalPath: rawPath,
                    value: "",
                    context: nil,
                    uploads: [],
                    spawnSubSession: false,
                    clearsPendingInputsOnSuccess: false
                )
            }
            return SloppyTUIWorkspaceAccessRequest(
                directoryPath: directory,
                originalPath: rawPath,
                value: value,
                context: context,
                uploads: uploads,
                spawnSubSession: spawnSubSession,
                clearsPendingInputsOnSuccess: clearsPendingInputsOnSuccess
            )
        }
        return nil
    }

    func showWorkspaceAccessPrompt(_ request: SloppyTUIWorkspaceAccessRequest) {
        guard !request.value.isEmpty else {
            return
        }
        pendingWorkspaceAccessRequest = request
        activePicker = SloppyTUIPicker(
            kind: .workspaceAccess,
            title: "Allow workspace directory?",
            items: [
                SloppyTUIPickerItem(
                    value: "allow",
                    label: "Allow",
                    description: request.directoryPath,
                    isCurrent: false
                ),
                SloppyTUIPickerItem(
                    value: "deny",
                    label: "Deny",
                    description: "Do not start the agent for this message",
                    isCurrent: false
                ),
            ],
            selectedIndex: 0
        )
        appendLocalCard("""
        The agent does not have access to this directory:
        `\(request.directoryPath)`

        Requested by path:
        `\(request.originalPath)`

        Allow access for this session?
        """, autoDismissAfter: 20)
        refreshStaticChrome(statusLine: "allow workspace directory with Enter, or choose deny")
        requestRender()
    }

    func applyWorkspaceAccessDecision(_ value: String) async {
        guard let request = pendingWorkspaceAccessRequest else {
            return
        }
        pendingWorkspaceAccessRequest = nil
        if value == "allow" {
            clearWorkspaceAccessDenial(request.directoryPath)
            guard await addDirectoryPath(request.directoryPath) else {
                return
            }
            await sendMessage(
                request.value,
                context: request.context,
                uploads: request.uploads,
                spawnSubSession: request.spawnSubSession,
                clearsPendingInputsOnSuccess: request.clearsPendingInputsOnSuccess
            )
        } else {
            denyWorkspaceAccess(request.directoryPath)
            appendLocalCard("""
            Workspace access denied for:
            `\(request.directoryPath)`

            The agent was not started.
            """, autoDismissAfter: 10)
        }
    }

    func denyPendingWorkspaceAccess() {
        guard let request = pendingWorkspaceAccessRequest else {
            return
        }
        pendingWorkspaceAccessRequest = nil
        denyWorkspaceAccess(request.directoryPath)
        appendLocalCard("""
        Workspace access denied for:
        `\(request.directoryPath)`

        The agent was not started.
        """, autoDismissAfter: 10)
    }

    func workspaceAccessDenialKey(_ directoryPath: String) -> String {
        currentSessionDirectoryKey() + "\u{0}" + directoryPath
    }

    func isWorkspaceAccessDenied(_ directoryPath: String) -> Bool {
        deniedWorkspaceAccessDirectories.contains(workspaceAccessDenialKey(directoryPath))
    }

    func denyWorkspaceAccess(_ directoryPath: String) {
        deniedWorkspaceAccessDirectories.insert(workspaceAccessDenialKey(directoryPath))
    }

    func clearWorkspaceAccessDenial(_ directoryPath: String) {
        deniedWorkspaceAccessDirectories.remove(workspaceAccessDenialKey(directoryPath))
    }

    func deniedWorkspaceAccessDirectoriesForCurrentSession() -> [String] {
        let prefix = currentSessionDirectoryKey() + "\u{0}"
        return deniedWorkspaceAccessDirectories.compactMap { raw in
            guard raw.hasPrefix(prefix) else {
                return nil
            }
            return String(raw.dropFirst(prefix.count))
        }.sorted()
    }

    func ensurePersistedSessionForMessage() async throws -> Bool {
        guard !hasPersistedSession else {
            return false
        }
        let draftDirectoryKey = currentSessionDirectoryKey()
        let draftDirectories = persistedDirectoriesForCurrentSession()
        let checkpointSessionID = pendingDraftCheckpointSessionID
        session = try await service.createAgentSession(
            agentID: agent.id,
            request: AgentSessionCreateRequest(
                checkpointSessionId: checkpointSessionID,
                projectId: project.id
            )
        )
        pendingDraftCheckpointSessionID = nil
        hasPersistedSession = true
        if !draftDirectories.isEmpty {
            await applyDraftDirectories(draftDirectories, previousKey: draftDirectoryKey)
        }
        persistSelection()
        trackSession(session, opened: true)
        streamSession()
        refreshStaticChrome()
        return true
    }

    func deleteSessionIfStillEmptyAfterFailedFirstMessage(_ shouldDelete: Bool) async {
        guard shouldDelete, hasPersistedSession else {
            return
        }
        guard let detail = try? await service.getAgentSession(agentID: agent.id, sessionID: session.id),
              detail.summary.messageCount == 0 else {
            return
        }
        try? await service.deleteAgentSession(agentID: agent.id, sessionID: session.id)
        session = SloppyTUIApp.makeDraftSession(agent: agent, projectID: project.id)
        hasPersistedSession = false
        persistSelection()
        streamSession()
    }

    func queueMessage(
        _ value: String,
        context: String? = nil,
        uploads: [AgentAttachmentUpload] = [],
        spawnSubSession: Bool = false,
        clearsPendingInputs: Bool = false,
        interruptActiveRun: Bool = false
    ) async {
        _ = queuedMessages.enqueue(
            text: value,
            context: context,
            uploads: uploads,
            spawnSubSession: spawnSubSession
        )
        if clearsPendingInputs {
            pendingContext = nil
            pendingUploads.removeAll()
        }
        showSystemNotice("Queued message. Press ctrl+b to cancel next queued message.")
        renderTimeline()
        guard SloppyTUIQueuedMessageInterruptPolicy.shouldRequestInterrupt(
            interruptActiveRun: interruptActiveRun,
            isPosting: isPosting,
            isInterruptingRun: isInterruptingRun,
            hasQueuedInterruptRequest: queuedMessageInterruptRequested
        ) else {
            return
        }
        queuedMessageInterruptRequested = true
        await interruptCurrentRun(
            reason: "TUI queued user message",
            successMessage: "Interrupt requested. Queued message will send next.",
            failurePrefix: "Interrupt failed",
            useNotice: true
        )
    }

    func sendNextQueuedMessageIfIdle() async {
        guard !isPosting, !isDrainingQueuedMessages else { return }
        guard let message = queuedMessages.dequeue() else {
            renderTimeline()
            return
        }

        isDrainingQueuedMessages = true
        renderTimeline()
        await sendMessage(
            message.text,
            context: message.context,
            uploads: message.uploads,
            spawnSubSession: message.spawnSubSession,
            clearsPendingInputsOnSuccess: false
        )
        isDrainingQueuedMessages = false
        await sendNextQueuedMessageIfIdle()
    }
}

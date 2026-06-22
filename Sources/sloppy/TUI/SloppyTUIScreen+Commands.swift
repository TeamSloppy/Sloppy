import Foundation
#if canImport(AppKit)
import AppKit
#endif
import ChannelPluginSupport
import Logging
import Protocols
import SloppyNodeCore
import TauTUI

@MainActor
extension SloppyTUIScreen {
    func handleCommand(_ raw: String) async {
        let parts = raw.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        let command = parts.first.map { String($0.dropFirst()).lowercased() } ?? ""
        let args = Array(parts.dropFirst())

        switch command {
        case "help":
            showHelp()
        case "keybindings", "shortcuts":
            showQuickReference()
        case "scrollback":
            configureScrollback(args)
        case "workspace":
            await showWorkspace()
        case "projects", "project":
            await showProjectPicker()
        case "status":
            await showStatus()
        case "pet":
            showPetStatus(toggle: true)
        case "agents", "agent":
            await showAgentPicker()
        case "subagents", "children":
            showSubSessionPicker()
        case "parent", "back":
            await openParentSession()
        case "sessions", "session":
            openSessionList(mode: .side)
        case "new":
            await createNewSession()
        case "bg":
            await createBackgroundSession(task: args.joined(separator: " "))
        case "goal":
            await handleGoalCommand(args)
        case "pin":
            togglePinForCurrentSession()
        case "clear":
            clearLocalCards()
            renderTimeline()
        case "stop":
            await stopCurrentRun()
        case "restore", "up":
            await restoreCurrentSession(extraInstruction: args.joined(separator: " "))
        case "undo":
            await undoLastTurn()
        case "redo":
            await redoLastTurn()
        case "btw":
            let message = args.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !message.isEmpty else {
                appendLocalCard("Usage: `/btw <message>`")
                return
            }
            await sendMessage(raw, interruptActiveRunOnQueue: false)
        case "compact":
            await compactCurrentSession()
        case "add_dir", "add-dir":
            await addDirectoryToCurrentSession(raw)
        case "fork":
            await forkCurrentSession(task: args.joined(separator: " "))
        case "themes", "theme":
            showThemePicker()
        case "bar":
            changeBarColor(args.first)
        case "copy":
            copyLastAssistantResponse()
        case "diff":
            await showDiff()
        case "feedback":
            openFeedbackPage()
        case "plan-web", "plans", "open-plan":
            await openPlanWebPage(planName: args.first)
        case "effort":
            setReasoningEffort(args.first)
        case "skills":
            await showSkills()
        case "editor":
            await openCodeEditor(args)
        case "model":
            await switchModel(args.first)
        case "context":
            await attachContext(args.first)
        case "tasks":
            await showTasks()
        case "mcps", "mcp":
            await showMCPServers()
        case "provider", "providers":
            if args.isEmpty {
                await showProviderPicker()
            } else {
                await configureProvider(args)
            }
        case "remote":
            await handleRemoteCommand(args)
        case "local":
            await switchToLocalInstance()
        case "openai-device":
            await startOpenAIDeviceFlow()
        case "anthropic-oauth":
            await startAnthropicOAuth()
        case "anthropic-callback":
            await completeAnthropicOAuth(args.joined(separator: " "))
        case "quit", "exit":
            await stopTUI(reason: "TUI /\(command)")
        default:
            if skillSlashCommandNames.contains(command) {
                await sendMessage(raw)
                return
            }
            showSystemNotice("Unknown command `\(raw)`. Try `/help`.")
        }
    }

    func shouldHandleSlashCommand(_ value: String) -> Bool {
        SloppyTUISlashCommandRouter.shouldHandle(
            value,
            commandNames: Self.handledSlashCommandNames,
            skillCommandNames: skillSlashCommandNames
        )
    }

    func showHelp() {
        let quickReference = quickReferenceMarkdown()
        let commandLines = allHelpCommands.map { command -> String in
            let usage = command.argument.map { " <\($0)>" } ?? ""
            return "- `\(command.invocationPrefix)\(command.name)\(usage)` — \(command.description ?? command.name)"
        }.joined(separator: "\n")
        appendLocalCard("""
        \(quickReference)

        ## TUI commands
        \(commandLines)

        Paste file paths normally to send them as text. Press Ctrl+V to attach files or images from the macOS clipboard.
        Press `!` on an empty prompt to toggle shell mode; press `!` again on an empty prompt to exit.
        Use `@skill` at the start of a message to invoke a skill. Use `@path` in a message to inline a project file as explicit context. Tab completes command and skill names.
        Use `#` to autocomplete active project tasks by id or title.
        Press Ctrl+O to toggle the full tool-call transcript. Ctrl+G enters the newest subagent session.
        Press Ctrl+P or run `/parent` to return from a subagent to its parent session.
        Use `/subagents` to pick a specific child session.

        ## History scroll
        `/scrollback` controls timeline rendering. `auto` keeps native scrollback for modest histories and switches to the fast viewport when a chat gets large.

        ## Tips
        - Esc interrupts the current run after picker overlays are closed.
        - `/pet` toggles the terminal Sloppie and shows its face/status.
        - `/undo` and `/redo` are scoped to the current session during this TUI run.
        - `/btw <message>` asks a quick side question without interrupting the main flow.
        - `/diff` previews source-control changes; `/context diff` attaches those changes to the next message.
        """)
    }

    func handleRemoteCommand(_ args: [String]) async {
        if args.first?.lowercased() == "add" {
            await addRemoteInstanceFromCommand(Array(args.dropFirst()))
            return
        }
        await showRemoteInstancePicker()
    }

    func showProjectPicker() async {
        refreshStaticChrome(statusLine: "loading projects from \(service.displayName)...")
        do {
            let projects = try await service.listProjects()
            guard !projects.isEmpty else {
                appendLocalCard("No projects available on `\(service.displayName)`.", autoDismissAfter: 8)
                return
            }
            let items = SloppyTUIProjectPicker.items(for: projects, currentProjectID: project.id)
            activePicker = SloppyTUIPicker(
                kind: .project,
                title: "Select project",
                items: items,
                selectedIndex: items.firstIndex(where: \.isCurrent) ?? 0,
                allItems: items,
                supportsSearch: true
            )
            refreshStaticChrome(statusLine: "choose project, Enter to switch workspace, Esc to cancel")
        } catch {
            appendLocalCard("Could not load projects from `\(service.displayName)`: \(String(describing: error))")
        }
    }

    func addRemoteInstanceFromCommand(_ args: [String]) async {
        guard args.count >= 2 else {
            editor.setText("/remote add ")
            appendLocalCard("Usage: `/remote add <title> <url> [token]`", autoDismissAfter: 8)
            requestRender()
            return
        }
        let title = args[0]
        let url = args[1]
        let token = args.dropFirst(2).joined(separator: " ")
        let id = title
            .lowercased()
            .filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        let node = CoreConfig.Node(
            id: id.isEmpty ? "remote-\(UUID().uuidString.prefix(8))" : id,
            title: title,
            url: url,
            token: token,
            enabled: true,
            kind: .sloppyInstance
        )
        do {
            var config = await runtime.service.getConfig()
            config.nodes.append(node)
            _ = try await runtime.service.updateConfig(config)
            appendLocalCard("Linked remote Sloppy instance `\(node.displayTitle)`.", autoDismissAfter: 8)
            await showRemoteInstancePicker()
        } catch {
            appendLocalCard("Could not save remote instance: \(String(describing: error))")
        }
    }

    func showRemoteInstancePicker() async {
        let config = await runtime.service.getConfig()
        pendingRemoteNodes = Dictionary(uniqueKeysWithValues: config.nodes.map { ($0.id, $0) })
        let localCore = runtime.service as? LocalSloppyTUIBackend
        let meshState = try? await localCore?.service.getMeshState()
        let localMeshNodeId = meshState?.localNode?.id
        let allMeshNodes: [MeshNodeRecord] = meshState?.nodes ?? []
        let meshNodes = allMeshNodes
            .filter { node in node.id != localMeshNodeId }
            .sorted { left, right in left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending }
        pendingMeshRemoteNodes = Dictionary(uniqueKeysWithValues: meshNodes.map { ($0.id, $0) })
        var items = [
            SloppyTUIPickerItem(
                value: "__local",
                label: "Local instance",
                description: runtime.configPath,
                isCurrent: !service.isRemote,
                group: "Local"
            )
        ]
        let remotes = config.nodes
            .filter { $0.enabled && $0.isRemoteSloppyInstance }
            .sorted { $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending }
        items.append(contentsOf: remotes.map { node in
            SloppyTUIPickerItem(
                value: node.id,
                label: node.displayTitle,
                description: node.url,
                isCurrent: service.isRemote && service.displayName == node.displayTitle,
                group: "Remote"
            )
        })
        items.append(contentsOf: meshNodes.map { node in
            SloppyTUIPickerItem(
                value: "mesh:\(node.id)",
                label: node.name.isEmpty ? node.id : node.name,
                description: "\(node.status.rawValue) · mesh node · \(node.capabilities.joined(separator: ", "))",
                isCurrent: service.isRemote && service.displayName == (node.name.isEmpty ? node.id : node.name),
                group: "Mesh"
            )
        })
        items.append(
            SloppyTUIPickerItem(
                value: "__add",
                label: "Add Sloppy instance",
                description: "Fill /remote add <title> <url> [token]",
                isCurrent: false,
                group: "Manage"
            )
        )
        activePicker = SloppyTUIPicker(
            kind: .remoteInstance,
            title: "Select Sloppy instance",
            items: items,
            selectedIndex: 0,
            allItems: items,
            supportsSearch: true
        )
        refreshStaticChrome(statusLine: "choose instance, Enter to open projects, Esc to cancel")
    }

    func applyRemoteInstancePickerItem(_ item: SloppyTUIPickerItem) async {
        if item.value == "__local" {
            await switchToLocalInstance()
            return
        }
        if item.value == "__add" {
            activePicker = nil
            editor.setText("/remote add ")
            appendLocalCard("Usage: `/remote add <title> <url> [token]`", autoDismissAfter: 8)
            requestRender()
            return
        }
        if item.value.hasPrefix("mesh:") {
            let nodeId = String(item.value.dropFirst("mesh:".count))
            guard let node = pendingMeshRemoteNodes[nodeId] else {
                appendLocalCard("Mesh node is no longer available.", autoDismissAfter: 8)
                return
            }
            await showMeshRemoteProjectPicker(node: node)
            return
        }
        guard let node = pendingRemoteNodes[item.value] else {
            appendLocalCard("Remote instance is no longer configured.", autoDismissAfter: 8)
            return
        }
        await showRemoteProjectPicker(node: node)
    }

    func showRemoteProjectPicker(node: CoreConfig.Node) async {
        beginOperationStatus(.remote, label: "Loading remote", detail: node.displayTitle)
        defer { endOperationStatus(.remote) }
        refreshStaticChrome(statusLine: "loading remote projects from \(node.displayTitle)...")
        let backend = RemoteSloppyTUIBackend(node: node)
        do {
            let projects = try await backend.listProjects()
            guard !projects.isEmpty else {
                appendLocalCard("Remote instance `\(node.displayTitle)` has no projects.", autoDismissAfter: 8)
                return
            }
            pendingRemoteProjectBackend = backend
            let items = projects
                .sorted { $0.updatedAt > $1.updatedAt }
                .map { project in
                    SloppyTUIPickerItem(
                        value: project.id,
                        label: project.name,
                        description: "\(project.id) · \(project.updatedAt)",
                        isCurrent: false
                    )
                }
            activePicker = SloppyTUIPicker(
                kind: .remoteProject,
                title: "Select remote project",
                items: items,
                selectedIndex: 0,
                allItems: items,
                supportsSearch: true
            )
            refreshStaticChrome(statusLine: "choose remote project, Enter to connect, Esc to cancel")
        } catch {
            appendLocalCard("Could not load remote projects from `\(node.displayTitle)`: \(String(describing: error))")
        }
    }

    func showMeshRemoteProjectPicker(node: MeshNodeRecord) async {
        guard let localCore = runtime.service as? LocalSloppyTUIBackend else {
            appendLocalCard("Mesh remote is only available from the local Sloppy instance.", autoDismissAfter: 8)
            return
        }
        beginOperationStatus(.remote, label: "Loading mesh", detail: node.name)
        defer { endOperationStatus(.remote) }
        let title = node.name.isEmpty ? node.id : node.name
        refreshStaticChrome(statusLine: "loading mesh projects from \(title)...")
        let backend = MeshSloppyTUIBackend(service: localCore.service, node: node)
        do {
            let projects = try await backend.listProjects()
            guard !projects.isEmpty else {
                appendLocalCard("Mesh node `\(title)` has no projects.", autoDismissAfter: 8)
                return
            }
            pendingMeshRemoteProjectNode = node
            let items = projects
                .sorted { $0.updatedAt > $1.updatedAt }
                .map { project in
                    SloppyTUIPickerItem(
                        value: project.id,
                        label: project.name,
                        description: "\(project.id) · \(project.updatedAt.formatted(date: .abbreviated, time: .shortened))",
                        isCurrent: false
                    )
                }
            activePicker = SloppyTUIPicker(
                kind: .remoteProject,
                title: "Select mesh project",
                items: items,
                selectedIndex: 0,
                allItems: items,
                supportsSearch: true
            )
            refreshStaticChrome(statusLine: "choose mesh project, Enter to connect, Esc to cancel")
        } catch {
            appendLocalCard("Could not load mesh projects from `\(title)`: \(String(describing: error))")
        }
    }

    func applyRemoteProjectPickerItem(_ item: SloppyTUIPickerItem) async {
        if let node = pendingMeshRemoteProjectNode {
            guard let localCore = runtime.service as? LocalSloppyTUIBackend else {
                appendLocalCard("Mesh remote is only available from the local Sloppy instance.", autoDismissAfter: 8)
                return
            }
            let backend = MeshSloppyTUIBackend(service: localCore.service, node: node, projectID: item.value)
            await switchBackend(backend, projectID: item.value, statusPrefix: "mesh \(node.name.isEmpty ? node.id : node.name)")
        } else {
            guard let pending = pendingRemoteProjectBackend else {
                appendLocalCard("Remote instance selection expired.", autoDismissAfter: 8)
                return
            }
            let backend = RemoteSloppyTUIBackend(node: pending.node, projectID: item.value)
            await switchBackend(backend, projectID: item.value, statusPrefix: "remote \(pending.node.displayTitle)")
        }
    }

    func switchToLocalInstance() async {
        await switchBackend(runtime.service, projectID: nil, statusPrefix: "local")
    }

    func switchBackend(_ nextService: any SloppyTUIBackend, projectID: String?, statusPrefix: String) async {
        beginOperationStatus(.remote, label: "Connecting remote", detail: statusPrefix)
        defer { endOperationStatus(.remote) }
        streamTask?.cancel()
        changeTask?.cancel()
        autoDiffTask?.cancel()
        projectSourceControlFooterTask?.cancel()
        projectFileIndexTask?.cancel()
        projectFileReindexTask?.cancel()
        endOperationStatus(.indexing)
        projectTaskAutocompleteTask?.cancel()
        pendingRemoteProjectBackend = nil
        pendingMeshRemoteProjectNode = nil
        activePicker = nil
        projectSourceControlFooterStatus = nil
        refreshStaticChrome(statusLine: "switching to \(statusPrefix)...")
        do {
            service = nextService
            if let projectID {
                project = try await service.getProject(id: projectID)
            } else {
                project = try await service.resolveOrCreateProjectForCurrentDirectory(runtime.cwd)
            }
            let selectionKey = SloppyTUIStateStore.selectionKey(projectId: project.id)
            let selection = state.selections[selectionKey]
            let agents = (try? await service.listAgents(includeSystem: false)) ?? []
            let resolved: SloppyTUILaunchSelection
            if let sessionID = selection?.sessionId?.trimmingCharacters(in: .whitespacesAndNewlines),
               !sessionID.isEmpty,
               let persisted = try? await SloppyTUIApp.resolveLaunchSelection(
                    service: service,
                    project: project,
                    requestedSessionID: sessionID,
                    selection: selection,
                    agents: agents
               ) {
                resolved = persisted
            } else {
                resolved = try await SloppyTUIApp.resolveLaunchSelection(
                    service: service,
                    project: project,
                    requestedSessionID: nil,
                    selection: selection,
                    agents: agents
                )
            }
            agent = resolved.agent
            session = resolved.session
            hasPersistedSession = resolved.hasPersistedSession
            if resolved.hasPersistedSession {
                trackSession(resolved.session, opened: true)
            }
            sessionCards = []
            subSessionCards = []
            workspaceDiffPreview = nil
            projectFileIndex = nil
            projectFileIndexLookup = nil
            projectFileRootURL = nil
            projectFileIndexGeneration += 1
            projectTaskGeneration += 1
            projectTaskSearchCache = nil
            projectTaskAutocompleteLoading = false
            loadProjectFileIndex()
            reloadProjectForTaskAutocompleteIfNeeded()
            streamSession()
            streamChanges()
            scheduleProjectSourceControlFooterRefresh()
            await reloadSkillSlashCommands()
            await refreshSelectedModel()
            await prepareCurrentSessionContext()
            await reloadSession()
            refreshStaticChrome(statusLine: "connected to \(statusPrefix)")
            appendLocalCard("Connected to \(statusPrefix) project `\(project.name)`.", autoDismissAfter: 8)
        } catch {
            service = runtime.service
            appendLocalCard("Could not switch Sloppy instance: \(String(describing: error))")
        }
    }

    func showQuickReference() {
        appendLocalCard("""
        \(quickReferenceMarkdown())

        Keybinding customization is not available yet.
        """)
    }

    func quickReferenceMarkdown() -> String {
        SloppyTUITheme.quickReferenceLines(width: terminal?.columns ?? 80).joined(separator: "\n")
    }

    func showMCPServers() async {
        let statuses = await refreshMCPStatusSummary()
        guard !statuses.isEmpty else {
            appendLocalCard("No MCP servers configured.", autoDismissAfter: 6)
            return
        }

        let summary = SloppyTUIMCPStatusSummary(statuses: statuses)
        let lines = statuses.map(SloppyTUITheme.mcpStatusLine).joined(separator: "\n")
        appendLocalCard("""
        ## MCP servers
        \(SloppyTUITheme.mcpSummaryLine(summary))

        \(lines)
        """, autoDismissAfter: 20)
    }

    func refreshMCPStatusSummary() async -> [MCPServerStatus] {
        let statuses = await service.listMCPServerStatuses()
        mcpStatusSummary = SloppyTUIMCPStatusSummary(statuses: statuses)
        refreshStaticChrome()
        return statuses
    }

    func createNewSession() async {
        resetToDraftSession()
    }

    func createBackgroundSession(task rawTask: String) async {
        let task = rawTask.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !task.isEmpty else {
            appendLocalCard("Usage: `/bg <task>`")
            return
        }
        guard !service.isRemote else {
            appendLocalCard("`/bg` worktree sessions are only available for the local Sloppy instance in v1.")
            return
        }

        do {
            let background = try await service.startTUIBackgroundSession(
                agentID: agent.id,
                projectID: project.id,
                task: task,
                mode: chatMode,
                reasoningEffort: reasoningEffort
            )
            trackSession(
                background.session,
                background: true,
                worktreePath: background.worktree.worktreePath,
                worktreeBranch: background.worktree.branchName
            )
            appendLocalCard("Background session started: `\(SloppyTUITheme.shortID(background.session.id))` on `\(background.worktree.branchName)`.", autoDismissAfter: 8)
            if sessionListMode != .hidden {
                refreshSessionList()
            }
        } catch {
            appendLocalCard("Background session failed: \(String(describing: error))")
        }
    }

    func handleGoalCommand(_ args: [String]) async {
        switch SloppyTUIGoalCommand.parse(args) {
        case .failure(let message):
            appendLocalCard(message)
        case .task(let objective):
            await createGoalTask(objective: objective)
        case .start(let objective):
            guard !service.isRemote else {
                appendLocalCard("`/goal` is only available for the local Sloppy instance in v1.")
                return
            }
            do {
                _ = try await ensurePersistedSessionForMessage()
                let goal = try await service.startAgentSessionGoal(
                    agentID: agent.id,
                    sessionID: session.id,
                    request: AgentSessionGoalStartRequest(
                        objective: objective,
                        userId: "goal",
                        reasoningEffort: reasoningEffort,
                        mode: chatMode
                    )
                )
                appendLocalCard(goalStatusMarkdown(goal, title: "Goal started"), autoDismissAfter: 10)
                await reloadSession()
            } catch {
                appendLocalCard("Goal failed: \(String(describing: error))")
            }
        case .status:
            do {
                if let goal = try await service.getAgentSessionGoal(agentID: agent.id, sessionID: session.id) {
                    appendLocalCard(goalStatusMarkdown(goal, title: "Goal status"), autoDismissAfter: 12)
                } else {
                    appendLocalCard("No active goal for this session.", autoDismissAfter: 8)
                }
            } catch {
                appendLocalCard("Goal status failed: \(String(describing: error))")
            }
        case .pause:
            do {
                if let goal = try await service.pauseAgentSessionGoal(agentID: agent.id, sessionID: session.id) {
                    appendLocalCard(goalStatusMarkdown(goal, title: "Goal paused"), autoDismissAfter: 10)
                } else {
                    appendLocalCard("No active goal to pause.", autoDismissAfter: 8)
                }
            } catch {
                appendLocalCard("Goal pause failed: \(String(describing: error))")
            }
        case .resume:
            do {
                if let goal = try await service.resumeAgentSessionGoal(agentID: agent.id, sessionID: session.id) {
                    appendLocalCard(goalStatusMarkdown(goal, title: "Goal resumed"), autoDismissAfter: 10)
                    await reloadSession()
                } else {
                    appendLocalCard("No paused goal to resume.", autoDismissAfter: 8)
                }
            } catch {
                appendLocalCard("Goal resume failed: \(String(describing: error))")
            }
        case .clear:
            do {
                if let goal = try await service.clearAgentSessionGoal(agentID: agent.id, sessionID: session.id) {
                    appendLocalCard(goalStatusMarkdown(goal, title: "Goal cleared"), autoDismissAfter: 8)
                } else {
                    appendLocalCard("No goal to clear.", autoDismissAfter: 8)
                }
            } catch {
                appendLocalCard("Goal clear failed: \(String(describing: error))")
            }
        }
    }

    func createGoalTask(objective: String) async {
        let request = SloppyTUIGoalTaskFormatter.request(objective: objective)
        do {
            let updatedProject = try await service.createProjectTask(projectID: project.id, request: request)
            project = updatedProject
            let task = updatedProject.tasks.last { task in
                task.title == request.title && task.description == request.description
            } ?? updatedProject.tasks.last
            if let task {
                appendLocalCard("""
                ## Goal task created
                - task: `\(task.id)`
                - status: `\(task.status)`
                - objective: \(objective)
                """, autoDismissAfter: 10)
            } else {
                appendLocalCard("Goal task created.", autoDismissAfter: 8)
            }
            refreshStaticChrome()
            if sessionListMode != .hidden {
                refreshSessionList()
            }
        } catch {
            appendLocalCard("Goal task failed: \(String(describing: error))")
        }
    }

    func goalStatusMarkdown(_ goal: AgentSessionGoalRecord, title: String) -> String {
        var lines = [
            "## \(title)",
            "- status: `\(goal.status.rawValue)`",
            "- attempts: `\(goal.attemptCount)/\(goal.maxAttempts)`",
            "- objective: \(goal.objective)",
        ]
        if let evaluation = goal.lastEvaluation {
            lines.append("- last evaluation: \(evaluation.reason)")
        }
        return lines.joined(separator: "\n")
    }

    func openSessionList(mode: SloppyTUISessionListMode) {
        sessionListMode = mode
        sessionListSelectedIndex = SloppyTUISessionList.clampedSelection(
            sessionListSelectedIndex,
            entryCount: sessionListEntries.count
        )
        refreshSessionList()
        refreshStaticChrome(statusLine: "enter to open · space to reply · ctrl+x to hide · ? for shortcuts")
    }

    func refreshSessionList() {
        sessionListRefreshTask?.cancel()
        sessionListRefreshTask = Task { [weak self] in
            guard let self else { return }
            await self.reloadSessionListEntries()
        }
    }

    func reloadSessionListEntries() async {
        let tracked = trackedSessionsForCurrentProject()
        var entries: [SloppyTUISessionListEntry] = []
        for item in tracked {
            guard let detail = try? await service.getAgentSession(agentID: item.agentId, sessionID: item.sessionId) else {
                continue
            }
            let section = SloppyTUISessionList.section(
                for: detail.events,
                isPosting: postingSessionIDs.contains(item.sessionId)
            )
            entries.append(SloppyTUISessionListEntry(
                tracked: item,
                summary: detail.summary,
                section: section,
                detail: sessionListDetail(for: detail, tracked: item)
            ))
        }
        sessionListEntries = SloppyTUISessionList.sortedEntries(entries)
        sessionListSelectedIndex = SloppyTUISessionList.clampedSelection(
            sessionListSelectedIndex,
            entryCount: sessionListEntries.count
        )
        requestRender()
    }
}

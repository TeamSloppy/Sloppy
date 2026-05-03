import Foundation
#if canImport(AppKit)
import AppKit
#endif
import Protocols
import TauTUI

struct SloppyTUIApp {
    var configPath: String?
    var requestedSessionID: String?

    init(configPath: String? = nil, requestedSessionID: String? = nil) {
        self.configPath = configPath
        self.requestedSessionID = requestedSessionID
    }

    @MainActor
    func run() async throws {
        let runtime = try await SloppyTUIBootstrap(configPath: configPath).prepare()
        defer {
            Task { await runtime.service.shutdownChannelPlugins() }
        }

        let project = try await runtime.service.resolveOrCreateProjectForCurrentDirectory(runtime.cwd)
        let stateStore = SloppyTUIStateStore(workspaceRoot: runtime.workspaceRoot)
        let state = stateStore.load()
        let selectionKey = SloppyTUIStateStore.selectionKey(projectId: project.id)
        let selection = state.selections[selectionKey]

        let agents = (try? await runtime.service.listAgents(includeSystem: false)) ?? []
        let resolved: (agent: AgentSummary, session: AgentSessionSummary)
        if let requestedSessionID = requestedSessionID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !requestedSessionID.isEmpty {
            resolved = try await resolveExplicitSession(
                service: runtime.service,
                projectID: project.id,
                sessionID: requestedSessionID,
                agents: agents
            )
        } else {
            let agent = try await resolveAgent(
                service: runtime.service,
                preferredID: selection?.agentId,
                agents: agents
            )
            let session = try await resolveSession(
                service: runtime.service,
                projectID: project.id,
                agentID: agent.id,
                preferredID: selection?.sessionId
            )
            resolved = (agent, session)
        }
        let agent = resolved.agent
        let session = resolved.session

        var nextState = state
        nextState.selections[selectionKey] = .init(agentId: agent.id, sessionId: session.id)
        stateStore.save(nextState)

        try await withCheckedThrowingContinuation { continuation in
            do {
                try startTUI(
                    runtime: runtime,
                    project: project,
                    agent: agent,
                    session: session,
                    stateStore: stateStore,
                    state: nextState,
                    continuation: continuation
                )
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    @MainActor
    private func startTUI(
        runtime: SloppyTUIRuntime,
        project: ProjectRecord,
        agent: AgentSummary,
        session: AgentSessionSummary,
        stateStore: SloppyTUIStateStore,
        state: SloppyTUIState,
        continuation: CheckedContinuation<Void, Error>
    ) throws {
        let runHandle = SloppyTUIRunHandle(continuation: continuation)
        do {
            let terminal = ProcessTerminal()
            let tui = TUI(terminal: terminal)
            let screen = SloppyTUIScreen(
                runtime: runtime,
                project: project,
                agent: agent,
                session: session,
                stateStore: stateStore,
                state: state,
                tui: tui,
                terminal: terminal
            )
            screen.onExit = { runHandle.finish() }
            runHandle.tui = tui
            runHandle.screen = screen
            tui.addChild(screen)
            tui.apply(theme: SloppyTUITheme.palette)
            tui.setFocus(screen)

            tui.onControlC = {
                runHandle.finish()
            }

            try tui.start()
            screen.start()
        } catch {
            runHandle.finish(with: error)
        }
    }

    private func resolveAgent(
        service: CoreService,
        preferredID: String?,
        agents: [AgentSummary]
    ) async throws -> AgentSummary {
        if let preferredID,
           let agent = agents.first(where: { $0.id == preferredID }) {
            return agent
        }
        if let first = agents.first {
            return first
        }
        return try await service.createAgent(
            AgentCreateRequest(
                id: "sloppy",
                displayName: "SLOPPY",
                role: "SLOPPY"
            )
        )
    }

    private func resolveSession(
        service: CoreService,
        projectID: String,
        agentID: String,
        preferredID: String?
    ) async throws -> AgentSessionSummary {
        let sessions = (try? await service.listAgentSessions(agentID: agentID, projectID: projectID)) ?? []
        if let preferredID,
           let session = sessions.first(where: { $0.id == preferredID }) {
            return session
        }
        if let latest = sessions.sorted(by: { $0.updatedAt > $1.updatedAt }).first {
            return latest
        }
        return try await service.createAgentSession(
            agentID: agentID,
            request: AgentSessionCreateRequest(
                title: "TUI chat",
                projectId: projectID
            )
        )
    }

    private func resolveExplicitSession(
        service: CoreService,
        projectID: String,
        sessionID: String,
        agents: [AgentSummary]
    ) async throws -> (agent: AgentSummary, session: AgentSessionSummary) {
        for agent in agents {
            let sessions = (try? await service.listAgentSessions(agentID: agent.id, projectID: projectID)) ?? []
            if let session = sessions.first(where: { $0.id == sessionID }) {
                return (agent, session)
            }
        }
        throw SloppyTUIError.sessionNotFound(sessionID)
    }
}

private enum SloppyTUIError: LocalizedError {
    case sessionNotFound(String)

    var errorDescription: String? {
        switch self {
        case .sessionNotFound(let id):
            return "No TUI session `\(id)` was found for this directory. Run `sloppy`, then choose `/sessions` to see available sessions."
        }
    }
}

private enum SloppyTUIAttachmentLimits {
    static let maxBytes = 25 * 1024 * 1024
}

private enum SloppyTUIAttachmentError: LocalizedError {
    case notAFile
    case tooLarge(Int)

    var errorDescription: String? {
        switch self {
        case .notAFile:
            return "not a file"
        case .tooLarge(let bytes):
            return "file is too large (\(bytes) bytes)"
        }
    }
}

@MainActor
private final class SloppyTUIRunHandle: @unchecked Sendable {
    var tui: TUI?
    var screen: SloppyTUIScreen?

    private var continuation: CheckedContinuation<Void, Error>?
    private var didFinish = false

    init(continuation: CheckedContinuation<Void, Error>) {
        self.continuation = continuation
    }

    func finish() {
        finish(with: nil)
    }

    func finish(with error: Error?) {
        guard !didFinish else { return }
        didFinish = true

        screen?.stopBackgroundTasks()
        screen?.onExit = nil
        tui?.onControlC = nil
        tui?.stop()
        tui?.clear()

        let continuation = continuation
        self.continuation = nil
        screen = nil
        tui = nil

        if let error {
            continuation?.resume(throwing: error)
        } else {
            continuation?.resume()
        }
    }
}

@MainActor
final class SloppyTUIScreen: @preconcurrency Component, @unchecked Sendable {
    let editor = Editor()
    var onExit: (@MainActor @Sendable () -> Void)?

    private static let slashCommands = [
        SloppyTUISlashCommand("help", "Show TUI commands"),
        SloppyTUISlashCommand("status", "Show session status"),
        SloppyTUISlashCommand("agents", "Switch agent"),
        SloppyTUISlashCommand("sessions", "Switch session"),
        SloppyTUISlashCommand("new", "Create a new session"),
        SloppyTUISlashCommand("clear", "Clear local cards"),
        SloppyTUISlashCommand("stop", "Interrupt the current run"),
        SloppyTUISlashCommand("model", "Switch agent model"),
        SloppyTUISlashCommand("context", "Attach changes or git diff"),
        SloppyTUISlashCommand("tasks", "Show project tasks"),
        SloppyTUISlashCommand("provider", "Configure provider"),
        SloppyTUISlashCommand("quit", "Exit TUI"),
    ]

    private let runtime: SloppyTUIRuntime
    private var project: ProjectRecord
    private var agent: AgentSummary
    private var session: AgentSessionSummary
    private let stateStore: SloppyTUIStateStore
    private var state: SloppyTUIState
    private weak var tui: TUI?
    private weak var terminal: Terminal?

    private let header = Text(paddingX: 1, paddingY: 0)
    private let timeline = MarkdownComponent(padding: .init(horizontal: 1, vertical: 0))
    private let status = Text(paddingX: 1, paddingY: 0)

    private var sessionCards: [SloppyTUITimelineBlock] = []
    private var localCards: [SloppyTUITimelineBlock] = []
    private var pendingContext: String?
    private var pendingUploads: [AgentAttachmentUpload] = []
    private var chatMode: AgentChatMode = .ask
    private var selectedModel = "default"
    private var commandPaletteSelection = 0
    private var streamTask: Task<Void, Never>?
    private var changeTask: Task<Void, Never>?
    private var devicePollTask: Task<Void, Never>?
    private var thinkingAnimationTask: Task<Void, Never>?
    private var lastChangeBatch: ProjectWorkingTreeChangeBatch?
    private var lastRenderedSessionEventIDs: Set<String> = []
    private var activePicker: SloppyTUIPicker?
    private var liveAssistantDraft: String?
    private var thinkingFrame = 0
    private var thinkingWord = "thinking"
    private var welcomeDismissed = false
    private var isPosting = false

    init(
        runtime: SloppyTUIRuntime,
        project: ProjectRecord,
        agent: AgentSummary,
        session: AgentSessionSummary,
        stateStore: SloppyTUIStateStore,
        state: SloppyTUIState,
        tui: TUI,
        terminal: Terminal
    ) {
        self.runtime = runtime
        self.project = project
        self.agent = agent
        self.session = session
        self.stateStore = stateStore
        self.state = state
        self.tui = tui
        self.terminal = terminal

        editor.setAutocompleteProvider(
            SloppyTUIAutocompleteProvider(basePath: runtime.cwd)
        )
        editor.onSubmit = { [weak self] value in
            guard let self else { return }
            Task { @MainActor in await self.submit(value) }
        }
        editor.onChange = { [weak self] value in
            self?.persistDraft(value)
        }
        let draftKey = SloppyTUIStateStore.draftKey(
            projectId: project.id,
            agentId: agent.id,
            sessionId: session.id
        )
        editor.setText(state.drafts[draftKey] ?? "")
        refreshStaticChrome()
        renderTimeline()
    }

    func start() {
        Task { @MainActor in await reloadSession() }
        Task { @MainActor in await refreshSelectedModel() }
        streamSession()
        streamChanges()
        if !runtime.config.onboarding.completed {
            appendLocalCard("""
            ## First start bootstrap
            Configure a provider with `/provider <id> <key> [model]`, `/openai-device`, or `/anthropic-oauth`.
            Type the launch prompt when ready; Sloppy will create the onboarding session turn and mark onboarding complete.
            """)
        }
    }

    func stopBackgroundTasks() {
        streamTask?.cancel()
        changeTask?.cancel()
        devicePollTask?.cancel()
        thinkingAnimationTask?.cancel()
    }

    func render(width: Int) -> [String] {
        let height = max(terminal?.rows ?? 24, 12)
        let lines = renderBaseScreen(width: width, height: height)
        return SloppyTUITheme.normalize(lines: lines, width: width, height: height)
    }

    func handle(input: TerminalInput) {
        if handleActivePicker(input: input) {
            return
        }
        if handleCommandPalette(input: input) {
            return
        }
        if handleAttachmentInput(input) {
            return
        }
        if handleModeCycle(input) {
            return
        }
        editor.handle(input: input)
    }

    private func renderBaseScreen(width: Int, height: Int) -> [String] {
        let footer = SloppyTUITheme.appFooter(width: width, cwd: runtime.cwd)
        var composer = editor.render(width: width)
        composer.append(SloppyTUITheme.composerMetaLine(
            width: width,
            mode: chatMode,
            model: selectedModel,
            agent: agent.displayName,
            provider: providerLabel(from: selectedModel)
        ))
        composer.append(footer)

        if let picker = activePicker {
            composer.insert(contentsOf: SloppyTUITheme.pickerLines(width: width, picker: picker, maxVisible: 9), at: 0)
        } else if let palette = commandPaletteLines(width: width) {
            composer.insert(contentsOf: palette, at: 0)
        }

        let bodyHeight = max(1, height - composer.count)
        let body = renderBody(width: width, height: bodyHeight)
        return body + composer
    }

    private func renderBody(width: Int, height: Int) -> [String] {
        let raw: [String]
        if shouldRenderWelcome {
            raw = SloppyTUITheme.welcomeScreen(
                width: width,
                cwd: runtime.cwd,
                project: project.name,
                agent: agent.displayName,
                model: selectedModel,
                mode: chatMode,
                includeFooter: false
            )
        } else {
            raw = header.render(width: width) + renderTimelineBlocks(width: width) + status.render(width: width)
        }

        if raw.count >= height {
            return Array(raw.suffix(height))
        }
        return raw + Array(repeating: "", count: height - raw.count)
    }

    private func handleActivePicker(input: TerminalInput) -> Bool {
        guard var picker = activePicker else { return false }
        guard case let .key(key, _) = input else { return true }
        guard !picker.items.isEmpty else {
            activePicker = nil
            requestRender()
            return true
        }

        switch key {
        case .arrowUp:
            picker.selectedIndex = max(0, picker.selectedIndex - 1)
            activePicker = picker
            requestRender()
            return true
        case .arrowDown:
            picker.selectedIndex = min(picker.items.count - 1, picker.selectedIndex + 1)
            activePicker = picker
            requestRender()
            return true
        case .enter, .tab:
            let item = picker.items[picker.selectedIndex]
            activePicker = nil
            requestRender()
            Task { @MainActor in
                await self.applyPickerItem(item, kind: picker.kind)
            }
            return true
        case .escape:
            activePicker = nil
            refreshStaticChrome()
            return true
        default:
            return true
        }
    }

    private func handleCommandPalette(input: TerminalInput) -> Bool {
        guard commandPaletteVisible else { return false }
        guard case let .key(key, _) = input else { return false }
        let commands = commandPaletteSuggestions()
        guard !commands.isEmpty else { return false }

        switch key {
        case .arrowUp:
            commandPaletteSelection = max(0, commandPaletteSelection - 1)
            requestRender()
            return true
        case .arrowDown:
            commandPaletteSelection = min(commands.count - 1, commandPaletteSelection + 1)
            requestRender()
            return true
        case .enter, .tab:
            applyCommandPaletteSelection(commands[commandPaletteSelection])
            return true
        case .escape:
            editor.setText("")
            commandPaletteSelection = 0
            requestRender()
            return true
        default:
            return false
        }
    }

    private func handleAttachmentInput(_ input: TerminalInput) -> Bool {
        switch input {
        case .paste(let text):
            let urls = attachmentURLs(fromPastedText: text)
            guard !urls.isEmpty else { return false }
            addPendingAttachmentFiles(urls)
            return true
        case .key(.character("v"), let modifiers) where modifiers.contains(.control):
            pasteAttachmentFromClipboard()
            return true
        default:
            return false
        }
    }

    private func handleModeCycle(_ input: TerminalInput) -> Bool {
        guard case .key(.tab, let modifiers) = input, modifiers.isEmpty else {
            return false
        }
        chatMode = chatMode.next
        refreshStaticChrome()
        return true
    }

    private var commandPaletteVisible: Bool {
        let value = editor.getText()
        guard value.hasPrefix("/") else { return false }
        guard !value.contains(" ") else { return false }
        return !value.contains("\n")
    }

    private func commandPaletteSuggestions() -> [SloppyTUISlashCommand] {
        let prefix = String(editor.getText().dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let matches: [SloppyTUISlashCommand]
        if prefix.isEmpty {
            matches = Self.slashCommands
        } else {
            matches = Self.slashCommands.filter { command in
                command.name.lowercased().hasPrefix(prefix)
            }
        }
        if commandPaletteSelection >= matches.count {
            commandPaletteSelection = max(0, matches.count - 1)
        }
        return matches
    }

    private func commandPaletteLines(width: Int) -> [String]? {
        guard commandPaletteVisible else { return nil }
        let suggestions = commandPaletteSuggestions()
        guard !suggestions.isEmpty else { return nil }
        return SloppyTUITheme.commandPaletteLines(
            width: width,
            commands: suggestions,
            selectedIndex: commandPaletteSelection,
            maxVisible: 9
        )
    }

    private func applyCommandPaletteSelection(_ command: SloppyTUISlashCommand) {
        commandPaletteSelection = 0
        let raw = "/\(command.name)"
        if command.requiresArgument {
            editor.setText(raw + " ")
            requestRender()
            return
        }

        editor.setText("")
        persistDraft("")
        requestRender()
        Task { @MainActor in
            await self.handleCommand(raw)
        }
    }

    private func providerLabel(from model: String) -> String {
        if let separator = model.firstIndex(of: ":") {
            return String(model[..<separator])
        }
        return "native"
    }

    private func submit(_ raw: String) async {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty || !pendingUploads.isEmpty else {
            return
        }
        if !value.isEmpty {
            editor.addToHistory(value)
        }
        editor.setText("")
        persistDraft("")

        if value.hasPrefix("/") {
            await handleCommand(value)
            return
        }

        welcomeDismissed = true
        await sendMessage(value)
    }

    private func sendMessage(_ value: String) async {
        guard !isPosting else {
            appendLocalCard("A message is already in flight. Use `/stop` if you need to interrupt it.")
            return
        }

        isPosting = true
        liveAssistantDraft = ""
        startThinkingAnimation()
        renderTimeline()
        refreshStaticChrome(statusLine: "sending...")
        let uploads = pendingUploads
        let content = await messageContentWithInlineAttachments(value, uploads: uploads)
        do {
            if !runtime.config.onboarding.completed {
                var config = await runtime.service.getConfig()
                config.onboarding.completed = true
                _ = try await runtime.service.updateConfig(config)
            }
            let config = await runtime.service.getConfig()
            _ = try await runtime.service.postAgentSessionMessage(
                agentID: agent.id,
                sessionID: session.id,
                request: AgentSessionPostMessageRequest(
                    userId: config.onboarding.completed ? "tui" : "onboarding",
                    content: content,
                    attachments: uploads,
                    spawnSubSession: false,
                    mode: chatMode
                )
            )
            pendingContext = nil
            pendingUploads.removeAll()
            await reloadSession()
        } catch {
            liveAssistantDraft = nil
            appendLocalCard("Message failed: \(String(describing: error))")
        }
        isPosting = false
        stopThinkingAnimation()
        liveAssistantDraft = nil
        refreshStaticChrome()
        renderTimeline()
    }

    private func handleCommand(_ raw: String) async {
        let parts = raw.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        let command = parts.first.map { String($0.dropFirst()).lowercased() } ?? ""
        let args = Array(parts.dropFirst())

        switch command {
        case "help":
            appendLocalCard("""
            ## TUI commands
            `/status`, `/sessions`, `/new`, `/clear`, `/stop`, `/model <id>`, `/context changes`, `/context diff`, `/tasks`, `/provider`, `/provider <id> <key> [model]`, `/quit`.

            Use `@path` in a message to inline a project file as explicit context. Tab completes slash commands.
            """)
        case "status":
            await showStatus()
        case "agents", "agent":
            await showAgentPicker()
        case "sessions", "session":
            await showSessionPicker()
        case "new":
            await createNewSession()
        case "clear":
            localCards.removeAll()
            renderTimeline()
        case "stop":
            await stopCurrentRun()
        case "model":
            await switchModel(args.first)
        case "context":
            await attachContext(args.first)
        case "tasks":
            await showTasks()
        case "provider", "providers":
            if args.isEmpty {
                await showProviderPicker()
            } else {
                await configureProvider(args)
            }
        case "openai-device":
            await startOpenAIDeviceFlow()
        case "anthropic-oauth":
            await startAnthropicOAuth()
        case "anthropic-callback":
            await completeAnthropicOAuth(args.joined(separator: " "))
        case "quit", "exit":
            stopTUI()
        default:
            appendLocalCard("Unknown command `\(raw)`. Try `/help`.")
        }
    }

    private func createNewSession() async {
        do {
            session = try await runtime.service.createAgentSession(
                agentID: agent.id,
                request: AgentSessionCreateRequest(
                    title: "TUI chat",
                    checkpointSessionId: session.id,
                    projectId: project.id
                )
            )
            persistSelection()
            streamSession()
            await reloadSession()
        } catch {
            appendLocalCard("Could not create session: \(String(describing: error))")
        }
    }

    private func stopCurrentRun() async {
        do {
            _ = try await runtime.service.controlAgentSession(
                agentID: agent.id,
                sessionID: session.id,
                request: AgentSessionControlRequest(action: .interruptTree, requestedBy: "tui", reason: "TUI /stop")
            )
            appendLocalCard("Stop requested.")
        } catch {
            appendLocalCard("Stop failed: \(String(describing: error))")
        }
    }

    private func showStatus() async {
        let config = try? await runtime.service.getAgentConfig(agentID: agent.id)
        let model = config?.selectedModel ?? selectedModel
        selectedModel = model
        appendLocalCard("""
        ## Status
        - project: `\(project.name)`
        - agent: `\(agent.displayName)`
        - session: `\(session.title)`
        - session id: `\(session.id)`
        - resume: `sloppy -s \(session.id)`
        - model: `\(model)`
        - provider: `\(providerLabel(from: model))`
        """)
    }

    private func showAgentPicker() async {
        let agents = (try? await runtime.service.listAgents(includeSystem: false)) ?? []
        guard !agents.isEmpty else {
            appendLocalCard("No agents available.")
            return
        }
        let ordered = orderedAgentsForPicker(agents)
        activePicker = SloppyTUIPicker(
            kind: .agent,
            title: "Select agent",
            items: ordered.map { item in
                SloppyTUIPickerItem(
                    value: item.id,
                    label: item.displayName,
                    description: item.role.isEmpty ? item.id : item.role,
                    isCurrent: item.id == agent.id
                )
            },
            selectedIndex: 0
        )
        refreshStaticChrome(statusLine: "select agent with arrows, Enter to apply, Esc to cancel")
    }

    private func showSessionPicker() async {
        let sessions = ((try? await runtime.service.listAgentSessions(agentID: agent.id, projectID: project.id)) ?? [])
            .sorted { lhs, rhs in
                if lhs.id == session.id { return true }
                if rhs.id == session.id { return false }
                return lhs.updatedAt > rhs.updatedAt
            }

        guard !sessions.isEmpty else {
            appendLocalCard("No sessions for `\(agent.displayName)` in this directory.")
            return
        }

        activePicker = SloppyTUIPicker(
            kind: .session,
            title: "Select session",
            items: sessions.map { item in
                SloppyTUIPickerItem(
                    value: item.id,
                    label: item.title.isEmpty ? item.id : item.title,
                    description: SloppyTUITheme.sessionPickerDescription(item),
                    isCurrent: item.id == session.id
                )
            },
            selectedIndex: 0
        )
        refreshStaticChrome(statusLine: "select session with arrows, Enter to open, Esc to cancel")
    }

    private func switchModel(_ model: String?) async {
        guard let model, !model.isEmpty else {
            await showModelPicker()
            return
        }
        await applyModel(model)
    }

    private func showModelPicker() async {
        do {
            let config = try await runtime.service.getAgentConfig(agentID: agent.id)
            let selected = config.selectedModel ?? selectedModel
            selectedModel = selected
            let models = orderedModelsForPicker(config.availableModels, selected: selected)
            guard !models.isEmpty else {
                appendLocalCard("No available models.")
                return
            }
            activePicker = SloppyTUIPicker(
                kind: .model,
                title: "Select model",
                items: models.map { model in
                    SloppyTUIPickerItem(
                        value: model.id,
                        label: model.id,
                        description: model.title == model.id ? nil : model.title,
                        isCurrent: model.id == selected
                    )
                },
                selectedIndex: 0
            )
            refreshStaticChrome(statusLine: "select model with arrows, Enter to apply, Esc to cancel")
        } catch {
            appendLocalCard("Could not load models: \(String(describing: error))")
        }
    }

    private func applyPickerItem(_ item: SloppyTUIPickerItem, kind: SloppyTUIPickerKind) async {
        switch kind {
        case .model:
            await applyModel(item.value)
        case .agent:
            await switchAgent(item.value)
        case .session:
            await switchSession(item.value)
        case .provider:
            if item.value == SloppyTUIProviderDefinition.addNewProviderValue {
                showProviderCatalogPicker()
            } else {
                await applyModel(item.value)
            }
        case .providerCatalog:
            await beginProviderSetup(item.value)
        }
    }

    private func applyModel(_ model: String) async {
        do {
            let config = try await runtime.service.getAgentConfig(agentID: agent.id)
            _ = try await runtime.service.updateAgentConfig(
                agentID: agent.id,
                request: AgentConfigUpdateRequest(
                    role: config.role,
                    selectedModel: model,
                    documents: config.documents,
                    heartbeat: config.heartbeat,
                    channelSessions: config.channelSessions,
                    runtime: config.runtime
                )
            )
            selectedModel = model
            appendLocalCard("Model switched to `\(model)`.")
        } catch {
            appendLocalCard("Model switch failed: \(String(describing: error))")
        }
    }

    private func orderedModelsForPicker(_ models: [ProviderModelOption], selected: String) -> [ProviderModelOption] {
        guard let selectedIndex = models.firstIndex(where: { $0.id == selected }) else {
            return models
        }
        var ordered = models
        let selectedModel = ordered.remove(at: selectedIndex)
        ordered.insert(selectedModel, at: 0)
        return ordered
    }

    private func orderedAgentsForPicker(_ agents: [AgentSummary]) -> [AgentSummary] {
        guard let selectedIndex = agents.firstIndex(where: { $0.id == agent.id }) else {
            return agents
        }
        var ordered = agents
        let selectedAgent = ordered.remove(at: selectedIndex)
        ordered.insert(selectedAgent, at: 0)
        return ordered
    }

    private func showProviderPicker() async {
        let config = await runtime.service.getConfig()
        let agentConfig = try? await runtime.service.getAgentConfig(agentID: agent.id)
        let selected = agentConfig?.selectedModel ?? selectedModel
        selectedModel = selected

        var items = config.models
            .filter { !$0.disabled }
            .map { model -> SloppyTUIPickerItem in
                let runtimeModel = runtimeModelID(for: model)
                return SloppyTUIPickerItem(
                    value: runtimeModel,
                    label: providerTitle(for: model),
                    description: SloppyTUITheme.compactPickerDescription(runtimeModel),
                    isCurrent: runtimeModel == selected || model.model == selected
                )
            }

        items.sort { lhs, rhs in
            if lhs.isCurrent != rhs.isCurrent { return lhs.isCurrent }
            return lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
        }
        items.append(
            SloppyTUIPickerItem(
                value: SloppyTUIProviderDefinition.addNewProviderValue,
                label: "+ Add new provider",
                description: "Configure another provider",
                isCurrent: false
            )
        )

        activePicker = SloppyTUIPicker(
            kind: .provider,
            title: "Select provider",
            items: items,
            selectedIndex: 0
        )
        refreshStaticChrome(statusLine: "select provider with arrows, Enter to apply, Esc to cancel")
    }

    private func showProviderCatalogPicker() {
        activePicker = SloppyTUIPicker(
            kind: .providerCatalog,
            title: "Add provider",
            items: SloppyTUIProviderDefinition.catalog.map { definition in
                SloppyTUIPickerItem(
                    value: definition.id,
                    label: definition.title,
                    description: definition.setupDescription,
                    isCurrent: false
                )
            },
            selectedIndex: 0
        )
        refreshStaticChrome(statusLine: "select provider type with arrows, Enter to configure, Esc to cancel")
    }

    private func beginProviderSetup(_ providerID: String) async {
        let definition = SloppyTUIProviderDefinition(providerID)
        switch definition.id {
        case "openai-oauth":
            await startOpenAIDeviceFlow()
        case "anthropic-oauth":
            await startAnthropicOAuth()
        default:
            if definition.requiresAPIKey {
                editor.setText("/provider \(definition.id) ")
                persistDraft(editor.getText())
                refreshStaticChrome(statusLine: "enter API key for \(definition.title), optionally followed by a model")
            } else {
                await configureProvider([definition.id])
            }
        }
    }

    private func switchAgent(_ agentID: String) async {
        do {
            let agents = try await runtime.service.listAgents(includeSystem: false)
            guard let nextAgent = agents.first(where: { $0.id == agentID }) else {
                appendLocalCard("Agent `\(agentID)` is no longer available.")
                return
            }
            agent = nextAgent
            session = try await resolveSessionForCurrentProject(agentID: nextAgent.id)
            persistSelection()
            streamSession()
            await reloadSession()
            await refreshSelectedModel()
            appendLocalCard("Agent switched to `\(nextAgent.displayName)`.")
        } catch {
            appendLocalCard("Agent switch failed: \(String(describing: error))")
        }
    }

    private func switchSession(_ sessionID: String) async {
        let sessions = (try? await runtime.service.listAgentSessions(agentID: agent.id, projectID: project.id)) ?? []
        guard let nextSession = sessions.first(where: { $0.id == sessionID }) else {
            appendLocalCard("Session `\(sessionID)` is no longer available for `\(agent.displayName)`.")
            return
        }
        session = nextSession
        persistSelection()
        streamSession()
        await reloadSession()
        appendLocalCard("Session switched to `\(nextSession.title)`.\nResume shortcut: `sloppy -s \(nextSession.id)`")
    }

    private func resolveSessionForCurrentProject(agentID: String) async throws -> AgentSessionSummary {
        let sessions = (try? await runtime.service.listAgentSessions(agentID: agentID, projectID: project.id)) ?? []
        if let latest = sessions.sorted(by: { $0.updatedAt > $1.updatedAt }).first {
            return latest
        }
        return try await runtime.service.createAgentSession(
            agentID: agentID,
            request: AgentSessionCreateRequest(
                title: "TUI chat",
                projectId: project.id
            )
        )
    }

    private func attachContext(_ mode: String?) async {
        switch mode?.lowercased() {
        case "changes":
            guard let lastChangeBatch else {
                appendLocalCard("No workspace change batch yet.")
                return
            }
            let paths = lastChangeBatch.changes.map { "- \($0.kind.rawValue): \($0.path)" }.joined(separator: "\n")
            pendingContext = "Workspace changes:\n\(paths)"
            appendLocalCard("Workspace change list will be attached to the next message.")
        case "diff":
            do {
                let git = try await runtime.service.projectWorkingTreeGit(projectID: project.id)
                guard git.isGitRepository, !git.diff.isEmpty else {
                    appendLocalCard(git.message ?? "No git diff to attach.")
                    return
                }
                pendingContext = "Git working tree diff:\n```diff\n\(git.diff)\n```"
                appendLocalCard("Git diff will be attached to the next message.")
            } catch {
                appendLocalCard("Could not read git diff: \(String(describing: error))")
            }
        default:
            appendLocalCard("Use `/context changes` or `/context diff`.")
        }
    }

    private func showTasks() async {
        do {
            let project = try await runtime.service.getProject(id: project.id)
            if project.tasks.isEmpty {
                appendLocalCard("No project tasks.")
                return
            }
            appendLocalCard(project.tasks.map { "- `\($0.id)` [\($0.status)] \($0.title)" }.joined(separator: "\n"))
        } catch {
            appendLocalCard("Could not load tasks: \(String(describing: error))")
        }
    }

    private func runtimeModelID(for model: CoreConfig.ModelConfig) -> String {
        let rawModel = model.model.trimmingCharacters(in: .whitespacesAndNewlines)
        if rawModel.hasPrefix("openai:")
            || rawModel.hasPrefix("openrouter:")
            || rawModel.hasPrefix("ollama:")
            || rawModel.hasPrefix("gemini:")
            || rawModel.hasPrefix("anthropic:") {
            return rawModel
        }
        return providerDefinition(for: model).runtimeModelID(rawModel)
    }

    private func providerTitle(for model: CoreConfig.ModelConfig) -> String {
        providerDefinition(for: model).title
    }

    private func providerDefinition(for model: CoreConfig.ModelConfig) -> SloppyTUIProviderDefinition {
        if let catalog = model.providerCatalogId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !catalog.isEmpty {
            return SloppyTUIProviderDefinition(catalog)
        }
        let title = model.title.lowercased()
        let apiURL = model.apiUrl.lowercased()
        if title.contains("openrouter") || apiURL.contains("openrouter") {
            return SloppyTUIProviderDefinition("openrouter")
        }
        if title.contains("gemini") || apiURL.contains("generativelanguage") {
            return SloppyTUIProviderDefinition("gemini")
        }
        if title.contains("anthropic") || apiURL.contains("anthropic") {
            return SloppyTUIProviderDefinition("anthropic")
        }
        if title.contains("ollama") || apiURL.contains("11434") {
            return SloppyTUIProviderDefinition("ollama")
        }
        if title.contains("oauth") || apiURL.contains("chatgpt.com") {
            return SloppyTUIProviderDefinition("openai-oauth")
        }
        return SloppyTUIProviderDefinition("openai-api")
    }

    private func configureProvider(_ args: [String]) async {
        guard let providerID = args.first else {
            appendLocalCard("Usage: `/provider openai-api|openrouter|gemini|anthropic|ollama <api-key> [model]`")
            return
        }
        let key = args.dropFirst().first ?? ""
        let model = args.dropFirst(2).first
        let definition = SloppyTUIProviderDefinition(providerID)
        if definition.requiresAPIKey && key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            appendLocalCard("Enter an API key: `/provider \(definition.id) <api-key> [model]`")
            return
        }
        var config = await runtime.service.getConfig()
        config.workspace.name = CoreConfig.defaultWorkspaceName
        config.workspace.basePath = "~"
        let entry = CoreConfig.ModelConfig(
            title: definition.title,
            apiKey: definition.requiresAPIKey ? key : "",
            apiUrl: definition.apiURL,
            model: model ?? definition.model,
            providerCatalogId: definition.id
        )
        if let existingIndex = config.models.firstIndex(where: { providerDefinition(for: $0).id == definition.id }) {
            config.models[existingIndex] = entry
        } else {
            config.models.append(entry)
        }
        config.onboarding.completed = false
        do {
            _ = try await runtime.service.updateConfig(config)
            appendLocalCard("Provider saved as `\(definition.id)`. Use `/model \(definition.runtimeModelID(model ?? definition.model))` if you want to switch the active agent now.")
        } catch {
            appendLocalCard("Provider save failed: \(String(describing: error))")
        }
    }

    private func startOpenAIDeviceFlow() async {
        do {
            let response = try await runtime.service.startOpenAIDeviceCode()
            appendLocalCard("""
            ## OpenAI Codex device auth
            Open \(response.verificationURL) and enter code `\(response.userCode)`.
            Polling automatically until approval or timeout.
            """)
            devicePollTask?.cancel()
            devicePollTask = Task { [weak self] in
                guard let self else { return }
                let deadline = Date().addingTimeInterval(TimeInterval(response.expiresIn))
                while !Task.isCancelled, Date() < deadline {
                    try? await Task.sleep(nanoseconds: UInt64(max(response.interval, 2)) * 1_000_000_000)
                    guard !Task.isCancelled else { break }
                    do {
                        let poll = try await self.runtime.service.pollOpenAIDeviceCode(
                            request: .init(deviceAuthId: response.deviceAuthId, userCode: response.userCode)
                        )
                        await MainActor.run {
                            self.appendLocalCard("OpenAI device auth: \(poll.message)")
                        }
                        if poll.ok { break }
                    } catch {
                        await MainActor.run {
                            self.appendLocalCard("OpenAI device auth failed: \(String(describing: error))")
                        }
                        break
                    }
                }
            }
            await configureProvider(["openai-oauth"])
        } catch {
            appendLocalCard("Could not start OpenAI device flow: \(String(describing: error))")
        }
    }

    private func startAnthropicOAuth() async {
        do {
            let response = try await runtime.service.startAnthropicOAuth(
                request: .init(redirectURI: "http://localhost:54545/oauth/anthropic/callback")
            )
            appendLocalCard("""
            ## Anthropic OAuth
            Open \(response.authorizationURL)

            Then paste the callback URL with `/anthropic-callback <url>`.
            """)
            await configureProvider(["anthropic-oauth", ""])
        } catch {
            appendLocalCard("Could not start Anthropic OAuth: \(String(describing: error))")
        }
    }

    private func completeAnthropicOAuth(_ callbackURL: String) async {
        guard !callbackURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            appendLocalCard("Paste the full callback URL: `/anthropic-callback <url>`.")
            return
        }
        do {
            let response = try await runtime.service.completeAnthropicOAuth(request: .init(callbackURL: callbackURL))
            appendLocalCard(response.message)
        } catch {
            appendLocalCard("Anthropic OAuth failed: \(String(describing: error))")
        }
    }

    private func streamSession() {
        streamTask?.cancel()
        streamTask = Task { [weak self] in
            guard let self else { return }
            do {
                let stream = try await self.runtime.service.streamAgentSessionEvents(agentID: self.agent.id, sessionID: self.session.id)
                for await update in stream {
                    guard !Task.isCancelled else { break }
                    await MainActor.run {
                        if update.kind == .sessionDelta, let message = update.message {
                            self.liveAssistantDraft = message
                            self.renderTimeline()
                        } else if update.kind == .sessionEvent, let event = update.event {
                            if self.isFinalAssistantMessage(event) {
                                self.liveAssistantDraft = nil
                                self.stopThinkingAnimation()
                            }
                            Task { await self.reloadSession() }
                        } else if update.kind == .sessionClosed {
                            self.liveAssistantDraft = nil
                            self.stopThinkingAnimation()
                            self.appendLocalCard(update.message ?? "Session closed.")
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    self.appendLocalCard("Session stream failed: \(String(describing: error))")
                }
            }
        }
    }

    private func streamChanges() {
        changeTask?.cancel()
        changeTask = Task { [weak self] in
            guard let self else { return }
            do {
                let stream = try await self.runtime.service.streamProjectWorkingTreeChanges(projectID: self.project.id)
                for await batch in stream {
                    guard !Task.isCancelled else { break }
                    await MainActor.run {
                        self.lastChangeBatch = batch
                    }
                }
            } catch {
                // Keep workspace watching silent so the timeline only shows agent output.
            }
        }
    }

    private func reloadSession() async {
        let detail = try? await runtime.service.getAgentSession(agentID: agent.id, sessionID: session.id)
        var blocks: [SloppyTUITimelineBlock] = []
        let events = detail?.events ?? []
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
                    if message.role == .assistant, SloppyTUITheme.isModelProviderError(body) {
                        blocks.append(.error(body))
                    } else {
                        blocks.append(.message(role: message.role, text: body))
                    }
                }
                if !thinking.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    blocks.append(.thinking(thinking))
                }
                for attachment in attachments {
                    blocks.append(.attachment(name: attachment.name, mimeType: attachment.mimeType, sizeBytes: attachment.sizeBytes))
                }
            } else if let toolCall = event.toolCall {
                blocks.append(.toolCall(tool: toolCall.tool, reason: toolCall.reason, argumentNames: toolCall.arguments.keys.sorted()))
            } else if let toolResult = event.toolResult {
                blocks.append(.toolResult(tool: toolResult.tool, ok: toolResult.ok, error: toolResult.error?.message, durationMs: toolResult.durationMs))
            }
        }
        sessionCards = blocks
        renderTimeline()
    }

    private func isFinalAssistantMessage(_ event: AgentSessionEvent) -> Bool {
        guard event.type == .message,
              let message = event.message,
              message.role == .assistant else {
            return false
        }
        return message.segments.contains { segment in
            segment.kind == .text && segment.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }
    }

    private func renderTimeline() {
        let blocks = sessionCards + liveAssistantBlocks() + localCards
        timeline.text = blocks.map(\.plainText).joined(separator: "\n\n")
        refreshStaticChrome()
        requestRender()
    }

    private func liveAssistantBlocks() -> [SloppyTUITimelineBlock] {
        guard let liveAssistantDraft else {
            return []
        }

        let spinner = SloppyTUITheme.waitingIndicator(frame: thinkingFrame, word: thinkingWord)
        let body = liveAssistantDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if body.isEmpty {
            return [.local(spinner)]
        }
        return [.message(role: .assistant, text: body + "\n\n" + spinner)]
    }

    private func renderTimelineBlocks(width: Int) -> [String] {
        let blocks = sessionCards + liveAssistantBlocks() + localCards
        guard !blocks.isEmpty else {
            return timeline.render(width: width)
        }

        var lines: [String] = []
        for block in blocks {
            if !lines.isEmpty {
                lines.append("")
            }
            switch block {
            case .message(let role, let text):
                if role == .user {
                    lines.append(contentsOf: SloppyTUITheme.userMessageLines(text, width: width))
                } else {
                    lines.append(contentsOf: renderMarkdown(text, width: width))
                }
            case .local(let text):
                lines.append(contentsOf: renderMarkdown(text, width: width))
            case .error(let text):
                lines.append(contentsOf: renderMarkdown(SloppyTUITheme.errorBlock(text), width: width))
            case .thinking(let text):
                lines.append(contentsOf: SloppyTUITheme.thinkingLines(text, width: width))
            case .attachment(let name, let mimeType, let sizeBytes):
                lines.append(SloppyTUITheme.attachmentLine(name: name, mimeType: mimeType, sizeBytes: sizeBytes, width: width))
            case .toolCall(let tool, let reason, let argumentNames):
                lines.append(SloppyTUITheme.toolCallLine(tool: tool, reason: reason, argumentNames: argumentNames, width: width))
            case .toolResult(let tool, let ok, let error, let durationMs):
                lines.append(SloppyTUITheme.toolResultLine(tool: tool, ok: ok, error: error, durationMs: durationMs, width: width))
            }
        }
        return lines
    }

    private func renderMarkdown(_ text: String, width: Int) -> [String] {
        let component = MarkdownComponent(
            text: text,
            padding: .init(horizontal: 1, vertical: 0),
            theme: timeline.theme
        )
        return component.render(width: width)
    }

    private func startThinkingAnimation() {
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

    private func stopThinkingAnimation() {
        thinkingAnimationTask?.cancel()
        thinkingAnimationTask = nil
        thinkingFrame = 0
        thinkingWord = "thinking"
    }

    private func appendLocalCard(_ text: String) {
        localCards.append(.local(text))
        if localCards.count > 24 {
            localCards.removeFirst(localCards.count - 24)
        }
        renderTimeline()
    }

    private func refreshStaticChrome(statusLine: String? = nil) {
        header.text = SloppyTUITheme.header(
            project: project.name,
            agent: agent.displayName,
            session: SloppyTUITheme.sessionHeaderTitle(session)
        )
        let context = pendingContext == nil ? "" : "  context: queued"
        let attachments = pendingUploads.isEmpty ? "" : "  attachments: \(pendingUploads.count)"
        status.text = SloppyTUITheme.status(
            statusLine ?? SloppyTUITheme.sessionStatusLine(
                mode: chatMode,
                model: selectedModel,
                context: context,
                attachments: attachments,
                sessionID: session.id
            ),
            isBusy: statusLine != nil
        )
        requestRender()
    }

    private func refreshSelectedModel() async {
        let config = try? await runtime.service.getAgentConfig(agentID: agent.id)
        selectedModel = config?.selectedModel ?? "default"
        refreshStaticChrome()
    }

    private func requestRender() {
        tui?.requestRender()
    }

    private var shouldRenderWelcome: Bool {
        !welcomeDismissed && localCards.isEmpty
    }

    private func stopTUI() {
        onExit?()
    }

    private func persistSelection() {
        let key = SloppyTUIStateStore.selectionKey(projectId: project.id)
        state.selections[key] = .init(agentId: agent.id, sessionId: session.id)
        stateStore.save(state)
    }

    private func persistDraft(_ value: String) {
        let key = SloppyTUIStateStore.draftKey(projectId: project.id, agentId: agent.id, sessionId: session.id)
        if value.isEmpty {
            state.drafts.removeValue(forKey: key)
        } else {
            state.drafts[key] = value
        }
        stateStore.save(state)
    }

    private func attachmentURLs(fromPastedText text: String) -> [URL] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let candidates = splitPastedPathCandidates(trimmed)
        guard !candidates.isEmpty else { return [] }

        var urls: [URL] = []
        for candidate in candidates {
            if let url = fileURL(fromPastedPathCandidate: candidate),
               FileManager.default.fileExists(atPath: url.path) {
                urls.append(url)
            } else {
                return []
            }
        }
        return urls
    }

    private func splitPastedPathCandidates(_ text: String) -> [String] {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if lines.count > 1 {
            return lines.map(Self.unquotePathCandidate)
        }

        let single = Self.unquotePathCandidate(normalized.trimmingCharacters(in: .whitespacesAndNewlines))
        if FileManager.default.fileExists(atPath: (single as NSString).expandingTildeInPath)
            || single.hasPrefix("file://") {
            return [single]
        }

        return splitEscapedShellPaths(single)
    }

    private func splitEscapedShellPaths(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var isEscaped = false
        var quote: Character?

        for character in text {
            if isEscaped {
                current.append(character)
                isEscaped = false
                continue
            }
            if character == "\\" {
                isEscaped = true
                continue
            }
            if let activeQuote = quote {
                if character == activeQuote {
                    quote = nil
                } else {
                    current.append(character)
                }
                continue
            }
            if character == "\"" || character == "'" {
                quote = character
                continue
            }
            if character.isWhitespace {
                if !current.isEmpty {
                    tokens.append(current)
                    current.removeAll()
                }
            } else {
                current.append(character)
            }
        }
        if isEscaped {
            current.append("\\")
        }
        if !current.isEmpty {
            tokens.append(current)
        }
        return tokens
    }

    private func fileURL(fromPastedPathCandidate candidate: String) -> URL? {
        if candidate.hasPrefix("file://") {
            return URL(string: candidate.removingPercentEncoding ?? candidate)
        }
        let raw = candidate.removingPercentEncoding ?? candidate
        let expanded = (raw as NSString).expandingTildeInPath
        if expanded.hasPrefix("/") {
            return URL(fileURLWithPath: expanded).standardizedFileURL
        }
        return URL(fileURLWithPath: runtime.cwd)
            .appendingPathComponent(expanded)
            .standardizedFileURL
    }

    private static func unquotePathCandidate(_ value: String) -> String {
        var result = value
        if result.count >= 2,
           let first = result.first,
           let last = result.last,
           (first == "\"" && last == "\"") || (first == "'" && last == "'") {
            result.removeFirst()
            result.removeLast()
        }
        return result.replacingOccurrences(of: "\\ ", with: " ")
    }

    private func addPendingAttachmentFiles(_ urls: [URL]) {
        var added: [String] = []
        var skipped: [String] = []
        for url in urls {
            do {
                let upload = try makeAttachmentUpload(from: url)
                pendingUploads.append(upload)
                added.append(upload.name)
            } catch {
                skipped.append("\(url.lastPathComponent): \(String(describing: error))")
            }
        }
        if !added.isEmpty {
            appendLocalCard("Attached \(added.count) file(s): \(added.map { "`\($0)`" }.joined(separator: ", "))")
        }
        if !skipped.isEmpty {
            appendLocalCard("Attachment skipped:\n" + skipped.map { "- \($0)" }.joined(separator: "\n"))
        }
        refreshStaticChrome()
    }

    private func makeAttachmentUpload(from url: URL) throws -> AgentAttachmentUpload {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            throw SloppyTUIAttachmentError.notAFile
        }

        let data = try Data(contentsOf: url)
        guard data.count <= SloppyTUIAttachmentLimits.maxBytes else {
            throw SloppyTUIAttachmentError.tooLarge(data.count)
        }
        return AgentAttachmentUpload(
            name: url.lastPathComponent.isEmpty ? "attachment.bin" : url.lastPathComponent,
            mimeType: mimeType(for: url),
            sizeBytes: data.count,
            contentBase64: data.base64EncodedString()
        )
    }

    private func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "heic": return "image/heic"
        case "tif", "tiff": return "image/tiff"
        case "pdf": return "application/pdf"
        case "json": return "application/json"
        case "md", "markdown": return "text/markdown"
        case "txt", "log": return "text/plain"
        case "csv": return "text/csv"
        case "html", "htm": return "text/html"
        case "swift": return "text/x-swift"
        default: return "application/octet-stream"
        }
    }

    private func pasteAttachmentFromClipboard() {
        #if canImport(AppKit)
        let pasteboard = NSPasteboard.general
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           !urls.isEmpty {
            addPendingAttachmentFiles(urls)
            return
        }

        if let pngData = pasteboard.data(forType: NSPasteboard.PasteboardType("public.png")) {
            addPendingClipboardImage(data: pngData, mimeType: "image/png", extension: "png")
            return
        }
        if let tiffData = pasteboard.data(forType: .tiff),
           let image = NSImage(data: tiffData),
           let pngData = image.pngData() {
            addPendingClipboardImage(data: pngData, mimeType: "image/png", extension: "png")
            return
        }
        appendLocalCard("Clipboard does not contain a file or image.")
        #else
        appendLocalCard("Clipboard image paste is only available on macOS.")
        #endif
    }

    private func addPendingClipboardImage(data: Data, mimeType: String, extension pathExtension: String) {
        guard data.count <= SloppyTUIAttachmentLimits.maxBytes else {
            appendLocalCard("Clipboard image is too large (\(data.count) bytes).")
            return
        }
        let name = "clipboard-\(Self.clipboardTimestamp()).\(pathExtension)"
        pendingUploads.append(
            AgentAttachmentUpload(
                name: name,
                mimeType: mimeType,
                sizeBytes: data.count,
                contentBase64: data.base64EncodedString()
            )
        )
        appendLocalCard("Attached clipboard image: `\(name)`")
        refreshStaticChrome()
    }

    private static func clipboardTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }

    private func messageContentWithInlineAttachments(_ raw: String, uploads: [AgentAttachmentUpload]) async -> String {
        var parts = [raw]
        if let pendingContext {
            parts.append("\n[Attached context]\n\(pendingContext)")
        }
        if !uploads.isEmpty {
            let list = uploads.map { "- \($0.name) (\($0.mimeType), \($0.sizeBytes) bytes)" }.joined(separator: "\n")
            parts.append("\n[Attached files]\n\(list)")
        }

        let tokens = raw.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let fileTokens = tokens
            .filter { $0.hasPrefix("@") && $0.count > 1 }
            .map { String($0.dropFirst()) }
        for path in fileTokens.prefix(8) {
            do {
                let file = try await runtime.service.readProjectFile(projectID: project.id, path: path)
                parts.append("\n[Attached file: \(file.path)]\n```\n\(file.content)\n```")
            } catch {
                parts.append("\n[Attachment failed: \(path)] \(String(describing: error))")
            }
        }
        return parts.joined(separator: "\n")
    }
}

private enum SloppyTUIPickerKind {
    case model
    case agent
    case session
    case provider
    case providerCatalog
}

private struct SloppyTUIPickerItem {
    var value: String
    var label: String
    var description: String?
    var isCurrent: Bool
}

private struct SloppyTUIPicker {
    var kind: SloppyTUIPickerKind
    var title: String
    var items: [SloppyTUIPickerItem]
    var selectedIndex: Int
}

private enum SloppyTUITimelineBlock {
    case message(role: AgentMessageRole, text: String)
    case local(String)
    case error(String)
    case thinking(String)
    case attachment(name: String, mimeType: String, sizeBytes: Int)
    case toolCall(tool: String, reason: String?, argumentNames: [String])
    case toolResult(tool: String, ok: Bool, error: String?, durationMs: Int?)

    var plainText: String {
        switch self {
        case .message(_, let text), .local(let text), .error(let text):
            return text
        case .thinking(let text):
            return text
        case .attachment(let name, let mimeType, _):
            return "\(name) \(mimeType)"
        case .toolCall(let tool, let reason, let argumentNames):
            return ([tool] + argumentNames + [reason].compactMap { $0 }).joined(separator: " ")
        case .toolResult(let tool, _, let error, _):
            return ([tool] + [error].compactMap { $0 }).joined(separator: " ")
        }
    }
}

private extension AgentChatMode {
    var next: AgentChatMode {
        switch self {
        case .ask: return .build
        case .build: return .plan
        case .plan: return .debug
        case .debug: return .ask
        }
    }

    var title: String {
        switch self {
        case .ask: return "Ask"
        case .build: return "Build"
        case .plan: return "Plan"
        case .debug: return "Debug"
        }
    }
}

private enum SloppyTUITheme {
    private static let resetBackground = "\u{001B}[49m"
    private static let accent = AnsiStyling.rgb(82, 211, 194)
    private static let accentBright = AnsiStyling.rgb(103, 232, 249)
    private static let blue = AnsiStyling.rgb(96, 165, 250)
    private static let green = AnsiStyling.rgb(74, 222, 128)
    private static let yellow = AnsiStyling.rgb(250, 204, 21)
    private static let orange = AnsiStyling.rgb(251, 178, 123)
    private static let red = AnsiStyling.rgb(248, 113, 113)
    private static let muted = AnsiStyling.rgb(148, 163, 184)
    private static let foreground = AnsiStyling.rgb(226, 232, 240)
    private static let black = AnsiStyling.color(30)
    private static let panelBackground = AnsiStyling.Background.rgb(24, 24, 24)
    private static let userMessageBackground = AnsiStyling.Background.rgb(55, 55, 55)
    private static let toolBackground = AnsiStyling.Background.rgb(31, 41, 55)
    private static let thinkingBackground = AnsiStyling.Background.rgb(38, 38, 38)
    private static let attachmentBackground = AnsiStyling.Background.rgb(32, 45, 42)
    private static let waitingFrames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
    private static let thinkingWords = [
        "thinking",
        "processing",
        "looting",
        "brewing",
        "plotting",
        "untangling",
        "debugging",
        "polishing",
        "compiling",
    ]

    static let selectListTheme = SelectListTheme(
        selectedPrefix: { accentBright($0) },
        selectedText: { accentBright(AnsiStyling.bold($0)) },
        description: { muted($0) },
        scrollInfo: { muted($0) },
        noMatch: { muted($0) }
    )

    static let palette = ThemePalette(
        editor: EditorTheme(
            borderColor: { accent($0) },
            selectList: selectListTheme
        ),
        selectList: selectListTheme,
        markdown: MarkdownComponent.MarkdownTheme(
            heading: { accentBright($0) },
            link: { blue(AnsiStyling.underline($0)) },
            linkUrl: { muted($0) },
            code: { yellow($0) },
            codeBlock: { green($0) },
            codeBlockBorder: { muted($0) },
            quote: { muted(AnsiStyling.italic($0)) },
            quoteBorder: { accent($0) },
            hr: { muted($0) },
            listBullet: { accent($0) },
            bold: AnsiStyling.bold,
            italic: AnsiStyling.italic,
            strikethrough: AnsiStyling.strikethrough,
            underline: AnsiStyling.underline
        ),
        textBackground: .init(red: 12, green: 16, blue: 22),
        loader: Loader.LoaderTheme(
            spinner: { accentBright($0) },
            message: { muted($0) }
        ),
        truncatedBackground: .rgb(12, 16, 22)
    )

    static func header(project: String, agent: String, session: String) -> String {
        let title = accentBright(AnsiStyling.bold("Sloppy TUI"))
        return "\(title)  \(muted("project:")) \(foreground(project))  \(muted("agent:")) \(foreground(agent))  \(muted("session:")) \(foreground(session))"
    }

    static func status(_ text: String, isBusy: Bool) -> String {
        if isBusy {
            return yellow(text)
        }
        if text.contains("\u{001B}[") {
            return text
        }
        return muted(text)
    }

    static func sessionStatusLine(mode: AgentChatMode, model: String, context: String, attachments: String, sessionID: String) -> String {
        muted("mode: ") + modeTitle(mode) + muted("  model: \(model)\(context)\(attachments)  last: \(shortID(sessionID))  /sessions  /help")
    }

    static func welcomeScreen(
        width: Int,
        cwd: String,
        project: String,
        agent: String,
        model: String,
        mode: AgentChatMode,
        includeFooter: Bool = true
    ) -> [String] {
        let contentWidth = max(1, min(max(1, width - 4), 112))
        let left = max(0, (width - contentWidth) / 2)
        let indent = String(repeating: " ", count: left)
        var lines: [String] = []

        lines.append("")
        lines.append("")
        lines.append(contentsOf: logoLines(width: width))
        lines.append("")
        lines.append(indent + welcomePromptLine(width: contentWidth))
        lines.append(indent + welcomeMetaLine(width: contentWidth, project: project, agent: agent, model: model, mode: mode))
        lines.append(indent + welcomeShortcutsLine(width: contentWidth))
        lines.append("")
        lines.append(center(yellow("Tip") + muted("  Use ") + foreground("/model") + muted(" to switch models with arrow keys."), width: width))
        lines.append("")
        if includeFooter {
            lines.append(welcomeFooter(width: width, cwd: cwd))
        }
        lines.append("")
        return lines
    }

    static func composerMetaLine(width: Int, mode: AgentChatMode, model: String, agent: String, provider: String) -> String {
        let modelText = truncateEnd(compactModel(model), maxWidth: max(4, width / 3))
        let agentText = truncateEnd(agent, maxWidth: max(4, width / 5))
        let providerText = truncateEnd(provider, maxWidth: max(4, width / 5))
        let text = "  " + modeTitle(mode) + muted(" · ") + foreground(modelText) + muted("  ") + muted(agentText) + muted("  ") + muted(providerText)
        return applyPanelBackground(padded(text, width: width), width: width)
    }

    private static func modeTitle(_ mode: AgentChatMode) -> String {
        switch mode {
        case .ask:
            return green(mode.title)
        case .build:
            return blue(mode.title)
        case .plan:
            return accentBright(mode.title)
        case .debug:
            return yellow(mode.title)
        }
    }

    static func compactPickerDescription(_ model: String) -> String {
        compactModel(model)
    }

    static func sessionHeaderTitle(_ session: AgentSessionSummary) -> String {
        "\(session.title) (\(shortID(session.id)))"
    }

    static func sessionPickerDescription(_ session: AgentSessionSummary) -> String {
        let preview = session.lastMessagePreview?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ") ?? ""
        let detail = preview.isEmpty ? "\(session.messageCount) messages" : preview
        return "\(relativeTime(session.updatedAt)) · \(shortID(session.id)) · \(detail)"
    }

    static func waitingIndicator(frame: Int, word: String) -> String {
        let spinner = waitingFrames[frame % waitingFrames.count]
        return muted("\(spinner) ") + accentBright(word)
    }

    static func waitingWord(seed: String) -> String {
        let value = seed.unicodeScalars.reduce(0) { partial, scalar in
            partial &+ Int(scalar.value)
        }
        return thinkingWords[value % thinkingWords.count]
    }

    static func userMessageLines(_ text: String, width: Int) -> [String] {
        let contentWidth = max(1, width - 4)
        let rawLines = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .flatMap { line in
                AnsiWrapping.wrapText(String(line), width: contentWidth)
            }

        let lines = rawLines.isEmpty ? [""] : rawLines
        return lines.enumerated().map { index, line in
            let prefix = index == 0 ? "› " : "  "
            return applyBackground(
                " " + muted(prefix) + highlightedFileReferences(in: line),
                width: width,
                background: userMessageBackground
            )
        }
    }

    static func thinkingLines(_ text: String, width: Int) -> [String] {
        let contentWidth = max(1, width - 6)
        let rawLines = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .flatMap { line in
                AnsiWrapping.wrapText(String(line), width: contentWidth)
            }
        let lines = rawLines.isEmpty ? [""] : rawLines
        return lines.enumerated().map { index, line in
            let prefix = index == 0 ? "thought " : "        "
            return applyBackground(
                " " + muted(prefix) + foreground(line),
                width: width,
                background: thinkingBackground
            )
        }
    }

    static func toolCallLine(tool: String, reason: String?, argumentNames: [String], width: Int) -> String {
        let args = argumentNames.isEmpty ? "" : muted(" · \(argumentNames.joined(separator: ", "))")
        let suffix = reason?.trimmingCharacters(in: .whitespacesAndNewlines)
        let reasonText = suffix?.isEmpty == false ? muted(" · \(suffix!)") : ""
        let line = " " + blue("tool") + foreground(" \(tool)") + args + reasonText
        return applyBackground(padded(line, width: width), width: width, background: toolBackground)
    }

    static func toolResultLine(tool: String, ok: Bool, error: String?, durationMs: Int?, width: Int) -> String {
        let status = ok ? green("done") : red("failed")
        let duration = durationMs.map { muted(" · \($0)ms") } ?? ""
        let errorText = error?.trimmingCharacters(in: .whitespacesAndNewlines)
        let suffix = errorText?.isEmpty == false ? muted(" · \(errorText!)") : ""
        let line = " " + status + foreground(" \(tool)") + duration + suffix
        return applyBackground(padded(line, width: width), width: width, background: toolBackground)
    }

    static func attachmentLine(name: String, mimeType: String, sizeBytes: Int, width: Int) -> String {
        let size = formattedBytes(sizeBytes)
        let line = " " + green("attached") + foreground(" ") + yellow(name) + muted("  \(mimeType), \(size)")
        return applyBackground(padded(line, width: width), width: width, background: attachmentBackground)
    }

    static func commandPaletteLines(
        width: Int,
        commands: [SloppyTUISlashCommand],
        selectedIndex: Int,
        maxVisible: Int
    ) -> [String] {
        let paletteWidth = max(1, min(max(1, width - 4), 96))
        let left = max(0, (width - paletteWidth) / 2)
        let indent = String(repeating: " ", count: left)
        let visibleCount = max(1, min(maxVisible, commands.count))
        let start = max(0, min(selectedIndex - visibleCount / 2, commands.count - visibleCount))
        let end = min(commands.count, start + visibleCount)
        var lines: [String] = []

        for index in start..<end {
            let command = commands[index]
            let name = "/" + command.name
            let description = command.description ?? ""
            let raw: String
            if paletteWidth < 32 {
                raw = "  " + truncateEnd(name, maxWidth: max(1, paletteWidth - 2))
            } else {
                let nameWidth = max(10, min(22, paletteWidth / 3))
                let descWidth = max(1, paletteWidth - nameWidth - 4)
                raw = "  " + truncateEnd(name, maxWidth: nameWidth).padding(toLength: nameWidth, withPad: " ", startingAt: 0) + "  " + truncateEnd(description, maxWidth: descWidth)
            }
            let line = padded(raw, width: paletteWidth)
            if index == selectedIndex {
                lines.append(indent + selectedLine(line))
            } else {
                lines.append(indent + applyPanelBackground(foreground(line), width: paletteWidth))
            }
        }
        if commands.count > visibleCount {
            let info = "  " + muted("\(selectedIndex + 1)/\(commands.count)")
            lines.append(indent + applyPanelBackground(padded(info, width: paletteWidth), width: paletteWidth))
        }
        return lines
    }

    static func pickerLines(width: Int, picker: SloppyTUIPicker, maxVisible: Int) -> [String] {
        let paletteWidth = max(1, min(max(1, width - 4), 96))
        let left = max(0, (width - paletteWidth) / 2)
        let indent = String(repeating: " ", count: left)
        let visibleCount = max(1, min(maxVisible, picker.items.count))
        let start = max(0, min(picker.selectedIndex - visibleCount / 2, picker.items.count - visibleCount))
        let end = min(picker.items.count, start + visibleCount)
        var lines = [
            indent + padded("  " + foreground(AnsiStyling.bold(picker.title)) + "  " + muted("Enter apply · Esc cancel"), width: paletteWidth),
        ]

        for index in start..<end {
            let item = picker.items[index]
            let raw: String
            if paletteWidth < 32 {
                let marker = item.isCurrent ? "✓ " : "  "
                raw = "  " + marker + truncateEnd(item.label, maxWidth: max(1, paletteWidth - 4))
            } else {
                let nameWidth = max(14, min(42, paletteWidth / 2))
                let descWidth = max(1, paletteWidth - nameWidth - 6)
                let marker = item.isCurrent ? "✓ " : "  "
                let label = truncateEnd(item.label, maxWidth: nameWidth).padding(toLength: nameWidth, withPad: " ", startingAt: 0)
                raw = "  " + marker + label + "  " + truncateEnd(item.description ?? "", maxWidth: descWidth)
            }
            let line = padded(raw, width: paletteWidth)
            if index == picker.selectedIndex {
                lines.append(indent + selectedLine(line))
            } else {
                lines.append(indent + foreground(line))
            }
        }
        if picker.items.count > visibleCount {
            let info = "  " + muted("\(picker.selectedIndex + 1)/\(picker.items.count)")
            lines.append(indent + padded(info, width: paletteWidth))
        }
        return lines
    }

    static func overlayModal(
        base: [String],
        width: Int,
        title: String,
        subtitle: String,
        content: [String],
        maxWidth: Int
    ) -> [String] {
        let dimmed = base.map { AnsiStyling.dim($0) }
        let modalWidth = max(1, min(maxWidth, max(1, width - 8)))
        let left = max(0, (width - modalWidth) / 2)
        let top = max(1, (dimmed.count - content.count - 4) / 2)
        let indent = String(repeating: " ", count: left)
        var modal: [String] = []
        let titleText = truncateEnd(title, maxWidth: max(1, modalWidth / 2))
        let subtitleText = modalWidth > 36 ? truncateEnd(subtitle, maxWidth: max(1, modalWidth / 2)) : ""
        let gap = max(1, modalWidth - 4 - VisibleWidth.measure(titleText) - VisibleWidth.measure(subtitleText))
        modal.append(applyPanelBackground(padded("  " + foreground(AnsiStyling.bold(titleText)) + String(repeating: " ", count: gap) + muted(subtitleText) + "  ", width: modalWidth), width: modalWidth))
        modal.append(applyPanelBackground(padded("", width: modalWidth), width: modalWidth))
        for line in content {
            let inner = padded("  " + line, width: modalWidth)
            modal.append(applyPanelBackground(inner, width: modalWidth))
        }
        modal.append(applyPanelBackground(padded("", width: modalWidth), width: modalWidth))

        var result = dimmed
        for (offset, line) in modal.enumerated() {
            let index = top + offset
            guard result.indices.contains(index) else { continue }
            result[index] = overlay(line: result[index], overlay: indent + line, width: width)
        }
        return result
    }

    static func appFooter(width: Int, cwd: String) -> String {
        welcomeFooter(width: width, cwd: cwd)
    }

    static func normalize(lines: [String], width: Int, height: Int) -> [String] {
        let normalized = lines.prefix(height).map { line in
            let visible = VisibleWidth.measure(line)
            guard visible < width else { return line }
            return line + String(repeating: " ", count: width - visible)
        }
        if normalized.count >= height {
            return Array(normalized)
        }
        return normalized + Array(repeating: String(repeating: " ", count: width), count: height - normalized.count)
    }

    static func modelPickerPrompt(current: String) -> String {
        " " + accentBright(AnsiStyling.bold("Select model")) + "  " + muted("current:") + " " + foreground(current)
    }

    static func roleTitle(_ title: String, role: AgentMessageRole) -> String {
        switch role {
        case .assistant:
            return accentBright(title)
        case .user:
            return blue(title)
        case .system:
            return muted(title)
        }
    }

    static func runStatus(_ label: String) -> String {
        let normalized = label.lowercased()
        if normalized.contains("fail") || normalized.contains("error") {
            return red("_\(label)_")
        }
        if normalized.contains("complete") || normalized.contains("done") {
            return green("_\(label)_")
        }
        return yellow("_\(label)_")
    }

    static func isModelProviderError(_ text: String) -> Bool {
        text.localizedCaseInsensitiveContains("Model provider error")
            || text.localizedCaseInsensitiveContains("No models loaded")
    }

    static func errorBlock(_ text: String) -> String {
        "### \(red("Error"))\n\(text)"
    }

    private static func logoLines(width: Int) -> [String] {
        if width < 64 {
            return [center(accentBright(AnsiStyling.bold("sloppy")), width: width)]
        }
        let logo = [
            "███████╗██╗      ██████╗ ██████╗ ██████╗ ██╗   ██╗",
            "██╔════╝██║     ██╔═══██╗██╔══██╗██╔══██╗╚██╗ ██╔╝",
            "███████╗██║     ██║   ██║██████╔╝██████╔╝ ╚████╔╝ ",
            "╚════██║██║     ██║   ██║██╔═══╝ ██╔═══╝   ╚██╔╝  ",
            "███████║███████╗╚██████╔╝██║     ██║        ██║   ",
            "╚══════╝╚══════╝ ╚═════╝ ╚═╝     ╚═╝        ╚═╝   ",
        ]
        return logo.map { center(accentBright($0), width: width) }
    }

    private static func welcomePromptLine(width: Int) -> String {
        let text: String
        if width < 48 {
            text = muted("Ask anything...")
        } else {
            text = muted("Ask anything...  ") + foreground("\"What is the tech stack of this project?\"")
        }
        return accent("▌") + " " + padded(text, width: max(1, width - 2))
    }

    private static func welcomeMetaLine(width: Int, project: String, agent: String, model: String, mode: AgentChatMode) -> String {
        let modelText = truncateEnd(compactModel(model), maxWidth: max(8, width / 3))
        let agentText = truncateEnd(agent, maxWidth: max(6, width / 5))
        let projectText = truncateEnd(project, maxWidth: max(6, width / 5))
        let text = modeTitle(mode) + muted(" · ") + foreground(modelText) + muted("  ") + foreground(agentText) + muted("  ") + muted(projectText)
        return accent("▌") + " " + padded(text, width: max(1, width - 2))
    }

    private static func welcomeShortcutsLine(width: Int) -> String {
        let text: String
        if width < 48 {
            text = foreground("/help") + muted(" commands")
        } else {
            text = foreground("tab") + muted(" mode") + muted("     ") + foreground("/model") + muted(" models") + muted("     ") + foreground("/help") + muted(" commands")
        }
        return "  " + padded(text, width: max(1, width - 2))
    }

    private static func welcomeFooter(width: Int, cwd: String) -> String {
        let pathWidth = max(1, width - 24)
        let path = truncateStart(shortPath(cwd), maxWidth: pathWidth)
        let left = muted(path) + muted("  ") + green("○") + muted(" ") + foreground("1 MCP") + muted("  /status")
        let right = muted(SloppyVersion.current)
        let leftWidth = VisibleWidth.measure(left)
        let rightWidth = VisibleWidth.measure(right)
        guard leftWidth + rightWidth + 1 <= width else {
            return leftWidth <= width ? left : muted(truncateStart(path, maxWidth: width))
        }
        let gap = width - leftWidth - rightWidth
        return left + String(repeating: " ", count: gap) + right
    }

    private static func applyPanelBackground(_ line: String, width: Int) -> String {
        applyBackground(line, width: width, background: panelBackground)
    }

    private static func applyBackground(_ line: String, width: Int, background: AnsiStyling.Background) -> String {
        AnsiWrapping.applyBackgroundToLine(line, width: width, background: background) + resetBackground
    }

    private static func selectedLine(_ line: String) -> String {
        "\u{001B}[48;2;251;178;123m\u{001B}[38;2;0;0;0m\(line)\u{001B}[39m\u{001B}[49m"
    }

    private static func overlay(line: String, overlay: String, width: Int) -> String {
        let overlayWidth = VisibleWidth.measure(overlay)
        guard overlayWidth < width else { return overlay }
        let suffix = max(0, width - overlayWidth)
        return overlay + String(repeating: " ", count: suffix)
    }

    private static func center(_ text: String, width: Int) -> String {
        let visible = VisibleWidth.measure(text)
        guard visible < width else { return text }
        return String(repeating: " ", count: (width - visible) / 2) + text
    }

    private static func padded(_ text: String, width: Int) -> String {
        let visible = VisibleWidth.measure(text)
        if visible >= width { return text }
        return text + String(repeating: " ", count: width - visible)
    }

    private static func compactModel(_ model: String) -> String {
        let raw = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return "default" }
        if let colon = raw.firstIndex(of: ":") {
            return String(raw[raw.index(after: colon)...])
        }
        return raw
    }

    private static func shortPath(_ path: String) -> String {
        let expanded = (path as NSString).abbreviatingWithTildeInPath
        let parts = expanded.split(separator: "/").map(String.init)
        guard parts.count > 2 else { return expanded }
        return "…/" + parts.suffix(2).joined(separator: "/")
    }

    private static func truncateEnd(_ text: String, maxWidth: Int) -> String {
        guard maxWidth > 1, VisibleWidth.measure(text) > maxWidth else { return text }
        let limit = max(1, maxWidth - 1)
        return String(text.prefix(limit)) + "…"
    }

    private static func truncateStart(_ text: String, maxWidth: Int) -> String {
        guard maxWidth > 1, VisibleWidth.measure(text) > maxWidth else { return text }
        let limit = max(1, maxWidth - 1)
        return "…" + String(text.suffix(limit))
    }

    private static func highlightedFileReferences(in line: String) -> String {
        let pattern = #"@[A-Za-z0-9._/\-~]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return foreground(line)
        }
        let nsRange = NSRange(line.startIndex..<line.endIndex, in: line)
        let matches = regex.matches(in: line, range: nsRange)
        guard !matches.isEmpty else {
            return foreground(line)
        }

        var result = ""
        var cursor = line.startIndex
        for match in matches {
            guard let range = Range(match.range, in: line) else { continue }
            if range.lowerBound > cursor {
                result += foreground(String(line[cursor..<range.lowerBound]))
            }
            result += yellow(String(line[range]))
            cursor = range.upperBound
        }
        if cursor < line.endIndex {
            result += foreground(String(line[cursor..<line.endIndex]))
        }
        return result
    }

    private static func formattedBytes(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        let units = ["KB", "MB", "GB"]
        var value = Double(bytes) / 1024.0
        var unit = units[0]
        for nextUnit in units.dropFirst() where value >= 1024.0 {
            value /= 1024.0
            unit = nextUnit
        }
        return String(format: "%.1f %@", value, unit)
    }

    static func shortID(_ id: String) -> String {
        guard id.count > 12 else { return id }
        return String(id.prefix(8))
    }

    private static func relativeTime(_ date: Date) -> String {
        let seconds = max(0, Int(Date().timeIntervalSince(date)))
        if seconds < 60 { return "just now" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        let days = hours / 24
        if days < 7 { return "\(days)d ago" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}

struct SloppyTUISlashCommand: SlashCommand {
    let name: String
    let description: String?
    var requiresArgument: Bool {
        switch name {
        case "context", "anthropic-callback":
            return true
        default:
            return false
        }
    }

    init(_ name: String, _ description: String?) {
        self.name = name
        self.description = description
    }

    func argumentCompletions(prefix: String) -> [AutocompleteItem] {
        []
    }
}

private final class SloppyTUIAutocompleteProvider: AutocompleteProvider {
    private let base: CombinedAutocompleteProvider

    init(basePath: String) {
        self.base = CombinedAutocompleteProvider(basePath: basePath)
    }

    func getSuggestions(lines: [String], cursorLine: Int, cursorCol: Int) -> AutocompleteSuggestion? {
        base.getSuggestions(lines: lines, cursorLine: cursorLine, cursorCol: cursorCol)
    }

    func applyCompletion(
        lines: [String],
        cursorLine: Int,
        cursorCol: Int,
        item: AutocompleteItem,
        prefix: String
    ) -> (lines: [String], cursorLine: Int, cursorCol: Int) {
        guard prefix.hasPrefix("@") else {
            return base.applyCompletion(
                lines: lines,
                cursorLine: cursorLine,
                cursorCol: cursorCol,
                item: item,
                prefix: prefix
            )
        }
        guard lines.indices.contains(cursorLine) else {
            return (lines, cursorLine, cursorCol)
        }

        var mutableLines = lines
        var currentLine = lines[cursorLine]
        let safePrefixCount = min(prefix.count, cursorCol)
        let start = currentLine.index(currentLine.startIndex, offsetBy: cursorCol - safePrefixCount)
        let end = currentLine.index(start, offsetBy: safePrefixCount)
        let replacement = item.value.hasPrefix("@") ? item.value + " " : "@" + item.value + " "
        currentLine.replaceSubrange(start..<end, with: replacement)
        mutableLines[cursorLine] = currentLine
        let newCursor = cursorCol - safePrefixCount + replacement.count
        return (mutableLines, cursorLine, max(0, newCursor))
    }

    func forceFileSuggestions(lines: [String], cursorLine: Int, cursorCol: Int) -> AutocompleteSuggestion? {
        nil
    }

    func shouldTriggerFileCompletion(lines: [String], cursorLine: Int, cursorCol: Int) -> Bool {
        guard lines.indices.contains(cursorLine) else {
            return false
        }
        let currentLine = lines[cursorLine]
        let prefixIndex = currentLine.index(currentLine.startIndex, offsetBy: min(cursorCol, currentLine.count))
        let textBeforeCursor = String(currentLine[..<prefixIndex])
        return textBeforeCursor.trimmingCharacters(in: .whitespaces).hasPrefix("/")
    }
}

struct SloppyTUIProviderDefinition {
    static let addNewProviderValue = "__add_new_provider__"
    static let catalog = [
        SloppyTUIProviderDefinition("openai-api"),
        SloppyTUIProviderDefinition("openai-oauth"),
        SloppyTUIProviderDefinition("openrouter"),
        SloppyTUIProviderDefinition("gemini"),
        SloppyTUIProviderDefinition("anthropic"),
        SloppyTUIProviderDefinition("anthropic-oauth"),
        SloppyTUIProviderDefinition("ollama"),
    ]

    var id: String
    var title: String
    var apiURL: String
    var model: String
    var requiresAPIKey: Bool
    var setupDescription: String

    init(_ raw: String) {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "openrouter":
            id = "openrouter"
            title = "openrouter"
            apiURL = "https://openrouter.ai/api/v1"
            model = "openai/gpt-4o-mini"
            requiresAPIKey = true
            setupDescription = "OpenRouter API key"
        case "gemini":
            id = "gemini"
            title = "gemini"
            apiURL = "https://generativelanguage.googleapis.com"
            model = "gemini-2.5-flash"
            requiresAPIKey = true
            setupDescription = "Google AI Studio API key"
        case "anthropic":
            id = "anthropic"
            title = "anthropic"
            apiURL = "https://api.anthropic.com"
            model = "claude-sonnet-4-20250514"
            requiresAPIKey = true
            setupDescription = "Anthropic API key"
        case "anthropic-oauth":
            id = "anthropic-oauth"
            title = "anthropic-oauth"
            apiURL = "https://api.anthropic.com"
            model = "claude-sonnet-4-20250514"
            requiresAPIKey = false
            setupDescription = "Browser OAuth flow"
        case "ollama", "ollama-local":
            id = "ollama"
            title = "ollama-local"
            apiURL = "http://127.0.0.1:11434"
            model = "qwen3"
            requiresAPIKey = false
            setupDescription = "Local Ollama server"
        case "openai-oauth":
            id = "openai-oauth"
            title = "openai-oauth"
            apiURL = "https://chatgpt.com/backend-api"
            model = "gpt-5.3-codex"
            requiresAPIKey = false
            setupDescription = "Codex device auth"
        default:
            id = "openai-api"
            title = "openai-api"
            apiURL = "https://api.openai.com/v1"
            model = "gpt-5.4-mini"
            requiresAPIKey = true
            setupDescription = "OpenAI API key"
        }
    }

    func runtimeModelID(_ modelID: String) -> String {
        if id == "openrouter" { return "openrouter:\(modelID)" }
        if id == "gemini" { return "gemini:\(modelID)" }
        if id == "anthropic" || id == "anthropic-oauth" { return "anthropic:\(modelID)" }
        if id == "ollama" { return "ollama:\(modelID)" }
        return "openai:\(modelID)"
    }
}

#if canImport(AppKit)
private extension NSImage {
    func pngData() -> Data? {
        guard let tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffRepresentation) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }
}
#endif

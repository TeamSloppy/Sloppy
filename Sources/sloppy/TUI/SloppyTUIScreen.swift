import Foundation
#if canImport(AppKit)
import AppKit
#endif
import Protocols
import TauTUI

private enum SloppyTUIAttachmentLimits {
    static let maxBytes = 25 * 1024 * 1024
}

private extension Array where Element == String {
    func trimmingEmptyEdges() -> [String] {
        var startIndex = self.startIndex
        var endIndex = self.endIndex

        while startIndex < endIndex, self[startIndex].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            startIndex = index(after: startIndex)
        }
        while endIndex > startIndex {
            let previousIndex = index(before: endIndex)
            guard self[previousIndex].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                break
            }
            endIndex = previousIndex
        }

        return Array(self[startIndex..<endIndex])
    }
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

    private static let firstStartBootstrapCard = """
    ## First start bootstrap
    Configure a provider with `/provider <id> <key> [model]`, `/openai-device`, or `/anthropic-oauth`.
    Type the launch prompt when ready; Sloppy will create the onboarding session turn and mark onboarding complete.
    """

    private let runtime: SloppyTUIRuntime
    private var project: ProjectRecord
    private var agent: AgentSummary
    private var session: AgentSessionSummary
    private let stateStore: SloppyTUIStateStore
    private var state: SloppyTUIState
    private let initialAction: SloppyTUIInitialAction
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
    private var exitAfterModelSelection = false

    init(
        runtime: SloppyTUIRuntime,
        project: ProjectRecord,
        agent: AgentSummary,
        session: AgentSessionSummary,
        stateStore: SloppyTUIStateStore,
        state: SloppyTUIState,
        initialAction: SloppyTUIInitialAction = .none,
        tui: TUI,
        terminal: Terminal
    ) {
        self.runtime = runtime
        self.project = project
        self.agent = agent
        self.session = session
        self.stateStore = stateStore
        self.state = state
        self.initialAction = initialAction
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
        Task { @MainActor in
            await refreshSelectedModel()
            if case .modelPicker(let exitAfterSelection) = initialAction {
                await showModelPicker(exitAfterSelection: exitAfterSelection)
            }
        }
        streamSession()
        streamChanges()
        if !runtime.config.onboarding.completed {
            appendLocalCard(Self.firstStartBootstrapCard)
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
            return centerWelcome(raw, height: height)
        } else {
            raw = header.render(width: width) + renderTimelineBlocks(width: width) + status.render(width: width)
        }

        if raw.count >= height {
            return Array(raw.suffix(height))
        }
        return raw + Array(repeating: "", count: height - raw.count)
    }

    private func centerWelcome(_ lines: [String], height: Int) -> [String] {
        let content = lines.trimmingEmptyEdges()
        guard content.count < height else {
            return Array(content.suffix(height))
        }

        let topPadding = (height - content.count) / 2
        let bottomPadding = height - content.count - topPadding
        return Array(repeating: "", count: topPadding)
            + content
            + Array(repeating: "", count: bottomPadding)
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
            if exitAfterModelSelection && picker.kind == .model {
                onExit?()
                return true
            }
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
        dismissFirstStartBootstrapCard()
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

    private func showModelPicker(exitAfterSelection: Bool = false) async {
        exitAfterModelSelection = exitAfterSelection
        refreshStaticChrome(statusLine: "loading models from providers...")
        do {
            let config = try await runtime.service.getAgentConfig(agentID: agent.id)
            let selected = config.selectedModel ?? selectedModel
            selectedModel = selected
            let models = orderedModelsForPicker(
                await selectableModels(base: config.availableModels, selected: selected),
                selected: selected
            )
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
                        description: SloppyTUITheme.modelPickerDescription(model),
                        isCurrent: model.id == selected
                    )
                },
                selectedIndex: 0
            )
            refreshStaticChrome(statusLine: "select model with arrows, Enter to apply, Esc to cancel")
        } catch {
            exitAfterModelSelection = false
            appendLocalCard("Could not load models: \(String(describing: error))")
        }
    }

    private func applyPickerItem(_ item: SloppyTUIPickerItem, kind: SloppyTUIPickerKind) async {
        switch kind {
        case .model:
            await applyModel(item.value)
            if exitAfterModelSelection {
                onExit?()
            }
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

    private func selectableModels(base: [ProviderModelOption], selected: String) async -> [ProviderModelOption] {
        var seen: Set<String> = []
        var models: [ProviderModelOption] = []

        func add(_ option: ProviderModelOption) {
            let id = option.id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty, seen.insert(id).inserted else {
                return
            }
            models.append(ProviderModelOption(
                id: id,
                title: option.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? id : option.title,
                contextWindow: option.contextWindow,
                capabilities: option.capabilities
            ))
        }

        for option in base {
            add(option)
        }

        let config = await runtime.service.getConfig()
        for entry in config.models where !entry.disabled {
            let definition = providerDefinition(for: entry)
            let response = await runtime.service.probeProvider(
                request: ProviderProbeRequest(
                    providerId: definition.probeID,
                    apiKey: entry.apiKey,
                    apiUrl: entry.apiUrl
                )
            )
            guard response.ok else {
                continue
            }
            for option in response.models {
                let rawId = option.id.trimmingCharacters(in: .whitespacesAndNewlines)
                let id = runtimeModelID(rawId, provider: definition)
                add(ProviderModelOption(
                    id: id,
                    title: option.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? rawId : option.title,
                    contextWindow: option.contextWindow,
                    capabilities: option.capabilities
                ))
            }
        }

        if !selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !seen.contains(selected) {
            add(CoreService.providerModelOption(for: selected))
        }

        return models
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
            dismissFirstStartBootstrapCard()
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
        return runtimeModelID(rawModel, provider: providerDefinition(for: model))
    }

    private func runtimeModelID(_ rawModel: String, provider: SloppyTUIProviderDefinition) -> String {
        let rawModel = rawModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if rawModel.hasPrefix("openai:")
            || rawModel.hasPrefix("openrouter:")
            || rawModel.hasPrefix("ollama:")
            || rawModel.hasPrefix("gemini:")
            || rawModel.hasPrefix("anthropic:") {
            return rawModel
        }
        return provider.runtimeModelID(rawModel)
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
        let rawModel = model.model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if rawModel.hasPrefix("openrouter:") {
            return SloppyTUIProviderDefinition("openrouter")
        }
        if rawModel.hasPrefix("ollama:") {
            return SloppyTUIProviderDefinition("ollama")
        }
        if rawModel.hasPrefix("gemini:") {
            return SloppyTUIProviderDefinition("gemini")
        }
        if rawModel.hasPrefix("anthropic:") {
            return SloppyTUIProviderDefinition("anthropic")
        }
        if rawModel.hasPrefix("openai:") {
            return title.contains("oauth") ? SloppyTUIProviderDefinition("openai-oauth") : SloppyTUIProviderDefinition("openai-api")
        }
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
            dismissFirstStartBootstrapCard()
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

    private func dismissFirstStartBootstrapCard() {
        localCards.removeAll { block in
            if case .local(let text) = block {
                return text == Self.firstStartBootstrapCard
            }
            return false
        }
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

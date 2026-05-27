import Foundation
import ChannelPluginSupport
import Protocols
import TauTUI
import Testing
@testable import sloppy

@Test
func slashCommandRouterIgnoresAbsolutePaths() {
    let commandNames: Set<String> = ["help", "status"]
    let path = "/Users/vlad-prusakov/Developer/Sloppy/Sources/sloppy/TUI/SloppyTUICommands.swift"

    #expect(SloppyTUISlashCommandRouter.commandName(in: path) == "users/vlad-prusakov/developer/sloppy/sources/sloppy/tui/sloppytuicommands.swift")
    #expect(!SloppyTUISlashCommandRouter.shouldHandle(path, commandNames: commandNames, skillCommandNames: []))
}

@Test
func slashCommandRouterHandlesKnownCommandsAndAliases() {
    let commandNames: Set<String> = ["help", "workspace", "keybindings", "shortcuts", "add-dir", "restore", "up", "undo", "redo", "themes", "plan-web", "plans", "open-plan"]

    #expect(SloppyTUISlashCommandRouter.shouldHandle("/help", commandNames: commandNames, skillCommandNames: []))
    #expect(SloppyTUISlashCommandRouter.shouldHandle("/workspace", commandNames: commandNames, skillCommandNames: []))
    #expect(SloppyTUISlashCommandRouter.shouldHandle("/keybindings", commandNames: commandNames, skillCommandNames: []))
    #expect(SloppyTUISlashCommandRouter.shouldHandle("/shortcuts", commandNames: commandNames, skillCommandNames: []))
    #expect(SloppyTUISlashCommandRouter.shouldHandle("/add-dir /tmp/demo", commandNames: commandNames, skillCommandNames: []))
    #expect(SloppyTUISlashCommandRouter.shouldHandle("/restore", commandNames: commandNames, skillCommandNames: []))
    #expect(SloppyTUISlashCommandRouter.shouldHandle("/up", commandNames: commandNames, skillCommandNames: []))
    #expect(SloppyTUISlashCommandRouter.shouldHandle("/undo", commandNames: commandNames, skillCommandNames: []))
    #expect(SloppyTUISlashCommandRouter.shouldHandle("/redo", commandNames: commandNames, skillCommandNames: []))
    #expect(SloppyTUISlashCommandRouter.shouldHandle("/themes", commandNames: commandNames, skillCommandNames: []))
    #expect(SloppyTUISlashCommandRouter.shouldHandle("/plan-web", commandNames: commandNames, skillCommandNames: []))
    #expect(SloppyTUISlashCommandRouter.shouldHandle("/plans latest-plan", commandNames: commandNames, skillCommandNames: []))
    #expect(SloppyTUISlashCommandRouter.shouldHandle("/open-plan latest-plan", commandNames: commandNames, skillCommandNames: []))
}

@Test
func workspaceAccessRequiresDirectoryForAbsolutePathsOutsideRoots() throws {
    let tmp = FileManager.default.temporaryDirectory
    let project = tmp.appendingPathComponent("sloppy-project-\(UUID().uuidString)", isDirectory: true)
    let outside = tmp.appendingPathComponent("sloppy-outside-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
    defer {
        try? FileManager.default.removeItem(at: project)
        try? FileManager.default.removeItem(at: outside)
    }
    let file = outside.appendingPathComponent("note.txt")
    try Data("hello".utf8).write(to: file)

    #expect(SloppyTUIWorkspaceAccess.requiredDirectoryForAbsolutePath(
        file.path,
        projectRootPath: project.path,
        sessionDirectories: []
    ) == outside.resolvingSymlinksInPath().path)

    #expect(SloppyTUIWorkspaceAccess.requiredDirectoryForAbsolutePath(
        file.path,
        projectRootPath: project.path,
        sessionDirectories: [outside.path]
    ) == nil)
}

@Test
func slashCommandRouterHandlesSkillCommands() {
    let skillCommandNames: Set<String> = ["ux_pro_max"]

    #expect(SloppyTUISlashCommandRouter.shouldHandle("/ux_pro_max make it nicer", commandNames: [], skillCommandNames: skillCommandNames))
}

@Test
func skillInvocationRouterHandlesAtCommands() {
    let commands = [
        SloppyTUISlashCommand(
            "ux_pro_max",
            "UX Pro Max [acme/ux-pro-max]",
            invocationPrefix: "@",
            skillId: "acme/ux-pro-max"
        ),
    ]

    #expect(SloppyTUISkillInvocationRouter.commandName(in: "@ux_pro_max make it nicer") == "ux_pro_max")
    #expect(SloppyTUISkillInvocationRouter.requestText(in: "@ux_pro_max make it nicer") == "make it nicer")

    let message = SloppyTUISkillInvocationRouter.invocationMessage(
        raw: "@ux_pro_max make it nicer",
        skillCommands: commands
    )
    #expect(message?.contains("Use installed skill `acme/ux-pro-max`") == true)
    #expect(message?.contains("make it nicer") == true)
    #expect(SloppyTUISkillInvocationRouter.invocationMessage(raw: "@missing test", skillCommands: commands) == nil)
}

@Test
func skillSlashCommandNamingUsesRepoTokenByDefault() {
    let tokens = SkillSlashCommandNaming.resolvedSlashTokens(forSkillIds: ["owner/ui-pro-max"])

    #expect(tokens["owner/ui-pro-max"] == "ui_pro_max")
}

@Test
func planArtifactLookupResolvesLatestAndNamedArtifacts() {
    let older = PlanArtifactRecord(
        projectId: "project",
        projectName: "Project",
        agentId: "agent",
        sessionId: "session",
        messageEventId: "message-1",
        planName: "older-plan",
        createdAt: Date(timeIntervalSince1970: 10),
        storageKind: "workspace",
        markdownPath: "/tmp/older-plan/older-plan.md",
        webUrl: "/v1/projects/project/plans/older-plan/web"
    )
    let newer = PlanArtifactRecord(
        projectId: "project",
        projectName: "Project",
        agentId: "agent",
        sessionId: "session",
        messageEventId: "message-2",
        planName: "newer-plan",
        createdAt: Date(timeIntervalSince1970: 20),
        storageKind: "workspace",
        markdownPath: "/tmp/newer-plan/newer-plan.md",
        webUrl: "/v1/projects/project/plans/newer-plan/web"
    )
    let events = [
        AgentSessionEvent(agentId: "agent", sessionId: "session", type: .planArtifact, planArtifact: .init(artifact: older)),
        AgentSessionEvent(agentId: "agent", sessionId: "session", type: .planArtifact, planArtifact: .init(artifact: newer)),
    ]

    #expect(SloppyTUIPlanArtifactLookup.latest(in: events)?.planName == "newer-plan")
    #expect(SloppyTUIPlanArtifactLookup.resolve(nil, in: events)?.planName == "newer-plan")
    #expect(SloppyTUIPlanArtifactLookup.resolve("older-plan", in: events)?.planName == "older-plan")
    #expect(SloppyTUIPlanArtifactLookup.resolve("missing", in: events) == nil)
}

@Test
func skillSlashCommandNamingUsesOwnerForBuiltinConflict() {
    let tokens = SkillSlashCommandNaming.resolvedSlashTokens(
        forSkillIds: ["openai/help"],
        reservedTokens: ["help"]
    )

    #expect(tokens["openai/help"] == "openai_help")
}

@Test
func skillSlashCommandNamingDisambiguatesDuplicateReposDeterministically() {
    let first = SkillSlashCommandNaming.resolvedSlashTokens(forSkillIds: [
        "openai/ui-kit",
        "acme/ui-kit",
    ])
    let second = SkillSlashCommandNaming.resolvedSlashTokens(forSkillIds: [
        "openai/ui-kit",
        "acme/ui-kit",
    ])

    #expect(first["openai/ui-kit"] == "openai_ui_kit")
    #expect(first["acme/ui-kit"] == "acme_ui_kit")
    #expect(first == second)
}

@Test
func globalShortcutMatcherRecognizesSafeHotkeys() {
    #expect(SloppyTUIGlobalShortcutAction.match(input: .key(.character("p"), modifiers: [.option])) == .modelPicker)
    #expect(SloppyTUIGlobalShortcutAction.match(input: .key(.character("P"), modifiers: [.option])) == .modelPicker)
    #expect(SloppyTUIGlobalShortcutAction.match(input: .key(.character("t"), modifiers: [.control])) == .projectTasks)
    #expect(SloppyTUIGlobalShortcutAction.match(input: .key(.character("e"), modifiers: [.option])) == .codeEditor)
    #expect(SloppyTUIGlobalShortcutAction.match(input: .key(.character("u"), modifiers: [.option])) == .undo)
    #expect(SloppyTUIGlobalShortcutAction.match(input: .key(.character("r"), modifiers: [.option])) == .redo)
}

@Test
func globalShortcutMatcherLeavesExistingBindingsAlone() {
    #expect(SloppyTUIGlobalShortcutAction.match(input: .key(.character("g"), modifiers: [.control])) == nil)
    #expect(SloppyTUIGlobalShortcutAction.match(input: .key(.character("o"), modifiers: [.control])) == nil)
    #expect(SloppyTUIGlobalShortcutAction.match(input: .key(.tab)) == nil)
    #expect(SloppyTUIGlobalShortcutAction.match(input: .key(.character("p"), modifiers: [.control])) == nil)
    #expect(SloppyTUIGlobalShortcutAction.match(input: .key(.character("p"), modifiers: [.option, .control])) == nil)
}

@Test
func shellModeToggleRequiresPlainBangOnEmptyEditor() {
    #expect(SloppyTUIShellModeToggle.shouldToggle(input: .key(.character("!")), editorText: ""))
    #expect(!SloppyTUIShellModeToggle.shouldToggle(input: .key(.character("!")), editorText: "echo hi"))
    #expect(!SloppyTUIShellModeToggle.shouldToggle(input: .key(.character("!"), modifiers: [.option]), editorText: ""))
    #expect(!SloppyTUIShellModeToggle.shouldToggle(input: .key(.character("a")), editorText: ""))
    #expect(!SloppyTUIShellModeToggle.shouldToggle(input: .key(.escape), editorText: ""))
}

@Test
func shellCommandResultFormatterIncludesCommandExitAndOutput() {
    let markdown = SloppyTUIShellCommandResultFormatter.markdown(
        command: "printf hi",
        cwd: "/tmp/project",
        result: .object([
            "exitCode": .number(0),
            "timedOut": .bool(false),
            "stdout": .string("hi\n"),
            "stderr": .string(""),
            "stdoutTruncated": .bool(false),
            "stderrTruncated": .bool(false),
        ])
    )

    #expect(markdown.contains("## Shell"))
    #expect(markdown.contains("printf hi"))
    #expect(markdown.contains("- cwd: `/tmp/project`"))
    #expect(markdown.contains("- exit code: `0`"))
    #expect(markdown.contains("stdout:"))
    #expect(markdown.contains("hi"))
}

@Test
func shellCommandResultFormatterMarksTimeoutAndTruncation() {
    let markdown = SloppyTUIShellCommandResultFormatter.markdown(
        command: "sleep 30",
        cwd: "/tmp/project",
        result: .object([
            "exitCode": .number(-1),
            "timedOut": .bool(true),
            "stdout": .string("partial"),
            "stderr": .string("error"),
            "stdoutTruncated": .bool(true),
            "stderrTruncated": .bool(true),
        ])
    )

    #expect(markdown.contains("- exit code: `-1`"))
    #expect(markdown.contains("- timed out"))
    #expect(markdown.contains("- stdout truncated"))
    #expect(markdown.contains("- stderr truncated"))
    #expect(markdown.contains("stderr:"))
}

@Test
func codeEditorLauncherParsesConfiguredEditorCommand() {
    let command = SloppyTUICodeEditorLauncher.configuredCommandLine(environment: [
        "SLOPPY_CODE_EDITOR": "code --reuse-window",
        "VISUAL": "vim",
    ])

    #expect(command == ["code", "--reuse-window"])
}

@Test
func codeEditorLauncherSkipsTerminalEditorFallbacks() {
    let command = SloppyTUICodeEditorLauncher.configuredCommandLine(environment: [
        "VISUAL": "vim",
        "EDITOR": "nano",
    ])

    #expect(command == nil)
}

@Test
func codeEditorLauncherUsesExplicitPreferredEditor() {
    let xcodeLabels = SloppyTUICodeEditorLauncher.candidateCommandLabels(
        preferredEditor: ["xcode"],
        environment: ["SLOPPY_CODE_EDITOR": "code --reuse-window"]
    )
    let cursorLabels = SloppyTUICodeEditorLauncher.candidateCommandLabels(
        preferredEditor: ["cursor", "--reuse-window"],
        environment: [:]
    )

    #expect(xcodeLabels == ["xcode", "Xcode"])
    #expect(cursorLabels == ["cursor --reuse-window", "Cursor"])
}

@Test
func doubleEscapeDetectorInterruptsOnlyOnSecondNearbyEscape() {
    var detector = SloppyTUIDoubleEscapeDetector(interval: 0.75)
    let first = Date(timeIntervalSince1970: 100)
    let second = first.addingTimeInterval(0.4)
    let firstResult = detector.shouldInterrupt(input: TerminalInput.key(.escape), now: first, isInterruptible: true)
    let secondResult = detector.shouldInterrupt(input: TerminalInput.key(.escape), now: second, isInterruptible: true)

    #expect(!firstResult)
    #expect(secondResult)
}

@Test
func doubleEscapeDetectorIgnoresSlowOrNonInterruptibleEscapes() {
    var detector = SloppyTUIDoubleEscapeDetector(interval: 0.75)
    let first = Date(timeIntervalSince1970: 100)
    let slowSecond = first.addingTimeInterval(1.0)
    let firstResult = detector.shouldInterrupt(input: TerminalInput.key(.escape), now: first, isInterruptible: true)
    let slowResult = detector.shouldInterrupt(input: TerminalInput.key(.escape), now: slowSecond, isInterruptible: true)
    let nonInterruptibleResult = detector.shouldInterrupt(
        input: TerminalInput.key(.escape),
        now: slowSecond.addingTimeInterval(0.2),
        isInterruptible: false
    )

    #expect(!firstResult)
    #expect(!slowResult)
    #expect(!nonInterruptibleResult)
}

@Test
func doubleEscapeDetectorResetsOnOtherInput() {
    var detector = SloppyTUIDoubleEscapeDetector(interval: 0.75)
    let first = Date(timeIntervalSince1970: 100)
    let other = first.addingTimeInterval(0.2)
    let second = first.addingTimeInterval(0.4)
    let firstResult = detector.shouldInterrupt(input: TerminalInput.key(.escape), now: first, isInterruptible: true)
    let otherResult = detector.shouldInterrupt(input: TerminalInput.key(.character("a")), now: other, isInterruptible: true)
    let secondResult = detector.shouldInterrupt(input: TerminalInput.key(.escape), now: second, isInterruptible: true)

    #expect(!firstResult)
    #expect(!otherResult)
    #expect(!secondResult)
}

@Test
func controlCExitDetectorRequiresSecondNearbyPress() {
    var detector = SloppyTUIControlCExitDetector(interval: 2)
    let first = Date(timeIntervalSince1970: 100)
    let second = first.addingTimeInterval(1.5)
    let firstResult = detector.shouldExit(now: first)
    let secondResult = detector.shouldExit(now: second)

    #expect(!firstResult)
    #expect(secondResult)
}

@Test
func controlCExitDetectorIgnoresSlowOrResetPresses() {
    var detector = SloppyTUIControlCExitDetector(interval: 2)
    let first = Date(timeIntervalSince1970: 100)
    let slowSecond = first.addingTimeInterval(3)
    let afterReset = slowSecond.addingTimeInterval(1)
    let firstResult = detector.shouldExit(now: first)
    let slowResult = detector.shouldExit(now: slowSecond)

    #expect(!firstResult)
    #expect(!slowResult)

    detector.reset()
    let resetResult = detector.shouldExit(now: afterReset)
    #expect(!resetResult)
}

@Test
func pickerSearchFiltersAcrossLabelDescriptionAndGroup() {
    let items = [
        SloppyTUIPickerItem(
            value: "openrouter:anthropic/claude-sonnet",
            label: "claude-sonnet",
            description: "Claude Sonnet",
            isCurrent: false,
            group: "OpenRouter / anthropic"
        ),
        SloppyTUIPickerItem(
            value: "opencode:yteam:internal/internal-model",
            label: "internal-model",
            description: "tools",
            isCurrent: false,
            group: "OpenCode / yteam / internal"
        ),
        SloppyTUIPickerItem(
            value: "openai:gpt-5.4-mini",
            label: "gpt-5.4-mini",
            description: "reasoning",
            isCurrent: false,
            group: "OpenAI / gpt"
        ),
    ]

    let filtered = SloppyTUIPicker.filteredItems(items, query: "yteam tools")

    #expect(filtered.map(\.value) == ["opencode:yteam:internal/internal-model"])
}

@Test
func pickerSearchRestoresItemsAfterClearingQuery() {
    let items = [
        SloppyTUIPickerItem(value: "openai:gpt-5.4-mini", label: "gpt-5.4-mini", description: nil, isCurrent: false, group: "OpenAI / gpt"),
        SloppyTUIPickerItem(value: "openai:o4-mini", label: "o4-mini", description: nil, isCurrent: false, group: "OpenAI / o4"),
    ]
    var picker = SloppyTUIPicker(
        kind: .model,
        title: "Select model",
        items: items,
        selectedIndex: 0,
        allItems: items,
        supportsSearch: true
    )

    picker.setSearchQuery("o4")
    #expect(picker.items.map(\.value) == ["openai:o4-mini"])

    picker.clearSearchQuery()
    #expect(picker.items.map(\.value) == ["openai:gpt-5.4-mini", "openai:o4-mini"])
}

@Test
func toolApprovalStateBuildsCurrentSessionPicker() throws {
    let now = Date(timeIntervalSince1970: 100)
    let current = ToolApprovalRecord(
        id: "approval-current",
        approvalKind: .riskyTool,
        agentId: "agent-1",
        sessionId: "session-1",
        tool: "files.write",
        arguments: ["path": .string("/tmp/file.txt")],
        reason: "Write /tmp/file.txt",
        createdAt: now,
        updatedAt: now,
        expiresAt: now.addingTimeInterval(60)
    )
    let other = ToolApprovalRecord(
        id: "approval-other",
        agentId: "agent-1",
        sessionId: "session-2",
        tool: "runtime.exec",
        createdAt: now,
        updatedAt: now,
        expiresAt: now.addingTimeInterval(60)
    )

    let approval = try #require(SloppyTUIToolApprovalState.pendingApproval(
        in: [other, current],
        agentID: "agent-1",
        sessionID: "session-1"
    ))
    let picker = SloppyTUIToolApprovalState.picker(
        for: approval,
        previousApprovalID: approval.id,
        previousSelectedIndex: 1
    )

    #expect(approval.id == "approval-current")
    #expect(picker.kind == .toolApproval)
    #expect(picker.selectedIndex == 1)
    #expect(picker.items.map(\.label) == ["Allow once", "Allow for session", "Deny"])
    #expect(picker.items[0].description == "files.write - Write /tmp/file.txt")
}

@Test
func launchDraftSessionIsNotPersistedSessionID() {
    let agent = AgentSummary(id: "sloppy", displayName: "SLOPPY", role: "SLOPPY")
    let session = SloppyTUIApp.makeDraftSession(agent: agent, projectID: "project-1")

    #expect(session.id == "new")
    #expect(session.agentId == "sloppy")
    #expect(session.title == "New session")
    #expect(session.projectId == "project-1")
    #expect(!session.id.hasPrefix("session-"))
}

@Test
func draftSessionResetKeepsPreviousPersistedSessionAsPendingCheckpoint() {
    let checkpoint = SloppyTUIDraftSessionReset.pendingCheckpointSessionID(
        currentSessionID: "session-previous",
        hasPersistedSession: true
    )

    #expect(checkpoint == "session-previous")
}

@Test
func draftSessionResetDoesNotInventCheckpointForDraftSession() {
    let checkpoint = SloppyTUIDraftSessionReset.pendingCheckpointSessionID(
        currentSessionID: "new",
        hasPersistedSession: false
    )

    #expect(checkpoint == nil)
}

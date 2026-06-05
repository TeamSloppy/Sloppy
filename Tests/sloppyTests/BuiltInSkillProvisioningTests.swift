import Foundation
import Testing
@testable import Protocols
@testable import sloppy

@Test
func coreServiceCreateAgentInstallsBuiltInTaskSpecSkill() async throws {
    let service = CoreService(
        config: .test,
        persistenceBuilder: InMemoryCorePersistenceBuilder(),
        sharedSkillsRootURLs: []
    )
    _ = try await service.createAgent(
        AgentCreateRequest(
            id: "task-spec-new-agent",
            displayName: "Task Spec New Agent",
            role: "Planner"
        )
    )

    let response = try await service.listAgentSkills(agentID: "task-spec-new-agent")
    let skillIDs = Set(response.skills.map(\.id))
    let expectedCoreSkillIDs = Set([
        BuiltInSkillCatalog.modeAskID,
        BuiltInSkillCatalog.modeBuildID,
        BuiltInSkillCatalog.modePlanID,
        BuiltInSkillCatalog.modeDebugID,
        BuiltInSkillCatalog.modeAutoID,
        BuiltInSkillCatalog.kanbanTaskManagerID,
        BuiltInSkillCatalog.taskSpecWriterID,
        BuiltInSkillCatalog.workflowID
    ])
    #expect(skillIDs.isSuperset(of: expectedCoreSkillIDs))

    let skill = try #require(response.skills.first { $0.id == BuiltInSkillCatalog.taskSpecWriterID })

    #expect(skill.name == "task-spec-writer")
    #expect(skill.userInvocable == false)
    #expect(skill.allowedTools.contains("project.task_create"))
    #expect(FileManager.default.fileExists(atPath: URL(fileURLWithPath: skill.localPath)
        .appendingPathComponent("SKILL.md")
        .path))

    let kanbanSkill = try #require(response.skills.first { $0.id == BuiltInSkillCatalog.kanbanTaskManagerID })
    #expect(kanbanSkill.name == "kanban-task-manager")
    #expect(kanbanSkill.userInvocable == false)
    #expect(kanbanSkill.allowedTools.contains("project.current"))
    #expect(kanbanSkill.allowedTools.contains("project.task_get"))
    #expect(kanbanSkill.allowedTools.contains("project.task_create"))
    #expect(kanbanSkill.allowedTools.contains("project.task_update"))
    #expect(FileManager.default.fileExists(atPath: URL(fileURLWithPath: kanbanSkill.localPath)
        .appendingPathComponent("SKILL.md")
        .path))

    let modeBuild = try #require(response.skills.first { $0.id == BuiltInSkillCatalog.modeBuildID })
    #expect(modeBuild.name == "mode-build")
    #expect(modeBuild.userInvocable == false)
    #expect(modeBuild.allowedTools.isEmpty)
    #expect(FileManager.default.fileExists(atPath: URL(fileURLWithPath: modeBuild.localPath)
        .appendingPathComponent("SKILL.md")
        .path))

    let modePlan = try #require(response.skills.first { $0.id == BuiltInSkillCatalog.modePlanID })
    #expect(modePlan.name == "mode-plan")
    #expect(modePlan.userInvocable == false)
    #expect(modePlan.allowedTools.isEmpty)

    let modeAsk = try #require(response.skills.first { $0.id == BuiltInSkillCatalog.modeAskID })
    #expect(modeAsk.allowedTools.isEmpty)

    let modeDebug = try #require(response.skills.first { $0.id == BuiltInSkillCatalog.modeDebugID })
    #expect(modeDebug.allowedTools.isEmpty)

    let modeAuto = try #require(response.skills.first { $0.id == BuiltInSkillCatalog.modeAutoID })
    #expect(modeAuto.name == "mode-auto")
    #expect(modeAuto.userInvocable == false)
    #expect(modeAuto.allowedTools.isEmpty)

    let workflow = try #require(response.skills.first { $0.id == BuiltInSkillCatalog.workflowID })
    #expect(workflow.name == "workflow")
    #expect(workflow.userInvocable == true)
    #expect(workflow.allowedTools.contains("project.workflow"))
}

@Test
func builtInSkillsBackfillIsIdempotentForExistingAgents() throws {
    let agentsRootURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("built-in-skill-provisioning-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("agents", isDirectory: true)
    let catalogStore = AgentCatalogFileStore(agentsRootURL: agentsRootURL)
    _ = try catalogStore.createAgent(
        AgentCreateRequest(
            id: "existing-agent",
            displayName: "Existing Agent",
            role: "Planner"
        ),
        availableModels: [
            ProviderModelOption(id: "mock:test-model", title: "Mock", capabilities: ["tools"])
        ]
    )
    let skillsStore = AgentSkillsFileStore(agentsRootURL: agentsRootURL, sharedSkillsRootURLs: [])

    try skillsStore.ensureSkillsDirectory(agentID: "existing-agent")
    try skillsStore.ensureSkillsDirectory(agentID: "existing-agent")

    let installed = try skillsStore.listSkills(agentID: "existing-agent")
    let builtInIDs = Set(installed.map(\.id))

    #expect(installed.count >= 7)
    #expect(builtInIDs.isSuperset(of: Set([
        BuiltInSkillCatalog.modeAskID,
        BuiltInSkillCatalog.modeBuildID,
        BuiltInSkillCatalog.modePlanID,
        BuiltInSkillCatalog.modeDebugID,
        BuiltInSkillCatalog.modeAutoID,
        BuiltInSkillCatalog.kanbanTaskManagerID,
        BuiltInSkillCatalog.taskSpecWriterID,
        BuiltInSkillCatalog.workflowID
    ])))
    #expect(installed.filter { $0.owner == "sloppy" && $0.id != BuiltInSkillCatalog.workflowID }.allSatisfy { $0.userInvocable == false })
    #expect(installed.first { $0.id == BuiltInSkillCatalog.workflowID }?.userInvocable == true)
    #expect(FileManager.default.fileExists(atPath: agentsRootURL
        .appendingPathComponent("existing-agent", isDirectory: true)
        .appendingPathComponent("skills", isDirectory: true)
        .appendingPathComponent("sloppy/task-spec-writer", isDirectory: true)
        .appendingPathComponent("SKILL.md")
        .path))
    #expect(FileManager.default.fileExists(atPath: agentsRootURL
        .appendingPathComponent("existing-agent", isDirectory: true)
        .appendingPathComponent("skills", isDirectory: true)
        .appendingPathComponent("sloppy/mode-debug", isDirectory: true)
        .appendingPathComponent("SKILL.md")
        .path))
    #expect(FileManager.default.fileExists(atPath: agentsRootURL
        .appendingPathComponent("existing-agent", isDirectory: true)
        .appendingPathComponent("skills", isDirectory: true)
        .appendingPathComponent("sloppy/mode-auto", isDirectory: true)
        .appendingPathComponent("SKILL.md")
        .path))
    #expect(FileManager.default.fileExists(atPath: agentsRootURL
        .appendingPathComponent("existing-agent", isDirectory: true)
        .appendingPathComponent("skills", isDirectory: true)
        .appendingPathComponent("sloppy/kanban-task-manager", isDirectory: true)
        .appendingPathComponent("SKILL.md")
        .path))
}

@Test
func builtInModePlanReferencesKanbanTaskManager() throws {
    let markdown = BuiltInSkillCatalog.modeSkillMarkdown(for: .plan)

    #expect(markdown.contains("sloppy/kanban-task-manager"))
}

@Test
func builtInSkillsLoadAdditionalSkillsFromInstalledShareDirectoryViaSymlink() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }

    let installRoot = root.appendingPathComponent("install", isDirectory: true)
    let linkRoot = root.appendingPathComponent("links", isDirectory: true)
    let binDirectory = installRoot.appendingPathComponent("bin", isDirectory: true)
    let skillDirectory = installRoot
        .appendingPathComponent("share/sloppy/Skills/release-only", isDirectory: true)
    try FileManager.default.createDirectory(at: binDirectory, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: linkRoot, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: skillDirectory, withIntermediateDirectories: true)

    let realBinaryPath = binDirectory.appendingPathComponent("sloppy").path
    let symlinkPath = linkRoot.appendingPathComponent("sloppy").path
    FileManager.default.createFile(atPath: realBinaryPath, contents: Data(), attributes: nil)
    try FileManager.default.createSymbolicLink(atPath: symlinkPath, withDestinationPath: realBinaryPath)

    try """
    ---
    name: release-only
    description: Skill shipped only in release share resources.
    user_invocable: true
    allowed_tools: project.current
    ---

    # Release Only
    """.write(to: skillDirectory.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

    let definitions = BuiltInSkillCatalog.resourceSkillDefinitions(
        executablePath: symlinkPath,
        currentDirectoryPath: root.path,
        sourceFilePath: root.appendingPathComponent("Missing/BuiltInSkillCatalog.swift").path
    )

    let skill = try #require(definitions.first { $0.repo == "release-only" })
    #expect(skill.owner == "bundled")
    #expect(skill.name == "release-only")
    #expect(skill.allowedTools == ["project.current"])
}

@Test
func agentSkillsStoreListsSharedSkillsFromAgentsRoot() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("shared-skill-provisioning-\(UUID().uuidString)", isDirectory: true)
    let agentsRootURL = root.appendingPathComponent("agents", isDirectory: true)
    let sharedRootURL = root.appendingPathComponent(".agents", isDirectory: true)
    let catalogStore = AgentCatalogFileStore(agentsRootURL: agentsRootURL)
    _ = try catalogStore.createAgent(
        AgentCreateRequest(
            id: "shared-agent",
            displayName: "Shared Agent",
            role: "Planner"
        ),
        availableModels: [
            ProviderModelOption(id: "mock:test-model", title: "Mock", capabilities: ["tools"])
        ]
    )

    let sharedSkillURL = sharedRootURL
        .appendingPathComponent("skills", isDirectory: true)
        .appendingPathComponent("prd", isDirectory: true)
    try FileManager.default.createDirectory(at: sharedSkillURL, withIntermediateDirectories: true)
    try """
    ---
    name: prd
    description: Shared PRD writer
    user_invocable: false
    allowed_tools: project.task_create, files.read
    context: fork
    agent: planner
    ---
    # PRD
    """.write(to: sharedSkillURL.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

    let skillsStore = AgentSkillsFileStore(
        agentsRootURL: agentsRootURL,
        sharedSkillsRootURLs: [sharedRootURL]
    )
    try skillsStore.ensureSkillsDirectory(agentID: "shared-agent")

    #expect(skillsStore.sharedSkillsRootPaths() == [
        sharedRootURL.appendingPathComponent("skills", isDirectory: true).standardizedFileURL.path
    ])

    let installed = try skillsStore.listSkills(agentID: "shared-agent")
    let sharedSkill = try #require(installed.first { $0.id == "shared/prd" })

    #expect(sharedSkill.owner == "shared")
    #expect(sharedSkill.repo == "prd")
    #expect(sharedSkill.name == "prd")
    #expect(sharedSkill.description == "Shared PRD writer")
    #expect(sharedSkill.version == "shared")
    #expect(sharedSkill.localPath == sharedSkillURL.standardizedFileURL.path)
    #expect(sharedSkill.userInvocable == false)
    #expect(sharedSkill.allowedTools == ["project.task_create", "files.read"])
    #expect(sharedSkill.context == SkillContext.fork)
    #expect(sharedSkill.agent == "planner")
    #expect(try skillsStore.getSkillPath(agentID: "shared-agent", skillID: "shared/prd") == sharedSkillURL.standardizedFileURL.path)
}

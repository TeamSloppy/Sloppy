import Foundation
import Testing
@testable import Protocols
@testable import sloppy

@Test
func coreServiceCreateAgentInstallsBuiltInTaskSpecSkill() async throws {
    let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    _ = try await service.createAgent(
        AgentCreateRequest(
            id: "task-spec-new-agent",
            displayName: "Task Spec New Agent",
            role: "Planner"
        )
    )

    let response = try await service.listAgentSkills(agentID: "task-spec-new-agent")
    let skillIDs = Set(response.skills.map(\.id))
    #expect(skillIDs == Set([
        BuiltInSkillCatalog.modeAskID,
        BuiltInSkillCatalog.modeBuildID,
        BuiltInSkillCatalog.modePlanID,
        BuiltInSkillCatalog.modeDebugID,
        BuiltInSkillCatalog.taskSpecWriterID
    ]))

    let skill = try #require(response.skills.first { $0.id == BuiltInSkillCatalog.taskSpecWriterID })

    #expect(skill.name == "task-spec-writer")
    #expect(skill.userInvocable == false)
    #expect(skill.allowedTools.contains("project.task_create"))
    #expect(FileManager.default.fileExists(atPath: URL(fileURLWithPath: skill.localPath)
        .appendingPathComponent("SKILL.md")
        .path))

    let modeBuild = try #require(response.skills.first { $0.id == BuiltInSkillCatalog.modeBuildID })
    #expect(modeBuild.name == "mode-build")
    #expect(modeBuild.userInvocable == false)
    #expect(modeBuild.allowedTools.contains("planning.progress_update"))
    #expect(FileManager.default.fileExists(atPath: URL(fileURLWithPath: modeBuild.localPath)
        .appendingPathComponent("SKILL.md")
        .path))

    let modePlan = try #require(response.skills.first { $0.id == BuiltInSkillCatalog.modePlanID })
    #expect(modePlan.name == "mode-plan")
    #expect(modePlan.userInvocable == false)
    #expect(modePlan.allowedTools.contains("planning.request_input"))
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
    let skillsStore = AgentSkillsFileStore(agentsRootURL: agentsRootURL)

    try skillsStore.ensureSkillsDirectory(agentID: "existing-agent")
    try skillsStore.ensureSkillsDirectory(agentID: "existing-agent")

    let installed = try skillsStore.listSkills(agentID: "existing-agent")
    let builtInIDs = Set(installed.map(\.id))

    #expect(installed.count == 5)
    #expect(builtInIDs == Set([
        BuiltInSkillCatalog.modeAskID,
        BuiltInSkillCatalog.modeBuildID,
        BuiltInSkillCatalog.modePlanID,
        BuiltInSkillCatalog.modeDebugID,
        BuiltInSkillCatalog.taskSpecWriterID
    ]))
    #expect(installed.allSatisfy { $0.userInvocable == false })
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
}

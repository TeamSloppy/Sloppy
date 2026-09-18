import Foundation
import Testing
import Protocols
@testable import sloppy

@Test
func agentPluginInspectPlanAndApprovalFlow() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("agent-plugin-test-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let zip = try makeAgentPluginZIP(at: root, includeSoftware: true)
    let manager = AgentPluginManager(workspaceRootURL: root.appendingPathComponent("workspace"), store: InMemoryPersistenceStore())

    let uploaded = try await manager.upload(Data(contentsOf: zip))
    #expect(uploaded.sha256.count == 64)
    let inspection = try await manager.inspect(.init(source: .init(kind: .upload, uploadId: uploaded.id)))
    #expect(inspection.manifest.id == "tests.sample")
    #expect(inspection.trust == .unverified)

    let plan = try await manager.makePlan(
        .init(inspectionId: inspection.id, agentIds: ["agent-1"], inputs: ["message": "hello"]),
        availableAgentIDs: ["agent-1"]
    )
    #expect(plan.requiresTrustConfirmation)
    #expect(plan.requiresCommandApproval)
    #expect(plan.changes.contains { $0.kind == .skill })

    do {
        _ = try await manager.consumePlan(.init(planId: plan.id, approvalHash: plan.approvalHash, trustConfirmed: false, commandsApproved: true))
        Issue.record("Expected trust approval to be required")
    } catch let error as AgentPluginManagerError {
        guard case .approvalRequired = error else { Issue.record("Unexpected error: \(error)"); return }
    }
}

@Test
func agentPluginManifestRequiresRollbackAndUninstall() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("agent-plugin-invalid-test-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let zip = try makeAgentPluginZIP(at: root, includeSoftware: false, invalidSoftware: true)
    let manager = AgentPluginManager(workspaceRootURL: root.appendingPathComponent("workspace"), store: InMemoryPersistenceStore())
    let uploaded = try await manager.upload(Data(contentsOf: zip))
    await #expect(throws: AgentPluginManagerError.self) {
        _ = try await manager.inspect(.init(source: .init(kind: .upload, uploadId: uploaded.id)))
    }
}

@Test
func agentPluginRegistriesSeedOfficialStore() async {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("agent-plugin-registry-test-\(UUID().uuidString)")
    let manager = AgentPluginManager(workspaceRootURL: root, store: InMemoryPersistenceStore())
    let registries = await manager.listRegistries()
    #expect(registries == [AgentPluginManager.officialRegistry])
}

@Test
func agentPluginSHA256MatchesKnownVector() {
    #expect(AgentPluginSHA256.hash(Data("abc".utf8)) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
}

@Test
func agentPluginServiceInstallsAndRemovesSkillAndMCPComponents() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("agent-plugin-service-test-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    var config = CoreConfig.test
    config.workspace = .init(name: "workspace", basePath: root.path)
    let service = CoreService(
        config: config,
        configPath: root.appendingPathComponent("sloppy.json").path,
        currentDirectory: root.path,
        persistenceBuilder: InMemoryCorePersistenceBuilder()
    )
    _ = try await service.createAgent(.init(id: "agent-1", displayName: "Agent One", role: "developer"))
    let zip = try makeAgentPluginZIP(at: root.appendingPathComponent("fixture"), includeMCP: true)
    let upload = try await service.uploadAgentPlugin(data: Data(contentsOf: zip))
    let inspection = try await service.inspectAgentPlugin(.init(source: .init(kind: .upload, uploadId: upload.id)))
    let plan = try await service.planAgentPlugin(.init(inspectionId: inspection.id, agentIds: ["agent-1"], inputs: ["message": "hello"]))
    let operation = try await service.installAgentPlugin(.init(planId: plan.id, approvalHash: plan.approvalHash, trustConfirmed: true, commandsApproved: true))

    #expect(operation.status == .completed)
    #expect(try await service.listAgentSkills(agentID: "agent-1").skills.contains { $0.id == "agent-plugin-tests/sample-sample" })
    let configAfterInstall = await service.getConfig()
    #expect(configAfterInstall.mcp.servers.contains { $0.id == "tests.sample/fixture" })
    #expect(await service.listAgentPlugins().map(\.id) == ["tests.sample"])

    let removal = try await service.uninstallAgentPlugin(id: "tests.sample", forceModifiedComponents: false)
    #expect(removal.status == .completed)
    let configAfterRemoval = await service.getConfig()
    #expect(!configAfterRemoval.mcp.servers.contains { $0.id == "tests.sample/fixture" })
    #expect(await service.listAgentPlugins().isEmpty)
}

private func makeAgentPluginZIP(at root: URL, includeSoftware: Bool = false, invalidSoftware: Bool = false, includeMCP: Bool = false) throws -> URL {
    let package = root.appendingPathComponent("package", isDirectory: true)
    let skill = package.appendingPathComponent("skills/sample", isDirectory: true)
    try FileManager.default.createDirectory(at: skill, withIntermediateDirectories: true)
    try Data("---\nname: sample\ndescription: test\n---\n# Sample\n".utf8).write(to: skill.appendingPathComponent("SKILL.md"))

    var software: [AgentPluginSoftwareComponent] = []
    if includeSoftware || invalidSoftware {
        software = [
            .init(
                id: "helper",
                install: [.init(id: "install", executable: "/usr/bin/true")],
                uninstall: invalidSoftware ? [] : [.init(id: "uninstall", executable: "/usr/bin/true")],
                rollback: invalidSoftware ? [] : [.init(id: "rollback", executable: "/usr/bin/true")]
            ),
        ]
    }
    let manifest = AgentPluginManifest(
        id: "tests.sample",
        name: "Sample",
        version: "1.2.3",
        inputs: [.init(id: "message", title: "Message", required: true)],
        components: .init(
            skills: [.init(id: "sample", path: "skills/sample")],
            mcpServers: includeMCP ? [.init(id: "fixture", command: "/usr/bin/true")] : [],
            software: software
        )
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(manifest).write(to: package.appendingPathComponent("agent-plugin.json"))

    let zip = root.appendingPathComponent("sample.zip")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
    process.arguments = ["-qr", zip.path, "."]
    process.currentDirectoryURL = package
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { throw AgentPluginManagerError.archiveInvalid("test ZIP creation failed") }
    return zip
}

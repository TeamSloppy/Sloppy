import Foundation
import Testing
@testable import Protocols

@Test
func actorSystemRoleSerialization() throws {
    let roles: [ActorSystemRole] = [.manager, .developer, .qa, .reviewer, .custom]
    let expected = ["manager", "developer", "qa", "reviewer", "custom"]
    for (role, raw) in zip(roles, expected) {
        #expect(role.rawValue == raw)
        let encoded = try JSONEncoder().encode(role)
        let decoded = try JSONDecoder().decode(ActorSystemRole.self, from: encoded)
        #expect(decoded == role)
    }
}

@Test
func actorNodeIncludesSystemRole() throws {
    let node = ActorNode(
        id: "node-1",
        displayName: "Alice Dev",
        kind: .agent,
        systemRole: .developer
    )
    let data = try JSONEncoder().encode(node)
    let decoded = try JSONDecoder().decode(ActorNode.self, from: data)
    #expect(decoded.systemRole == .developer)
    #expect(decoded.id == "node-1")
}

@Test
func actorNodeSystemRoleDefaultsToNil() throws {
    let node = ActorNode(
        id: "node-2",
        displayName: "Bob",
        kind: .human
    )
    #expect(node.systemRole == nil)
    let data = try JSONEncoder().encode(node)
    let decoded = try JSONDecoder().decode(ActorNode.self, from: data)
    #expect(decoded.systemRole == nil)
}

@Test
func actorNodeSystemRoleDecodesFromLegacyJsonWithoutField() throws {
    let json = """
    {
        "id": "node-legacy",
        "displayName": "Legacy",
        "kind": "agent",
        "positionX": 0,
        "positionY": 0,
        "createdAt": "2025-01-01T00:00:00Z"
    }
    """.data(using: .utf8)!
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let node = try decoder.decode(ActorNode.self, from: json)
    #expect(node.systemRole == nil)
}

@Test
func reviewApprovalModeSerialization() throws {
    let modes: [ReviewApprovalMode] = [.auto, .human, .agent]
    let expected = ["auto", "human", "agent"]
    for (mode, raw) in zip(modes, expected) {
        #expect(mode.rawValue == raw)
        let encoded = try JSONEncoder().encode(mode)
        let decoded = try JSONDecoder().decode(ReviewApprovalMode.self, from: encoded)
        #expect(decoded == mode)
    }
}

@Test
func projectReviewSettingsDefaultValues() {
    let settings = ProjectReviewSettings()
    #expect(settings.enabled == false)
    #expect(settings.approvalMode == .human)
}

@Test
func projectReviewSettingsSerialization() throws {
    let settings = ProjectReviewSettings(enabled: true, approvalMode: .auto)
    let data = try JSONEncoder().encode(settings)
    let decoded = try JSONDecoder().decode(ProjectReviewSettings.self, from: data)
    #expect(decoded.enabled == true)
    #expect(decoded.approvalMode == .auto)
}

@Test
func projectRecordIncludesReviewSettings() throws {
    let record = ProjectRecord(
        id: "proj-1",
        name: "Test",
        description: "A project",
        channels: [],
        tasks: [],
        repoPath: "/tmp/repo",
        reviewSettings: ProjectReviewSettings(enabled: true, approvalMode: .agent)
    )
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(record)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let decoded = try decoder.decode(ProjectRecord.self, from: data)
    #expect(decoded.repoPath == "/tmp/repo")
    #expect(decoded.reviewSettings.enabled == true)
    #expect(decoded.reviewSettings.approvalMode == .agent)
}

@Test
func projectTaskIncludesWorktreeBranch() throws {
    let task = ProjectTask(
        id: "task-1",
        title: "Implement feature",
        description: "",
        priority: "medium",
        status: "in_progress",
        worktreeBranch: "sloppy/task-abc123"
    )
    #expect(task.worktreeBranch == "sloppy/task-abc123")
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(task)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let decoded = try decoder.decode(ProjectTask.self, from: data)
    #expect(decoded.worktreeBranch == "sloppy/task-abc123")
}

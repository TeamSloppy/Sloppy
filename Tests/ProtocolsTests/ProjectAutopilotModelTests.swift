import Foundation
import Testing
@testable import Protocols

@Test
func projectAutopilotSettingsDefaultsAreSafe() {
    let settings = ProjectAutopilotSettings()

    #expect(settings.enabled == false)
    #expect(settings.mode == .assistive)
    #expect(settings.includedTags == [])
    #expect(settings.ignoredTags == [])
    #expect(settings.maxParallelTasks == 1)
    #expect(settings.canCommit == false)
    #expect(settings.canPush == false)
}

@Test
func legacyProjectAndTaskDecodeWithAutopilotDefaults() throws {
    let json = """
    {
        "id": "proj-1",
        "name": "Project",
        "description": "",
        "channels": [],
        "tasks": [
            {
                "id": "task-1",
                "title": "Task",
                "description": "",
                "priority": "medium",
                "status": "backlog",
                "createdAt": "2025-01-01T00:00:00Z",
                "updatedAt": "2025-01-01T00:00:00Z"
            }
        ],
        "createdAt": "2025-01-01T00:00:00Z",
        "updatedAt": "2025-01-01T00:00:00Z"
    }
    """.data(using: .utf8)!
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    let project = try decoder.decode(ProjectRecord.self, from: json)

    #expect(project.autopilotSettings == ProjectAutopilotSettings())
    #expect(project.tasks[0].createdBy == nil)
    #expect(project.tasks[0].dependsOnTaskIds == [])
}

@Test
func projectAutopilotFieldsEncodeAndDecode() throws {
    let task = ProjectTask(
        id: "task-1",
        title: "Task",
        description: "",
        priority: "medium",
        status: "backlog",
        createdBy: "user",
        dependsOnTaskIds: ["task-0"]
    )
    let project = ProjectRecord(
        id: "proj-1",
        name: "Project",
        description: "",
        channels: [],
        tasks: [task],
        autopilotSettings: ProjectAutopilotSettings(
            enabled: true,
            mode: .parallel,
            defaultAgentId: "builder",
            reviewerAgentId: "reviewer",
            includedTags: ["autopilot", "ship"],
            ignoredTags: ["manual", "blocked"],
            trustedAuthors: ["user"],
            maxParallelTasks: 3,
            canUseWeb: true,
            canEditFiles: true,
            canRunCommands: true,
            canStartLocalhost: true,
            canCommit: true,
            canPush: false
        )
    )
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(project)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    let decoded = try decoder.decode(ProjectRecord.self, from: data)

    #expect(decoded.autopilotSettings.enabled == true)
    #expect(decoded.autopilotSettings.mode == .parallel)
    #expect(decoded.autopilotSettings.defaultAgentId == "builder")
    #expect(decoded.autopilotSettings.includedTags == ["autopilot", "ship"])
    #expect(decoded.autopilotSettings.ignoredTags == ["manual", "blocked"])
    #expect(decoded.autopilotSettings.maxParallelTasks == 3)
    #expect(decoded.tasks[0].createdBy == "user")
    #expect(decoded.tasks[0].dependsOnTaskIds == ["task-0"])
}

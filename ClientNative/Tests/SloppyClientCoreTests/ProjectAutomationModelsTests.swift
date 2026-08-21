import Foundation
import SloppyClientCore
import Testing

@Suite("Project automation models")
struct ProjectAutomationModelsTests {
    @Test("automation definition decodes the Core wire format")
    func definitionDecoding() throws {
        let payload = """
        {
          "id": "daily-review",
          "projectId": "project-1",
          "name": "Daily review",
          "description": "Review open tasks",
          "version": 2,
          "enabled": true,
          "workflowId": "workflow-1",
          "repositoryFullName": "sloppy/client",
          "trigger": { "type": "cron", "config": { "expression": "0 9 * * *" } },
          "taskMode": "create_or_attach",
          "model": null,
          "permissionsScope": "project_visible",
          "createdAt": "2026-08-20T09:00:00Z",
          "updatedAt": "2026-08-21T09:00:00Z"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let definition = try decoder.decode(
            ProjectAutomationDefinition.self,
            from: Data(payload.utf8)
        )

        #expect(definition.id == "daily-review")
        #expect(definition.trigger.type == .cron)
        #expect(definition.taskMode == .createOrAttach)
        #expect(definition.permissionsScope == .projectVisible)
        #expect(definition.trigger.config["expression"] == .string("0 9 * * *"))
    }

    @Test("manual run request uses the default human actor")
    func manualRunRequestDefaults() {
        let request = ProjectAutomationManualRunRequest()

        #expect(request.actorId == "human:admin")
        #expect(request.input.isEmpty)
    }

    @Test("automation creation request preserves its project workflow configuration")
    func creationRequestCoding() throws {
        let request = ProjectAutomationDefinitionUpsertRequest(
            name: "Weekday review",
            description: "Review open tasks",
            workflowId: "workflow-review",
            repositoryFullName: "sloppy/client",
            trigger: .init(type: .cron, config: ["schedule": .string("0 9 * * 1-5")]),
            taskMode: .createOrAttach,
            permissionsScope: .projectVisible
        )

        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(
            ProjectAutomationDefinitionUpsertRequest.self,
            from: data
        )

        #expect(decoded == request)
        #expect(decoded.workflowId == "workflow-review")
        #expect(decoded.trigger.config["schedule"] == .string("0 9 * * 1-5"))
    }
}

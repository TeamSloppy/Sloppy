import Foundation
import Protocols
import Testing
@testable import sloppy

@Suite
struct TaskPickupRulesTests {
    private func importedTask() -> ProjectTask {
        ProjectTask(id: "TASK-1", title: "Fix the iOS filter", description: "Handle an empty queue", priority: "high", status: "backlog",
            externalMetadata: .init(providerId: "startrek", externalIssueId: "42", externalIssueKey: "CORE-42",
                externalStatus: .init(key: "open", display: "Open"),
                externalCreator: .init(id: "uid-42", login: "alice.dev", displayName: "Alice"),
                externalAssigneeIdentity: .init(id: "uid-55", login: "bob"), externalQueue: "CORE", externalIssueType: "bug", externalPriorityKey: "critical"),
            tags: ["ios"])
    }

    @Test
    func authorsMatchStableIdentifiersAndNeverDisplayNames() {
        let task = importedTask()
        #expect(TaskPickupCondition(field: .author, values: [" ALICE.DEV "]).matches(task))
        #expect(TaskPickupCondition(field: .author, values: ["uid-42"]).matches(task))
        #expect(!TaskPickupCondition(field: .author, values: ["Alice"]).matches(task))
        #expect(!TaskPickupCondition(field: .author, operation: .contains, values: ["alice"]).isValid)
    }

    @Test
    func combinesConditionsAndPreservesExclusions() {
        let task = importedTask()
        let author = TaskPickupCondition(field: .author, values: ["alice.dev", "someone-else"])
        let queue = TaskPickupCondition(field: .queue, values: ["MOBILE"])
        #expect(!ProjectTaskPickupRules(conditions: [author, queue]).matches(task))
        #expect(ProjectTaskPickupRules(matchMode: .any, conditions: [author, queue]).matches(task))
        #expect(TaskPickupCondition(field: .tag, operation: .notOneOf, values: ["manual"]).matches(task))
        #expect(!TaskPickupCondition(field: .tag, operation: .notOneOf, values: ["ios"]).matches(task))
        var untagged = task
        untagged.tags = []
        #expect(TaskPickupCondition(field: .tag, operation: .notOneOf, values: ["manual"]).matches(untagged))
    }

    @Test
    func matchesImportedAndLocalFields() {
        let task = importedTask()
        for (field, value) in [(TaskPickupField.assignee, "bob"), (.queue, "core"), (.issueType, "bug"), (.priority, "critical"), (.priority, "high"), (.externalStatus, "open"), (.source, "startrek")] {
            #expect(TaskPickupCondition(field: field, values: [value]).matches(task))
        }
        #expect(TaskPickupCondition(field: .title, operation: .contains, values: ["iOS"]).matches(task))
        #expect(TaskPickupCondition(field: .description, operation: .contains, values: ["empty queue"]).matches(task))
        var local = task
        local.externalMetadata = nil
        local.createdBy = "local-user"
        #expect(TaskPickupCondition(field: .author, values: ["local-user"]).matches(local))
        #expect(TaskPickupCondition(field: .source, values: ["local"]).matches(local))
    }

    @Test
    func legacyMetadataAndSettingsRemainReadableAndFailClosed() throws {
        let settings = try JSONDecoder().decode(ProjectAutopilotSettings.self, from: Data(#"{"enabled":true,"includedTags":["ios"]}"#.utf8))
        #expect(settings.pickupRules.conditions.isEmpty)
        #expect(settings.includedTags == ["ios"])
        var task = importedTask()
        task.externalMetadata = try JSONDecoder().decode(TaskExternalMetadata.self, from: Data(#"{"providerId":"startrek","externalIssueKey":"CORE-42"}"#.utf8))
        task.createdBy = "alice.dev"
        #expect(!TaskPickupCondition(field: .author, values: ["alice.dev"]).matches(task))
        #expect(!TaskPickupCondition(field: .author, operation: .notOneOf, values: ["bob"]).matches(task))
        #expect(TaskPickupCondition(field: .author, operation: .isNotSet).matches(task))
        let metadata = try JSONDecoder().decode(TaskExternalMetadata.self, from: JSONEncoder().encode(importedTask().externalMetadata))
        #expect(metadata.externalCreator?.login == "alice.dev")
        #expect(metadata.externalQueue == "CORE")
    }

    @Test
    func invalidAlternativeDoesNotBroadenAnAnyRule() {
        let rules = ProjectTaskPickupRules(matchMode: .any, conditions: [
            .init(field: .author, values: ["alice.dev"]), .init(field: .queue, values: [" "])
        ])
        #expect(!rules.isValid)
        #expect(!rules.matches(importedTask()))
    }

    @Test
    func trustedAuthorsUseTheTrackerCreator() async {
        let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
        let task = importedTask()
        var project = ProjectRecord(id: "pickup", name: "Pickup", description: "", channels: [], tasks: [task],
            autopilotSettings: .init(enabled: true, trustedAuthors: [" alice.dev "]))
        #expect(await service.isEligibleAutopilotRoot(project: project, task: task))
        project.autopilotSettings.pickupRules = .init(conditions: [.init(field: .queue, values: ["OTHER"])])
        #expect(await !service.isEligibleAutopilotRoot(project: project, task: task))
    }

    @Test
    func readyTasksCannotBypassRulesWhenAutopilotIsOff() async throws {
        let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
        var task = importedTask()
        task.status = "ready"
        var project = ProjectRecord(id: "pickup", name: "Pickup", description: "", channels: [], tasks: [task])
        project.autopilotSettings.pickupRules = .init(conditions: [.init(field: .author, values: ["bob"])])
        await service.store.saveProject(project)
        await service.handleTaskBecameReady(projectID: project.id, taskID: task.id)
        let updated = try await service.getProject(id: project.id)
        #expect(updated.tasks.first?.status == "ready")
        #expect(updated.tasks.first?.claimedAgentId == nil)
        #expect(await service.listTaskComments(projectID: project.id, taskID: task.id).isEmpty)
    }

    @Test
    func generatedChildrenInheritRootAdmissionAndFreshPolicyIsUsed() async {
        let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
        let root = importedTask()
        var child = ProjectTask(id: "CHILD-1", title: "Implementation", description: "", priority: "medium", status: "ready", parentTaskId: root.id, createdBy: "autopilot")
        var project = ProjectRecord(id: "pickup", name: "Pickup", description: "", channels: [], tasks: [root, child])
        project.autopilotSettings.pickupRules = .init(conditions: [.init(field: .author, values: ["alice.dev"])])
        #expect(await service.pickupRulesPermit(project: project, task: child))
        await service.store.saveProject(project)
        #expect(await service.currentPickupRulesPermit(projectID: project.id, taskID: child.id))
        project.autopilotSettings.pickupRules.conditions[0].values = ["bob"]
        await service.store.saveProject(project)
        #expect(await !service.currentPickupRulesPermit(projectID: project.id, taskID: child.id))
        child.parentTaskId = child.id
        project.tasks = [child]
        #expect(await !service.pickupRulesPermit(project: project, task: child))
    }

    @Test
    func rulesPersistThroughProjectAPIAndInvalidDraftsAreRejected() async throws {
        let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
        _ = try await service.createProject(.init(id: "pickup", name: "Pickup"))
        let rules = ProjectTaskPickupRules(conditions: [.init(field: .author, values: ["alice.dev"])])
        _ = try await service.updateProject(projectID: "pickup", request: .init(autopilotSettings: .init(pickupRules: rules)))
        let saved = try await service.getProject(id: "pickup")
        #expect(saved.autopilotSettings.pickupRules == rules)
        let router = CoreRouter(service: service)
        let invalid = ProjectUpdateRequest(autopilotSettings: .init(pickupRules: .init(conditions: [.init(field: .author)])))
        let response = await router.handle(method: "PATCH", path: "/v1/projects/pickup", body: try JSONEncoder().encode(invalid))
        #expect(response.status == 400)
    }
}

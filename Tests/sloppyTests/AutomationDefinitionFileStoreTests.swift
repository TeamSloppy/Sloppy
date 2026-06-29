import Foundation
import Testing
@testable import sloppy
import Protocols

@Test
func automationDefinitionStoreCreatesListsUpdatesAndDeletesDefinitions() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = AutomationDefinitionFileStore(workspaceRootURL: root)

    let created = try store.create(
        projectID: "proj",
        request: AutomationDefinitionUpsertRequest(
            name: "PR Review",
            description: "Review PRs",
            enabled: true,
            workflowId: "wf_review",
            repositoryFullName: "TeamSloppy/Sloppy",
            trigger: .init(type: .githubPullRequest, config: ["actions": .array([.string("opened")])]),
            taskMode: .createOrAttach,
            model: nil,
            permissionsScope: .projectVisible
        )
    )

    #expect(created.projectId == "proj")
    #expect(created.version == 1)
    #expect(try store.list(projectID: "proj").map(\.id) == [created.id])

    let updated = try store.update(
        projectID: "proj",
        automationID: created.id,
        request: AutomationDefinitionUpsertRequest(
            name: "PR Review Updated",
            description: "Review PRs again",
            enabled: false,
            workflowId: "wf_review",
            repositoryFullName: "TeamSloppy/Sloppy",
            trigger: .init(type: .githubPullRequest, config: ["actions": .array([.string("synchronize")])]),
            taskMode: .none,
            model: "openai:gpt-5",
            permissionsScope: .projectVisible
        )
    )

    #expect(updated.version == 2)
    #expect(updated.enabled == false)
    #expect(updated.createdAt == created.createdAt)

    try store.delete(projectID: "proj", automationID: created.id)
    #expect(try store.list(projectID: "proj").isEmpty)
}

@Test
func automationDefinitionStoreRejectsInvalidRepository() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = AutomationDefinitionFileStore(workspaceRootURL: root)

    #expect(throws: AutomationDefinitionFileStore.StoreError.invalidPayload) {
        _ = try store.create(
            projectID: "proj",
            request: AutomationDefinitionUpsertRequest(
                name: "Broken",
                enabled: true,
                workflowId: "wf_review",
                repositoryFullName: "invalid-repo",
                trigger: .init(type: .manual),
                taskMode: .none,
                permissionsScope: .private
            )
        )
    }
}

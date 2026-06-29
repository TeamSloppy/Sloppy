import Foundation
import Testing
@testable import Protocols

@Test
func automationDefinitionRoundTrips() throws {
    let now = Date(timeIntervalSince1970: 1_782_000_000)
    let definition = AutomationDefinition(
        id: "auto_pr_review",
        projectId: "proj",
        name: "PR Review Automation",
        description: "Run review workflow on PR open",
        version: 1,
        enabled: true,
        workflowId: "wf_review",
        repositoryFullName: "TeamSloppy/Sloppy",
        trigger: .init(
            type: .githubPullRequest,
            config: [
                "actions": .array([.string("opened"), .string("synchronize")]),
                "branchPatterns": .array([.string("main")])
            ]
        ),
        taskMode: .createOrAttach,
        model: nil,
        permissionsScope: .projectVisible,
        createdAt: now,
        updatedAt: now
    )

    let data = try JSONEncoder().encode(definition)
    let decoded = try JSONDecoder().decode(AutomationDefinition.self, from: data)

    #expect(decoded == definition)
}

@Test
func githubAutomationEventRequestRoundTrips() throws {
    let request = GitHubAutomationEventRequest(
        deliveryId: "delivery-1",
        event: "pull_request",
        action: "opened",
        repositoryFullName: "TeamSloppy/Sloppy",
        payload: [
            "pullRequestNumber": .number(42),
            "title": .string("Fix flaky tests")
        ]
    )

    let data = try JSONEncoder().encode(request)
    let decoded = try JSONDecoder().decode(GitHubAutomationEventRequest.self, from: data)

    #expect(decoded == request)
}

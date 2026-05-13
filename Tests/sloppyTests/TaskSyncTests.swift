import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Protocols
import Logging
import Testing
@testable import sloppy

@Test
func gitHubProjectURLParserAcceptsOrgAndUserProjects() throws {
    let org = try GitHubProjectTaskSyncProvider.parseProjectReference("https://github.com/orgs/AdaEngine/projects/2")
    #expect(org.ownerKind == "orgs")
    #expect(org.owner == "AdaEngine")
    #expect(org.number == 2)

    let user = try GitHubProjectTaskSyncProvider.parseProjectReference("https://github.com/users/vlad/projects/10")
    #expect(user.ownerKind == "users")
    #expect(user.owner == "vlad")
    #expect(user.number == 10)
}

@Test
func gitHubProjectURLParserAcceptsRepositoryProjects() throws {
    let repo = try GitHubProjectTaskSyncProvider.parseProjectReference("https://github.com/AdaEngine/AdaEngine/projects/2")
    #expect(repo.ownerKind == "repos")
    #expect(repo.owner == "AdaEngine")
    #expect(repo.repository == "AdaEngine")
    #expect(repo.number == 2)
}

@Test
func gitHubRepositoryParserAcceptsSlugAndURL() throws {
    let slug = try GitHubProjectTaskSyncProvider.parseRepository("AdaEngine/Sloppy")
    #expect(slug.owner == "AdaEngine")
    #expect(slug.repo == "Sloppy")

    let url = try GitHubProjectTaskSyncProvider.parseRepository("https://github.com/AdaEngine/Sloppy.git")
    #expect(url.slug == "AdaEngine/Sloppy")
    #expect(url.url == "https://github.com/AdaEngine/Sloppy")
}

@Test
func gitHubStatusMappingFallsBackToBasicFlow() {
    #expect(GitHubProjectTaskSyncProvider.mappedGitHubStatus(sloppyStatus: "ready", mappings: [:]) == "Todo")
    #expect(GitHubProjectTaskSyncProvider.mappedGitHubStatus(sloppyStatus: "in_progress", mappings: [:]) == "In Progress")
    #expect(GitHubProjectTaskSyncProvider.mappedGitHubStatus(sloppyStatus: "cancelled", mappings: [:]) == "Done")
    #expect(GitHubProjectTaskSyncProvider.mappedGitHubStatus(sloppyStatus: "ready", mappings: ["ready": "Queued"]) == "Queued")
}

@Test
func gitHubInboundStatusMappingUsesHighestActionableStatus() {
    let status = GitHubProjectTaskSyncProvider.mappedSloppyStatus(
        gitHubStatuses: ["Done", "Blocked", "In Progress"],
        mappings: ["blocked": "blocked", "done": "done", "in progress": "in_progress"]
    )
    #expect(status == "blocked")

    let fallback = GitHubProjectTaskSyncProvider.mappedSloppyStatus(
        gitHubStatuses: ["In Review"],
        mappings: [:]
    )
    #expect(fallback == "needs_review")
}

@Test
func gitHubTaskSyncDiscoveryReadsRepoAndOwnerProjects() async throws {
    let provider = GitHubProjectTaskSyncProvider(transport: { request in
        let object: [String: Any] = [
            "data": [
                "repository": [
                    "projectsV2": [
                        "nodes": [
                            [
                                "id": "P_REPO",
                                "title": "Repo Board",
                                "url": "https://github.com/AdaEngine/Sloppy/projects/1",
                                "fields": [
                                    "nodes": [
                                        [
                                            "name": "Status",
                                            "options": [["name": "Todo"], ["name": "Doing"]]
                                        ]
                                    ]
                                ]
                            ]
                        ]
                    ],
                    "owner": [
                        "projectsV2": [
                            "nodes": [
                                [
                                    "id": "P_ORG",
                                    "title": "Org Board",
                                    "url": "https://github.com/orgs/AdaEngine/projects/2",
                                    "fields": [
                                        "nodes": [
                                            [
                                                "name": "Status",
                                                "options": [["name": "Review"], ["name": "Done"]]
                                            ]
                                        ]
                                    ]
                                ]
                            ]
                        ]
                    ]
                ]
            ]
        ]
        return try mockGitHubResponse(object)
    })

    let discovery = try await provider.discoverProjects(repositoryURL: "AdaEngine/Sloppy", token: "token")
    #expect(discovery.repository.slug == "AdaEngine/Sloppy")
    #expect(discovery.projects.map(\.title) == ["Org Board", "Repo Board"])
    #expect(discovery.projects.map(\.tag).contains("gh:org_board"))
    #expect(discovery.statusOptions == ["Doing", "Done", "Review", "Todo"])
}

@Test
func gitHubTaskImportMergesSameIssueAcrossProjectsAndSkipsDrafts() async throws {
    let provider = GitHubProjectTaskSyncProvider(transport: { request in
        let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
        let variables = body?["variables"] as? [String: Any]
        let projectId = variables?["projectId"] as? String
        let title = projectId == "P_ONE" ? "Roadmap" : "Bugs"
        let status = projectId == "P_ONE" ? "In Progress" : "Blocked"
        let object: [String: Any] = [
            "data": [
                "node": [
                    "items": [
                        "pageInfo": ["hasNextPage": false, "endCursor": NSNull()],
                        "nodes": [
                            [
                                "id": "ITEM_\(projectId ?? "UNKNOWN")",
                                "fieldValues": [
                                    "nodes": [
                                        [
                                            "name": status,
                                            "field": ["name": "Status"]
                                        ]
                                    ]
                                ],
                                "content": [
                                    "id": "ISSUE_1",
                                    "number": 42,
                                    "title": "Merged issue",
                                    "body": "Issue body",
                                    "url": "https://github.com/AdaEngine/Sloppy/issues/42",
                                    "repository": [
                                        "owner": ["login": "AdaEngine"],
                                        "name": "Sloppy"
                                    ]
                                ]
                            ],
                            [
                                "id": "DRAFT_1",
                                "fieldValues": ["nodes": []]
                            ]
                        ]
                    ]
                ]
            ]
        ]
        _ = title
        return try mockGitHubResponse(object)
    })
    let settings = ProjectTaskSyncSettings(
        enabled: true,
        providerId: "github",
        repositorySlug: "AdaEngine/Sloppy",
        defaultRepo: "AdaEngine/Sloppy",
        inboundStatusMappings: ["in progress": "in_progress", "blocked": "blocked"],
        linkedProjects: [
            ProjectTaskSyncLinkedProject(title: "Roadmap", projectURL: "https://github.com/orgs/AdaEngine/projects/1", projectNodeId: "P_ONE", tag: "gh:roadmap"),
            ProjectTaskSyncLinkedProject(title: "Bugs", projectURL: "https://github.com/orgs/AdaEngine/projects/2", projectNodeId: "P_TWO", tag: "gh:bugs")
        ]
    )

    let imported = try await provider.importTasks(settings: settings, token: "token")
    #expect(imported.count == 1)
    #expect(imported[0].metadata.externalIssueNumber == 42)
    #expect(imported[0].status == "blocked")
    #expect(imported[0].tags == ["gh:bugs", "gh:roadmap", "github"])
    #expect(imported[0].metadata.projectMemberships.count == 2)
}

@Test
func taskSyncRunnerRunsDueSchedules() async throws {
    let counter = CounterActor()
    let runner = TaskSyncRunner(
        logger: .init(label: "test.task-sync.runner"),
        scheduleProvider: {
            [ProjectTaskSyncScheduleEntry(projectId: "sync-project", intervalMinutes: 1, lastRunAt: nil)]
        },
        executor: { projectID in
            await counter.record(projectID)
        }
    )
    await runner.triggerImmediately()
    #expect(await counter.values() == ["sync-project"])
}

private actor CounterActor {
    private var recorded: [String] = []

    func record(_ value: String) {
        recorded.append(value)
    }

    func values() -> [String] {
        recorded
    }
}

private func mockGitHubResponse(_ object: [String: Any]) throws -> (Data, HTTPURLResponse) {
    let data = try JSONSerialization.data(withJSONObject: object)
    let response = HTTPURLResponse(
        url: URL(string: "https://api.github.com/graphql")!,
        statusCode: 200,
        httpVersion: nil,
        headerFields: nil
    )!
    return (data, response)
}

@Test
func taskSyncHMACMatchesKnownVector() {
    let digest = TaskSyncCrypto.hmacSHA256Hex(
        key: Data("key".utf8),
        message: Data("The quick brown fox jumps over the lazy dog".utf8)
    )
    #expect(digest == "f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8")
    #expect(TaskSyncCrypto.verifyGitHubSignature(
        body: Data("The quick brown fox jumps over the lazy dog".utf8),
        secret: "key",
        signatureHeader: "sha256=\(digest)"
    ))
}

@Test
func taskSyncRouterLinksTokenStatusAndDedupesWebhookDelivery() async throws {
    let config = CoreConfig.test
    let service = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let router = CoreRouter(service: service)

    let create = try await service.createProject(ProjectCreateRequest(id: "sync-test", name: "Sync Test"))
    #expect(create.project.id == "sync-test")

    let linkBody = try JSONEncoder().encode(ProjectTaskSyncLinkRequest(
        projectURL: "https://github.com/orgs/AdaEngine/projects/2",
        defaultRepo: "AdaEngine/Sloppy"
    ))
    let linkResponse = await router.handle(method: "POST", path: "/v1/projects/sync-test/task-sync/link", body: linkBody)
    #expect(linkResponse.status == 200)

    let tokenBody = try JSONEncoder().encode(ProjectTaskSyncTokenRequest(token: "ghp_test_token_123456"))
    let tokenResponse = await router.handle(method: "POST", path: "/v1/projects/sync-test/task-sync/token", body: tokenBody)
    #expect(tokenResponse.status == 200)
    let tokenStatus = try JSONDecoder().decode(ProjectTaskSyncTokenStatusResponse.self, from: tokenResponse.body)
    #expect(tokenStatus.hasOverrideToken)
    #expect(tokenStatus.maskedToken == "ghp_...3456")

    let workspace = config.resolvedWorkspaceRootURL(currentDirectory: FileManager.default.currentDirectoryPath)
    let secretURL = workspace
        .appendingPathComponent("auth/task-sync/github", isDirectory: true)
        .appendingPathComponent("sync-test.webhook-secret")
    let secret = try String(contentsOf: secretURL).trimmingCharacters(in: .whitespacesAndNewlines)
    let body = Data(#"{"action":"opened","issue":{"id":1,"node_id":"ISSUE_1","number":12,"html_url":"https://github.com/AdaEngine/Sloppy/issues/12","title":"Issue","body":"Body","state":"open"}}"#.utf8)
    let signature = "sha256=" + TaskSyncCrypto.hmacSHA256Hex(key: Data(secret.utf8), message: body)
    let headers = [
        "X-GitHub-Delivery": "delivery-1",
        "X-GitHub-Event": "issues",
        "X-Hub-Signature-256": signature
    ]

    let webhookResponse = await router.handle(method: "POST", path: "/v1/task-sync/github/webhook", body: body, headers: headers)
    #expect(webhookResponse.status == 200)
    let duplicateResponse = await router.handle(method: "POST", path: "/v1/task-sync/github/webhook", body: body, headers: headers)
    #expect(duplicateResponse.status == 200)
    let duplicate = try JSONDecoder().decode(TaskSyncWebhookResponse.self, from: duplicateResponse.body)
    #expect(duplicate.duplicate)
}

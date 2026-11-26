import Foundation
import PluginSDK
import Protocols
import Testing
@testable import sloppy

@Suite("Pull request automation")
struct PullRequestAutomationTests {
    @Test func pollKeepsLinkedChatAndAcceptsRepeatedEventOnce() async throws {
        let service = CoreService(config: .test)
        let root = await service.workspaceRootURL
        let provider = FixturePullRequestSource()
        await service.registerSourceControlProvider(provider)
        do {
            let agent = try await service.createAgent(.init(id: "pr-agent", displayName: "PR Agent", role: "Test"))
            let project = try await service.createProject(.init(
                id: "pr-project", name: "PR Project", repoPath: root.path, sourceControlProviderId: provider.id
            )).project
            let existing = try await service.createAgentSession(
                agentID: agent.id, request: .init(title: "Current PR", separateChat: true, projectId: project.id)
            )
            let links = CodeReviewSessionStore(url: root.appendingPathComponent("code-review-sessions.json"))
            try links.link(provider.reference, session: existing)
            _ = try await service.configurePullRequestAutomation(
                projectID: project.id,
                settings: .init(enabled: true, agentId: agent.id, account: "me", kinds: [.feedbackReceived])
            )
            await service.runPullRequestAutomations(now: Date().addingTimeInterval(60))
            await service.runPullRequestAutomations(now: Date().addingTimeInterval(180))
            let status = try await service.pullRequestAutomationStatus(projectID: project.id)
            #expect(status?.latestSession?.sessionId == existing.id)
            #expect(status?.pendingEvents == 0)
            #expect(status?.lastError == nil)
            let detail = try await service.getAgentSession(agentID: agent.id, sessionID: existing.id)
            #expect(detail.events.filter { $0.message?.userId == "pull-request-automation" }.count == 1)
        } catch {
            await service.shutdownChannelPlugins()
            try? FileManager.default.removeItem(at: root)
            throw error
        }
        await service.shutdownChannelPlugins()
        try? FileManager.default.removeItem(at: root)
    }

    @Test func githubRejectsIssueNoiseAndCollapsesRedelivery() throws {
        let raw = """
        {"action":"created","repository":{"full_name":"Team/Repo"},"sender":{"login":"reviewer"},
         "issue":{"number":45,"title":"Fix","html_url":"https://github.com/team/repo/pull/45",
         "state":"open","user":{"login":"me"},"pull_request":{}},
         "comment":{"id":27,"body":"Please add a test","user":{"login":"reviewer"}}}
        """
        let payload = try JSONDecoder().decode(GitHubPullRequestEvents.self, from: Data(raw.utf8))
        let settings = PullRequestAutomationSettings(
            enabled: true, agentId: "agent", account: "me", kinds: [.feedbackReceived], githubRepository: "team/repo"
        )
        let event = try #require(payload.event(type: "issue_comment", deliveryID: "one", settings: settings))
        let redelivery = payload.event(type: "issue_comment", deliveryID: "two", settings: settings)
        #expect(event == redelivery)
        #expect(event.review.reviewId == "github:Team/Repo#45")
        #expect(event.comment?.id == "github-issue-comment-27")
        #expect(payload.event(type: "issues", deliveryID: "one", settings: settings) == nil)
    }
}

private struct FixturePullRequestSource: SourceControlPullRequestProvider {
    let id = "fixture-source"
    let capabilities: Set<SourceControlCapability> = [.pullRequestEvents, .pullRequestContext]
    let reference = CodeReviewReference(providerId: "fixture-review", reviewId: "45", repository: "repo")

    func pollPullRequestEvents(_ query: PullRequestEventQuery) async throws -> PullRequestEventPage {
        .init(events: [.init(
            id: "comment-1", kind: .feedbackReceived, review: reference, title: "Fix",
            url: "https://example.test/pr/45", comment: .init(id: "1", body: "Please add a test")
        )], nextCursor: .string("cursor"))
    }

    func getPullRequestContext(_ request: PullRequestContextRequest) async throws -> CodeReviewDetail {
        .init(item: .init(id: reference.reviewId, providerId: reference.providerId, providerName: "Fixture",
                         repository: reference.repository, title: "Fix", url: "https://example.test/pr/45"))
    }
}

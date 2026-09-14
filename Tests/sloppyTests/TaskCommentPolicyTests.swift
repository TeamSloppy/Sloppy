import Foundation
import PluginSDK
import Protocols
import Testing
@testable import sloppy

@Suite
struct TaskCommentPolicyTests {
    @Test
    func legacyCommentsAndRequestsRemainReadable() throws {
        let decoder = JSONDecoder()
        let system = try decoder.decode(TaskComment.self, from: Data(#"{"id":"old","taskId":"TASK-1","content":"old event","authorActorId":"system","isAgentReply":false,"createdAt":0}"#.utf8))
        #expect(system.kind == nil)
        #expect(system.effectiveKind == .technical)
        let request = try decoder.decode(TaskCommentCreateRequest.self, from: Data(#"{"content":"human comment","authorActorId":"user"}"#.utf8))
        #expect(request.kind == nil)
        for kind in [TaskCommentKind.technical, .result, .actionRequired, .userComment] {
            var comment = system
            comment.kind = kind
            let decoded = try decoder.decode(TaskComment.self, from: JSONEncoder().encode(comment))
            #expect(decoded.effectiveKind == kind)
        }
    }

    @Test
    func technicalCommentsStayLocalAndHumanTextIsNotClassifiedByKeywords() async throws {
        let (service, provider) = await fixture(status: .inProgress)
        _ = await service.reclaimStaleProjectTaskClaims(staleAfter: 0)
        #expect(await service.listTaskComments(projectID: "comment-policy", taskID: "TASK-1").isEmpty)
        await service.appendSystemTaskComment(projectID: "comment-policy", taskID: "TASK-1", content: "Task flow problem: Worker timed out after 801s")
        await service.appendAutoReviewTaskComment(projectID: "comment-policy", taskID: "TASK-1", artifactPath: nil)
        #expect(await provider.delivered().isEmpty)
        let local = await service.listTaskComments(projectID: "comment-policy", taskID: "TASK-1")
        #expect(local.count == 2)
        #expect(local.allSatisfy { $0.effectiveKind == .technical })

        _ = await service.addTaskComment(projectID: "comment-policy", taskID: "TASK-1", request: .init(
            content: "Worker timed out after 801s — please investigate this", authorActorId: "user"
        ))
        #expect(await provider.delivered().count == 1)
    }

    @Test
    func completionAndSystemArtifactsArePublishedAsResults() async throws {
        let (service, provider) = await fixture()
        await service.appendExecutorCompletionComment(
            projectID: "comment-policy", taskID: "TASK-1",
            completionNote: "Fixed the filter. PR: https://example.com/pr/1. Regression test passed.",
            authorActorId: "agent-dev"
        )
        let artifactID = "result-artifact"
        await service.store.persistArtifact(id: artifactID, content: "Changed filter.swift; verified empty queue behavior.")
        let event = EventEnvelope(
            messageType: .workerCompleted, channelId: "channel", taskId: "TASK-1",
            payload: .object(["artifactId": .string(artifactID)])
        )
        _ = await service.persistWorkerArtifactForProjectTask(projectID: "comment-policy", taskID: "TASK-1", event: event)
        let delivered = await provider.delivered()
        #expect(delivered.count == 2)
        #expect(delivered.allSatisfy { $0.effectiveKind == .result })
        #expect(delivered.last?.content == "Changed filter.swift; verified empty queue behavior.")
    }

    @Test
    func clarificationPublishesTheQuestionAndOptions() async throws {
        let (service, provider) = await fixture()
        _ = try await service.createTaskClarification(projectID: "comment-policy", taskID: "TASK-1", request: .init(
            questionText: "Which queue should be included?",
            options: [.init(id: "one", label: "Only the current queue")]
        ))
        let delivered = await provider.delivered()
        #expect(delivered.count == 1)
        #expect(delivered.first?.effectiveKind == .actionRequired)
        #expect(delivered.first?.content.contains("Which queue should be included?") == true)
        #expect(delivered.first?.content.contains("Only the current queue") == true)
        #expect(delivered.first?.content.contains("in Sloppy") == true)
    }

    @Test
    func taskStatusUpdatePublishesTheSpecificBlocker() async throws {
        let (service, provider) = await fixture()
        _ = try await service.updateProjectTask(projectID: "comment-policy", taskID: "TASK-1", request: .init(
            status: "blocked", completionNote: "Repository access is missing. Grant read access to continue.", changedBy: "agent-dev"
        ))
        let delivered = await provider.delivered()
        #expect(delivered.count == 1)
        #expect(delivered.first?.effectiveKind == .actionRequired)
        #expect(delivered.first?.content == "Repository access is missing. Grant read access to continue.")
    }

    @Test
    func agentRoutedClarificationDoesNotNotifyTheUser() async throws {
        let (service, provider) = await fixture()
        var project = try await service.getProject(id: "comment-policy")
        project.taskLoopMode = .agent
        await service.store.saveProject(project)
        _ = try await service.createTaskClarification(projectID: "comment-policy", taskID: "TASK-1", request: .init(questionText: "Internal routing question"))
        #expect(await provider.delivered().isEmpty)
    }

    @Test
    func exhaustedLaunchAttemptsPublishOneActionableReport() async throws {
        let (service, provider) = await fixture(status: .ready)
        _ = try await service.recordProjectTaskSpawnFailure(projectID: "comment-policy", taskID: "TASK-1", error: "Missing agent profile", failureLimit: 2)
        #expect(await provider.delivered().isEmpty)
        for _ in 0..<3 {
            _ = try await service.recordProjectTaskSpawnFailure(projectID: "comment-policy", taskID: "TASK-1", error: "Missing agent profile", failureLimit: 2)
        }
        let delivered = await provider.delivered()
        #expect(delivered.count == 1)
        #expect(delivered.first?.effectiveKind == .actionRequired)
        #expect(delivered.first?.content.contains("Missing agent profile") == true)
        #expect(delivered.first?.content.contains("return the task to ready") == true)
    }

    @Test
    func terminalWorkerFailurePublishesOnceWithTheNextAction() async throws {
        let (service, provider) = await fixture(status: .inProgress)
        let event = EventEnvelope(messageType: .workerFailed, channelId: "channel", taskId: "TASK-1", payload: .object([:]))
        for _ in 0..<2 {
            await service.syncTaskStatusFromWorkerEvent(event: event, nextStatus: "backlog", failureNote: "Worker timed out after 801s")
        }
        let delivered = await provider.delivered()
        #expect(delivered.count == 1)
        #expect(delivered.first?.effectiveKind == .actionRequired)
        #expect(delivered.first?.content.contains("Worker timed out after 801s") == true)
        #expect(delivered.first?.content.contains("return the task to ready") == true)
    }

    @Test
    func simultaneousReportsDeduplicateWithoutLosingLocalComments() async throws {
        let (service, provider) = await fixture()
        async let first: Void = service.appendSystemTaskComment(projectID: "comment-policy", taskID: "TASK-1", content: "Need repository access", kind: .actionRequired)
        async let second: Void = service.appendSystemTaskComment(projectID: "comment-policy", taskID: "TASK-1", content: "Need repository access", kind: .actionRequired)
        _ = await (first, second)
        #expect(await provider.delivered().count == 1)
        let comments = await service.listTaskComments(projectID: "comment-policy", taskID: "TASK-1")
        #expect(comments.count == 2)
        #expect(comments.allSatisfy { $0.externalMetadata?.externalCommentId != nil })
        for comment in comments {
            await service.mirrorOutboundCommentIfNeeded(projectID: "comment-policy", taskID: "TASK-1", commentID: comment.id)
        }
        #expect(await provider.delivered().count == 1)
        await service.appendSystemTaskComment(projectID: "comment-policy", taskID: "TASK-1", content: "Retry event")
        await service.appendSystemTaskComment(projectID: "comment-policy", taskID: "TASK-1", content: "Need repository access", kind: .actionRequired)
        #expect(await provider.delivered().count == 1)
        await service.appendSystemTaskComment(projectID: "comment-policy", taskID: "TASK-1", content: "Access restored; tests passed", kind: .result)
        #expect(await provider.delivered().count == 2)
    }

    @Test
    func failedDeliveryCanRetryAndExistingExclusionsRemainLocal() async throws {
        let (service, provider) = await fixture()
        await provider.failNextDelivery()
        let report = await service.addTaskComment(projectID: "comment-policy", taskID: "TASK-1", request: .init(content: "Verified result", authorActorId: "system", kind: .result))
        #expect(await provider.delivered().isEmpty)
        await service.mirrorOutboundCommentIfNeeded(projectID: "comment-policy", taskID: "TASK-1", commentID: report.id)
        #expect(await provider.delivered().count == 1)

        let excluded = [
            TaskComment(id: "imported", taskId: "TASK-1", content: "Imported", authorActorId: "external", externalMetadata: .init(providerId: "startrek", externalCommentId: "remote", origin: "startrek")),
            TaskComment(id: "reply", taskId: "TASK-1", content: "Agent reply", authorActorId: "agent", isAgentReply: true),
            TaskComment(id: "mention", taskId: "TASK-1", content: "Mention", authorActorId: "user", mentionedActorId: "agent"),
            TaskComment(id: "legacy-system", taskId: "TASK-1", content: "Old technical event", authorActorId: "system")
        ]
        let existing = await service.listTaskComments(projectID: "comment-policy", taskID: "TASK-1")
        await service.saveTaskComments(existing + excluded, projectID: "comment-policy", taskID: "TASK-1")
        for comment in excluded {
            await service.mirrorOutboundCommentIfNeeded(projectID: "comment-policy", taskID: "TASK-1", commentID: comment.id)
        }
        #expect(await provider.delivered().count == 1)
    }

    private func fixture(status: ProjectTaskStatus = .backlog) async -> (CoreService, CommentPolicyProvider) {
        let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
        let provider = CommentPolicyProvider()
        await service.registerTaskSyncProvider(provider)
        let task = ProjectTask(
            id: "TASK-1", title: "Filter fix", description: "", priority: "medium", status: status.rawValue,
            externalMetadata: .init(providerId: "startrek", externalIssueId: "42", externalIssueKey: "TEST-42", origin: "startrek")
        )
        var project = ProjectRecord(id: "comment-policy", name: "Comment policy", description: "", channels: [], tasks: [task])
        project.taskLoopMode = .human
        project.taskSyncSettings = .init(enabled: true, providerId: "startrek")
        await service.store.saveProject(project)
        return (service, provider)
    }
}

private actor CommentPolicyProvider: TaskSyncProvider {
    nonisolated let id = "startrek"
    private var comments: [TaskComment] = []
    private var shouldFail = false

    nonisolated func parseProjectURL(_ rawURL: String) throws -> TaskSyncProjectDescriptor {
        .init(providerId: id, projectURL: rawURL)
    }

    func resolveProject(url: String, token: String?, defaultRepo: String?) async throws -> TaskSyncProjectDescriptor {
        .init(providerId: id, projectURL: url)
    }

    func importTasks(settings: ProjectTaskSyncSettings, token: String?) async throws -> [TaskSyncExternalTask] { [] }

    func createOrUpdateTask(_ task: ProjectTask, settings: ProjectTaskSyncSettings, token: String?) async throws -> TaskExternalMetadata {
        task.externalMetadata ?? .init(providerId: id)
    }

    func mirrorComment(_ comment: TaskComment, task: ProjectTask, settings: ProjectTaskSyncSettings, token: String?) async throws -> TaskExternalMetadata {
        if shouldFail {
            shouldFail = false
            throw URLError(.cannotConnectToHost)
        }
        comments.append(comment)
        return .init(providerId: id, externalCommentId: "remote-\(comments.count)", origin: "sloppy")
    }

    func delivered() -> [TaskComment] { comments }
    func failNextDelivery() { shouldFail = true }
}

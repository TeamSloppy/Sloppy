import Foundation
import Testing
import Protocols
@testable import sloppy

@Suite("Workflow environment binding", .timeLimit(.minutes(1)))
struct WorkflowEnvironmentTests {
    @Test
    func taskAndWorktreeStayPinnedAcrossApprovalAndProjectChanges() async throws {
        let config = CoreConfig.test
        let service = CoreService(config: config)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try git(["init", "-b", "main"], root)
        try git(["-c", "user.name=Test", "-c", "user.email=test@local", "commit", "--allow-empty", "-m", "Initial"], root)
        let projectID = "env-\(UUID().uuidString)"
        _ = try await service.createProject(.init(id: projectID, name: "Environment", description: "", channels: [], repoPath: root.path))
        let project = try await service.createProjectTask(projectID: projectID, request: .init(title: "Original task", description: "Original body"))
        let task = try #require(project.tasks.first)
        let graph = try await service.createWorkflowDefinition(projectID: projectID, request: graph())
        let paused = try await service.startWorkflowRun(projectID: projectID, workflowID: graph.id,
            request: .init(taskId: task.id, startedBy: "owner", background: false,
                environment: .init(mode: .newWorktree, setupCommand: "printf x >> setup-marker")))
        #expect(paused.run.status == .waitingForHuman)
        let binding = try #require(paused.run.environment)
        #expect(binding.workingDirectory != root.path)
        #expect(binding.preparation == .ready)
        let action = try #require(paused.pendingActions.first)
        _ = try await service.updateProjectTask(projectID: projectID, taskID: task.id, request: .init(title: "Changed task", changedBy: "owner"))
        await service.shutdownChannelPlugins()
        let restarted = CoreService(config: config)
        defer { Task { await restarted.shutdownChannelPlugins() } }
        let finished = try await restarted.resolveWorkflowPendingAction(projectID: projectID, actionID: action.id,
            request: .init(decision: .approved, resolvedBy: "owner"))
        #expect(finished.run.status == .completed)
        #expect(finished.run.environment == binding)
        #expect(finished.steps.first { $0.nodeId == "work" }?.output["stdout"] == .string("\(binding.workingDirectory):Original task"))
        #expect(try String(contentsOf: URL(fileURLWithPath: binding.workingDirectory).appendingPathComponent("setup-marker"), encoding: .utf8) == "x")
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("setup-marker").path))
    }

    @Test
    func missingTaskAndUnrelatedCheckoutAreRejected() async throws {
        let service = CoreService(config: .test)
        defer { Task { await service.shutdownChannelPlugins() } }
        let projectID = "invalid-env-\(UUID().uuidString)"
        _ = try await service.createProject(.init(id: projectID, name: "Environment", description: "", channels: []))
        let graph = try await service.createWorkflowDefinition(projectID: projectID, request: graph())
        await #expect(throws: (any Error).self) {
            _ = try await service.startWorkflowRun(projectID: projectID, workflowID: graph.id,
                request: .init(taskId: "missing", startedBy: "owner"))
        }
        await #expect(throws: (any Error).self) {
            _ = try await service.startWorkflowRun(projectID: projectID, workflowID: graph.id,
                request: .init(startedBy: "owner", environment: .init(mode: .existingWorktree, path: "/tmp")))
        }
        #expect(await service.listWorkflowRuns(projectID: projectID).isEmpty)
    }

    @Test
    func interruptedSetupIsBlockedWithoutRepeatingTheCommand() async throws {
        let config = CoreConfig.test
        let service = CoreService(config: config)
        let projectID = "setup-\(UUID().uuidString)"
        _ = try await service.createProject(.init(id: projectID, name: "Environment", description: "", channels: []))
        let definition = try await service.createWorkflowDefinition(projectID: projectID, request: graph())
        let request = WorkflowRunCreateRequest(startedBy: "owner", environment: .init(setupCommand: "printf x >> marker"))
        var binding = try await service.planWorkflowEnvironment(projectID: projectID, runID: "run-setup", request: request)
        binding.preparation = .setup
        let run = WorkflowRun(id: "run-setup", workflowId: definition.id, workflowVersion: 1, projectId: projectID,
            status: .queued, startedBy: "owner", environment: binding)
        try await service.workflowExecutionFiles.save(.init(definition: definition, originalInput: [:], run: run))
        await service.shutdownChannelPlugins()
        let restarted = CoreService(config: config)
        defer { Task { await restarted.shutdownChannelPlugins() } }
        var detail = try await restarted.getWorkflowRunDetail(projectID: projectID, runID: run.id)
        for _ in 0..<300 where detail.run.status != .blocked {
            try await Task.sleep(for: .milliseconds(20))
            detail = try await restarted.getWorkflowRunDetail(projectID: projectID, runID: run.id)
        }
        #expect(detail.run.status == .blocked)
        #expect(!FileManager.default.fileExists(atPath: URL(fileURLWithPath: binding.workingDirectory).appendingPathComponent("marker").path))
    }

    @Test(arguments: [WorkflowEnvironmentMode.taskWorktree, .existingWorktree])
    func selectsExistingTaskOrExplicitWorktree(mode: WorkflowEnvironmentMode) async throws {
        let service = CoreService(config: .test)
        defer { Task { await service.shutdownChannelPlugins() } }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try git(["init", "-b", "main"], root)
        try git(["-c", "user.name=Test", "-c", "user.email=test@local", "commit", "--allow-empty", "-m", "Initial"], root)
        let id = "existing-env-\(UUID().uuidString)"
        _ = try await service.createProject(.init(id: id, name: "Existing checkout", description: "", channels: [], repoPath: root.path))
        var project = try await service.createProjectTask(projectID: id, request: .init(title: "Task checkout"))
        let task = try #require(project.tasks.first)
        let checkout = try await service.createTUIBackgroundWorktree(projectID: id, taskID: task.id)
        project.tasks[0].worktreeBranch = checkout.branchName
        await service.store.saveProject(project)
        let definition = try await service.createWorkflowDefinition(projectID: id, request: graph())
        let paused = try await service.startWorkflowRun(projectID: id, workflowID: definition.id,
            request: .init(taskId: task.id, startedBy: "owner", background: false,
                environment: .init(mode: mode, path: mode == .existingWorktree ? checkout.worktreePath : nil)))
        #expect(paused.run.status == .waitingForHuman)
        let path = canonicalWorkflowDirectory(checkout.worktreePath)
        #expect(paused.run.environment?.workingDirectory == path)
        #expect(paused.run.environment?.branch == checkout.branchName)
        let action = try #require(paused.pendingActions.first)
        let completed = try await service.resolveWorkflowPendingAction(projectID: id, actionID: action.id,
            request: .init(decision: .approved, resolvedBy: "owner"))
        #expect(completed.run.status == .completed)
        #expect(completed.steps.first { $0.nodeId == "work" }?.output["stdout"] == .string("\(path):Task checkout"))
    }

    @Test
    func nativeAgentKeepsTaskWorktreeWhileAnsweringAfterRestart() async throws {
        let config = CoreConfig.test
        let service = CoreService(config: config)
        await service.overrideModelProviderForTests(WorkflowModelProvider(probe: WorkflowModelProbe(requestsInput: true)), defaultModel: "mock:test-model")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try git(["init", "-b", "main"], root)
        try git(["-c", "user.name=Test", "-c", "user.email=test@local", "commit", "--allow-empty", "-m", "Initial"], root)
        let id = "native-env-\(UUID().uuidString)"
        _ = try await service.createProject(.init(id: id, name: "Native environment", description: "", channels: [], repoPath: root.path))
        _ = try await service.createAgent(.init(id: id, displayName: "Worker", role: "Assistant"))
        let project = try await service.createProjectTask(projectID: id, request: .init(title: "Pinned native task"))
        let task = try #require(project.tasks.first)
        let harness = WorkflowCompletionHarness(service: service, config: config, project: id, agent: id)
        let definition = try await harness.define([
            .init(id: "agent", type: .agentStep, title: "Agent", laneId: "s", config: ["agentId": .string(id), "mode": .string("plan"), "prompt": .string("Work on {{task.title}}")]),
            harness.shell("after", "pwd")
        ])
        let paused = try await service.startWorkflowRun(projectID: id, workflowID: definition.id,
            request: .init(taskId: task.id, startedBy: "owner", background: false, environment: .init(mode: .newWorktree)))
        #expect(paused.run.status == .waitingForAgent)
        let step = try #require(paused.steps.first { $0.nodeId == "agent" })
        let session = try #require(step.output["sessionId"]?.asString)
        let input = try #require(try await service.getAgentSession(agentID: id, sessionID: session).events.compactMap(\.inputRequest).last)
        let path = try #require(paused.run.environment?.workingDirectory)
        #expect(path != canonicalWorkflowDirectory(root.path))
        await service.shutdownChannelPlugins()
        let restarted = CoreService(config: config)
        await restarted.overrideModelProviderForTests(WorkflowModelProvider(probe: WorkflowModelProbe()), defaultModel: "mock:test-model")
        defer { Task { await restarted.shutdownChannelPlugins() } }
        await restarted.waitForStartup()
        let context = await restarted.toolContextForSession(sessionID: session, sessionTitle: "Agent", projectID: id, taskID: task.id)
        #expect(context.workingDirectory == path)
        _ = try await restarted.answerAgentPlanInput(agentID: id, sessionID: session, requestID: input.id,
            payload: .init(status: .answered, answers: [.init(questionId: "choice", selectedOptionId: "yes")], userId: "owner"))
        let finished = try await harness.wait(paused.run.id, service: restarted) { $0.run.status == .completed }
        #expect(finished.steps.first { $0.nodeId == "after" }?.output["stdout"]?.asString?.trimmingCharacters(in: .whitespacesAndNewlines) == path)
        #expect(finished.steps.first { $0.nodeId == "agent" }?.output["sessionId"] == .string(session))
    }

    private func graph() -> WorkflowDefinitionUpsertRequest {
        .init(name: "Environment", lanes: [.init(id: "s", title: "System", kind: .system)], nodes: [
            .init(id: "start", type: .trigger, title: "Start", laneId: "s"),
            .init(id: "approve", type: .humanApproval, title: "Approve", laneId: "s"),
            .init(id: "work", type: .toolCheck, title: "Work", laneId: "s", config: ["blockKind": .string("bash"), "command": .string("printf '%s:%s' \"$PWD\" '{{task.title}}'")]),
            .init(id: "done", type: .end, title: "Done", laneId: "s")
        ], edges: [.init(id: "1", sourceNodeId: "start", targetNodeId: "approve"),
                   .init(id: "2", sourceNodeId: "approve", targetNodeId: "work"), .init(id: "3", sourceNodeId: "work", targetNodeId: "done")])
    }

    private func git(_ arguments: [String], _ root: URL) throws {
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + arguments; process.currentDirectoryURL = root
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try process.run(); process.waitUntilExit(); #expect(process.terminationStatus == 0)
    }
}

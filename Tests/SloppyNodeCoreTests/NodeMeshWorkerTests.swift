import Foundation
import Testing
@testable import SloppyNodeCore

@Suite("NodeMeshWorker")
struct NodeMeshWorkerTests {
    @Test("worker returns a new-file diff without committing or touching source checkout")
    func workerCreatesTaskBranchCommitsCommandChangesAndReportsReviewMetadata() async throws {
        let repoURL = try makeRepository()
        let task = MeshTaskRecord(
            id: "mesh_task_123",
            projectId: "sp_mesh",
            title: "Implement remote task dispatch",
            assignedNodeId: "node_worker",
            status: .started
        )
        let project = SharedProjectRecord(
            id: "sp_mesh",
            name: "Mesh Project",
            repoUrl: "git@example.com:mesh.git",
            members: [
                SharedProjectMember(
                    nodeId: "node_worker",
                    localRepoPath: repoURL.path,
                    role: "worker",
                    permissions: MeshPermission.workerDefaults.rawValues
                ),
            ]
        )

        let result = try await NodeMeshWorker.execute(
            task: task,
            project: project,
            nodeId: "node_worker",
            nodeName: "Home Mac",
            commands: ["printf done > result.txt"],
            push: false
        )

        #expect(result.status == .readyForReview)
        #expect(result.branch == "agent/home-mac/mesh-task-123-implement-remote-task-dispatch")
        #expect(result.commit == nil)
        #expect(result.diff.contains("new file mode"))
        #expect(result.commandResults.count == 1)
        #expect(result.commandResults.first?.exitCode == 0)
        #expect(try gitOutput(["branch", "--show-current"], at: repoURL) == "main")
        #expect(try String(contentsOf: URL(fileURLWithPath: result.worktreePath).appendingPathComponent("result.txt"), encoding: .utf8) == "done")
    }

    @Test("isolated worker runs in a task worktree and leaves the shared checkout unchanged")
    func isolatedWorkerRunsInTaskWorktreeAndLeavesSharedCheckoutUnchanged() async throws {
        let repoURL = try makeRepository()
        let originalHead = try gitOutput(["rev-parse", "HEAD"], at: repoURL)
        let task = MeshTaskRecord(
            id: "mesh_task_isolated",
            projectId: "sp_mesh",
            title: "Isolated execution",
            assignedNodeId: "node_worker",
            status: .started
        )
        let project = SharedProjectRecord(
            id: "sp_mesh",
            name: "Mesh Project",
            repoUrl: "git@example.com:mesh.git",
            members: [SharedProjectMember(nodeId: "node_worker", localRepoPath: repoURL.path, role: "worker",
                                          permissions: MeshPermission.workerDefaults.rawValues)]
        )

        let result = try await NodeMeshWorker.execute(
            task: task,
            project: project,
            nodeId: "node_worker",
            nodeName: "Home Mac",
            executor: .autopilot { context in
                #expect(context.localRepoPath != repoURL.path)
                try "isolated".write(to: URL(fileURLWithPath: context.localRepoPath).appendingPathComponent("remote.txt"),
                                     atomically: true, encoding: .utf8)
                return NodeMeshWorkerExecutionSummary(summary: "done")
            },
            isolatedWorktree: true
        )

        #expect(result.status == .readyForReview)
        #expect(result.commit == nil)
        #expect(result.baseRevision == originalHead)
        #expect(result.diff.contains("remote.txt"))
        #expect(try gitOutput(["rev-parse", "HEAD"], at: repoURL) == originalHead)
        #expect(try gitOutput(["status", "--porcelain"], at: repoURL).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: repoURL.appendingPathComponent("remote.txt").path))
    }

    @Test("successful validation without source changes does not require a commit")
    func successfulValidationWithoutChangesDoesNotRequireCommit() async throws {
        let repoURL = try makeRepository()
        let task = MeshTaskRecord(id: "mesh_task_check", projectId: "sp_mesh", title: "Run checks",
                                  assignedNodeId: "node_worker", status: .started)
        let project = SharedProjectRecord(
            id: "sp_mesh", name: "Mesh Project", repoUrl: "git@example.com:mesh.git",
            members: [SharedProjectMember(nodeId: "node_worker", localRepoPath: repoURL.path, role: "worker",
                                          permissions: MeshPermission.workerDefaults.rawValues)]
        )

        let result = try await NodeMeshWorker.execute(
            task: task, project: project, nodeId: "node_worker", nodeName: "Home Mac",
            commands: ["true"], isolatedWorktree: true
        )

        #expect(result.status == .readyForReview)
        #expect(result.commit == nil)
        #expect(try gitOutput(["status", "--porcelain"], at: repoURL).isEmpty)
    }

    @Test("worker can execute through an injected autopilot adapter")
    func workerCanExecuteThroughInjectedAutopilotAdapter() async throws {
        let repoURL = try makeRepository()
        let task = MeshTaskRecord(
            id: "mesh_task_456",
            projectId: "sp_mesh",
            title: "Run autopilot adapter",
            assignedNodeId: "node_worker",
            status: .started
        )
        let project = SharedProjectRecord(
            id: "sp_mesh",
            name: "Mesh Project",
            repoUrl: "git@example.com:mesh.git",
            members: [
                SharedProjectMember(
                    nodeId: "node_worker",
                    actorId: "agent:worker",
                    localRepoPath: repoURL.path,
                    role: "worker",
                    permissions: MeshPermission.workerDefaults.rawValues + [MeshPermission.nodeAgentSpawn.rawValue]
                ),
            ]
        )

        let result = try await NodeMeshWorker.execute(
            task: task,
            project: project,
            nodeId: "node_worker",
            nodeName: "Home Mac",
            executor: .autopilot { context in
                #expect(context.localRepoPath != repoURL.path)
                #expect(context.agentId == "worker")
                try "adapter".write(
                    to: URL(fileURLWithPath: context.localRepoPath).appendingPathComponent("adapter.txt"),
                    atomically: true,
                    encoding: .utf8
                )
                return NodeMeshWorkerExecutionSummary(
                    summary: "Autopilot completed task.",
                    tests: ["swift test --filter Mesh"]
                )
            },
            push: false
        )

        #expect(result.status == .readyForReview)
        #expect(result.summary == "Autopilot completed task.")
        #expect(result.tests == ["swift test --filter Mesh"])
        #expect(result.commit == nil)
        #expect(result.diff.contains("new file mode"))
        #expect(try String(contentsOf: URL(fileURLWithPath: result.worktreePath).appendingPathComponent("adapter.txt"), encoding: .utf8) == "adapter")
    }

    @Test("pinned base and detached worktree never reset an existing task branch")
    func pinnedBaseDoesNotFollowHeadOrResetTaskBranch() async throws {
        let repo = try makeRepository()
        let base = try gitOutput(["rev-parse", "HEAD"], at: repo)
        try "later".write(to: repo.appendingPathComponent("later.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "later.txt"], at: repo)
        try runGit(["-c", "user.name=Tests", "-c", "user.email=test@example.com", "commit", "-m", "Later"], at: repo)
        let head = try gitOutput(["rev-parse", "HEAD"], at: repo)
        let task = MeshTaskRecord(id: "pinned", projectId: "p", title: "Pinned", assignedNodeId: "worker", status: .started)
        let branch = NodeMeshGitPolicy.makeTaskBranchName(nodeName: "Home", taskId: task.id, taskTitle: task.title)
        try runGit(["branch", branch, head], at: repo)
        let project = SharedProjectRecord(id: "p", name: "Project", repoUrl: "unused",
            members: [.init(nodeId: "worker", localRepoPath: repo.path, role: "worker", permissions: MeshPermission.workerDefaults.rawValues)])
        let result = try await NodeMeshWorker.execute(task: task, project: project, nodeId: "worker", nodeName: "Home",
            commands: ["test ! -f later.txt && printf new > new.txt"], baseRevision: base)
        #expect(result.baseRevision == base)
        #expect(result.commit == nil)
        #expect(result.diff.contains("new.txt"))
        #expect(try gitOutput(["rev-parse", branch], at: repo) == head)
        #expect(try gitOutput(["rev-parse", "HEAD"], at: URL(fileURLWithPath: result.worktreePath)) == base)
        #expect(try gitOutput(["branch", "--show-current"], at: URL(fileURLWithPath: result.worktreePath)).isEmpty)
        #expect(try gitOutput(["status", "--porcelain"], at: repo).isEmpty)
    }

    @Test("unsafe checkout and implicit push are rejected before commands")
    func unsafeOptionsAreRejectedBeforeCommands() async throws {
        let repo = try makeRepository()
        let task = MeshTaskRecord(id: "unsafe", projectId: "p", title: "Unsafe", assignedNodeId: "worker", status: .started)
        let project = SharedProjectRecord(id: "p", name: "Project", repoUrl: "unused",
            members: [.init(nodeId: "worker", localRepoPath: repo.path, role: "worker", permissions: MeshPermission.workerDefaults.rawValues)])
        await #expect(throws: NodeMeshWorkerError.unsafeCheckout) {
            try await NodeMeshWorker.execute(task: task, project: project, nodeId: "worker", nodeName: "Home",
                commands: ["touch should-not-exist"], isolatedWorktree: false)
        }
        await #expect(throws: NodeMeshWorkerError.pushRequiresCommit) {
            try await NodeMeshWorker.execute(task: task, project: project, nodeId: "worker", nodeName: "Home",
                commands: ["touch should-not-exist"], push: true)
        }
        #expect(!FileManager.default.fileExists(atPath: repo.appendingPathComponent("should-not-exist").path))
    }

    @Test("large new-file patch drains Git output and oversize patches fail explicitly")
    func largePatchIsCompleteAndOversizePatchFails() async throws {
        let repo = try makeRepository()
        let task = MeshTaskRecord(id: "large", projectId: "p", title: "Large diff", assignedNodeId: "worker", status: .started)
        let project = SharedProjectRecord(id: "p", name: "Project", repoUrl: "unused",
            members: [.init(nodeId: "worker", localRepoPath: repo.path, role: "worker", permissions: MeshPermission.workerDefaults.rawValues)])
        let result = try await NodeMeshWorker.execute(task: task, project: project, nodeId: "worker", nodeName: "Home",
            executor: .autopilot { context in
                try String(repeating: "test-line\n", count: 20000).write(
                    to: URL(fileURLWithPath: context.localRepoPath).appendingPathComponent("large.txt"), atomically: true, encoding: .utf8)
                return .init(summary: "fixture")
            })
        #expect(result.diff.utf8.count > 128 * 1024)
        #expect(result.diff.hasSuffix("+test-line\n"))
        #expect(result.commit == nil)
        try String(repeating: "oversized-line\n", count: 400000).write(
            to: URL(fileURLWithPath: result.worktreePath).appendingPathComponent("too-large.txt"), atomically: true, encoding: .utf8)
        #expect(throws: NodeMeshWorkerError.outputTooLarge) {
            try NodeMeshWorker.resultDiff(at: result.worktreePath, baseRevision: result.baseRevision)
        }
    }

    @Test("detached worktree shares Git config and is not a security boundary")
    func detachedWorktreeStillSharesRepositoryMetadata() async throws {
        let repo = try makeRepository()
        let task = MeshTaskRecord(id: "metadata", projectId: "p", title: "Metadata", assignedNodeId: "worker", status: .started)
        let project = SharedProjectRecord(id: "p", name: "Project", repoUrl: "unused",
            members: [.init(nodeId: "worker", localRepoPath: repo.path, role: "worker", permissions: MeshPermission.workerDefaults.rawValues)])
        let result = try await NodeMeshWorker.execute(task: task, project: project, nodeId: "worker", nodeName: "Home", commands: [])
        // Only a synthetic disposable repository is touched. No host/user repository mutation.
        let mutation = try NodeMeshProcess.run(executable: "/usr/bin/git",
            arguments: ["config", "--local", "mesh.isolation-canary", "shared"], directory: result.worktreePath)
        #expect(mutation.exitCode == 0)
        #expect(try gitOutput(["config", "--local", "mesh.isolation-canary"], at: repo) == "shared")
    }

    private func makeRepository() throws -> URL {
        let repoURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("sloppy-mesh-worker-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: repoURL, withIntermediateDirectories: true)
        try runGit(["init", "-b", "main"], at: repoURL)
        try "ok".write(to: repoURL.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try runGit(["add", "README.md"], at: repoURL)
        try runGit(["-c", "user.name=Sloppy Tests", "-c", "user.email=tests@example.com", "commit", "-m", "Initial"], at: repoURL)
        return repoURL
    }

    private func gitOutput(_ arguments: [String], at directoryURL: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.currentDirectoryURL = directoryURL
        process.arguments = arguments
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func runGit(_ arguments: [String], at directoryURL: URL) throws {
        _ = try gitOutput(arguments, at: directoryURL)
    }
}

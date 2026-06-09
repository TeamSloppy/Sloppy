import Foundation
import Testing
@testable import SloppyNodeCore

@Suite("NodeMeshWorker")
struct NodeMeshWorkerTests {
    @Test("worker creates task branch commits command changes and reports review metadata")
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
        #expect(result.commit?.isEmpty == false)
        #expect(result.commandResults.count == 1)
        #expect(result.commandResults.first?.exitCode == 0)
        #expect(try gitOutput(["branch", "--show-current"], at: repoURL) == result.branch)
        #expect(try String(contentsOf: repoURL.appendingPathComponent("result.txt"), encoding: .utf8) == "done")
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
                #expect(context.localRepoPath == repoURL.path)
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
        #expect(result.commit?.isEmpty == false)
        #expect(try String(contentsOf: repoURL.appendingPathComponent("adapter.txt"), encoding: .utf8) == "adapter")
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

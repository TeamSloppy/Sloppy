import Foundation
import Testing
@testable import SloppyNodeCore

@Suite("NodeMeshGitPolicy")
struct NodeMeshGitPolicyTests {
    @Test("clean repo plans branch per task")
    func cleanRepoPlansBranchPerTask() throws {
        let repoURL = try makeRepository()

        let report = try NodeMeshGitPolicy.check(
            repositoryPath: repoURL.path,
            nodeName: "Home Mac",
            taskId: "mesh_task_123",
            taskTitle: "Implement remote task dispatch!",
            defaultBranch: "main",
            policies: SharedProjectPolicies(branchPerTask: true, directPushToMain: false)
        )

        #expect(report.currentBranch == "main")
        #expect(report.isDirty == false)
        #expect(report.executionBranch == "agent/home-mac/mesh-task-123-implement-remote-task-dispatch")
        #expect(report.canExecute)
    }

    @Test("dirty worktree is blocked when clean tree required")
    func dirtyWorktreeIsBlockedWhenCleanTreeRequired() throws {
        let repoURL = try makeRepository()
        try "dirty".write(to: repoURL.appendingPathComponent("dirty.txt"), atomically: true, encoding: .utf8)

        #expect(throws: NodeMeshGitPolicyError.dirtyWorktree) {
            _ = try NodeMeshGitPolicy.check(
                repositoryPath: repoURL.path,
                nodeName: "Home Mac",
                taskId: "mesh_task_123",
                taskTitle: "Implement remote task dispatch",
                defaultBranch: "main",
                policies: SharedProjectPolicies(requireCleanWorktree: true)
            )
        }
    }

    @Test("direct push to default branch is blocked by policy")
    func directPushToDefaultBranchIsBlockedByPolicy() throws {
        let repoURL = try makeRepository()

        #expect(throws: NodeMeshGitPolicyError.directPushToDefaultBranch("main")) {
            _ = try NodeMeshGitPolicy.check(
                repositoryPath: repoURL.path,
                nodeName: "Home Mac",
                taskId: "mesh_task_123",
                taskTitle: "Implement remote task dispatch",
                defaultBranch: "main",
                policies: SharedProjectPolicies(branchPerTask: false, directPushToMain: false)
            )
        }
    }

    private func makeRepository() throws -> URL {
        let repoURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("sloppy-mesh-git-policy-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: repoURL, withIntermediateDirectories: true)
        try runGit(["init", "-b", "main"], at: repoURL)
        try "ok".write(to: repoURL.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try runGit(["add", "README.md"], at: repoURL)
        try runGit(["-c", "user.name=Sloppy Tests", "-c", "user.email=tests@example.com", "commit", "-m", "Initial"], at: repoURL)
        return repoURL
    }

    private func runGit(_ arguments: [String], at directoryURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.currentDirectoryURL = directoryURL
        process.arguments = arguments
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }
}

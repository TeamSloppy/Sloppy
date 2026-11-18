import Foundation

public enum NodeMeshWorkerError: LocalizedError, Equatable, Sendable {
    case projectMemberMissing(String)
    case commandFailed(String, Int32)
    case unsafeCheckout
    case invalidBaseRevision
    case pushRequiresCommit
    case outputTooLarge
    case noChangesToCommit

    public var errorDescription: String? {
        switch self {
        case .projectMemberMissing(let nodeId):
            "Node '\(nodeId)' is not a project member."
        case .commandFailed(let command, let exitCode):
            "Command failed with exit code \(exitCode): \(command)"
        case .unsafeCheckout: "Mesh execution requires an isolated task worktree."
        case .invalidBaseRevision: "Base revision must be a full immutable Git object ID."
        case .pushRequiresCommit: "Push requires explicit commit authorization."
        case .outputTooLarge: "Mesh command output exceeded the supported capture limit."
        case .noChangesToCommit:
            "Worker command completed but produced no changes to commit."
        }
    }
}

public struct NodeMeshWorkerCommandResult: Codable, Sendable, Equatable {
    public var command: String
    public var exitCode: Int32
    public var output: String

    public init(command: String, exitCode: Int32, output: String) {
        self.command = command
        self.exitCode = exitCode
        self.output = output
    }
}

public struct NodeMeshWorkerResult: Sendable, Equatable {
    public var taskId: String
    public var projectId: String
    public var status: MeshTaskStatus
    public var branch: String
    public var commit: String?
    public var baseRevision: String = ""
    public var diff: String = ""
    public var worktreePath: String = ""
    public var commandResults: [NodeMeshWorkerCommandResult]
    public var summary: String
    public var tests: [String]

    public init(
        taskId: String,
        projectId: String,
        status: MeshTaskStatus,
        branch: String,
        commit: String?,
        commandResults: [NodeMeshWorkerCommandResult],
        summary: String,
        tests: [String] = []
    ) {
        self.taskId = taskId
        self.projectId = projectId
        self.status = status
        self.branch = branch
        self.commit = commit
        self.commandResults = commandResults
        self.summary = summary
        self.tests = tests
    }
}

public struct NodeMeshWorkerExecutionContext: Sendable, Equatable {
    public var task: MeshTaskRecord
    public var project: SharedProjectRecord
    public var nodeId: String
    public var nodeName: String
    public var localRepoPath: String
    public var agentId: String?

    public init(
        task: MeshTaskRecord,
        project: SharedProjectRecord,
        nodeId: String,
        nodeName: String,
        localRepoPath: String,
        agentId: String? = nil
    ) {
        self.task = task
        self.project = project
        self.nodeId = nodeId
        self.nodeName = nodeName
        self.localRepoPath = localRepoPath
        self.agentId = agentId
    }
}

public struct NodeMeshWorkerExecutionSummary: Sendable, Equatable {
    public var summary: String
    public var tests: [String]

    public init(summary: String, tests: [String] = []) {
        self.summary = summary
        self.tests = tests
    }
}

public enum NodeMeshWorkerExecutor: Sendable {
    case commands([String])
    case autopilot(@Sendable (NodeMeshWorkerExecutionContext) async throws -> NodeMeshWorkerExecutionSummary)
}

public enum NodeMeshWorker {
    public static func execute(
        task: MeshTaskRecord,
        project: SharedProjectRecord,
        nodeId: String,
        nodeName: String,
        commands: [String],
        push: Bool = false,
        isolatedWorktree: Bool = true,
        baseRevision: String? = nil,
        commitChanges: Bool = false
    ) async throws -> NodeMeshWorkerResult {
        try await execute(
            task: task,
            project: project,
            nodeId: nodeId,
            nodeName: nodeName,
            executor: .commands(commands),
            push: push,
            isolatedWorktree: isolatedWorktree,
            baseRevision: baseRevision,
            commitChanges: commitChanges
        )
    }

    public static func execute(
        task: MeshTaskRecord,
        project: SharedProjectRecord,
        nodeId: String,
        nodeName: String,
        executor: NodeMeshWorkerExecutor,
        push: Bool = false,
        isolatedWorktree: Bool = true,
        baseRevision: String? = nil,
        commitChanges: Bool = false
    ) async throws -> NodeMeshWorkerResult {
        guard let member = project.members.first(where: { $0.nodeId == nodeId }) else {
            throw NodeMeshWorkerError.projectMemberMissing(nodeId)
        }

        guard isolatedWorktree else { throw NodeMeshWorkerError.unsafeCheckout }
        guard !push || commitChanges else { throw NodeMeshWorkerError.pushRequiresCommit }
        if let baseRevision {
            guard [40, 64].contains(baseRevision.count), baseRevision.allSatisfy({ $0.isHexDigit }) else {
                throw NodeMeshWorkerError.invalidBaseRevision
            }
        }
        // Resolve once, before execution; never use a moving branch for task creation.
        let pinnedBase = try gitOutput(["rev-parse", "--verify", (baseRevision ?? "HEAD") + "^{commit}"], at: member.localRepoPath)
        let policy = try NodeMeshGitPolicy.check(
            repositoryPath: member.localRepoPath,
            nodeName: nodeName,
            taskId: task.id,
            taskTitle: task.title,
            defaultBranch: project.defaultBranch,
            policies: project.policies
        )
        let workingDirectory: String
        if isolatedWorktree {
            let safeTaskID = task.id.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : "-" }
                .reduce(into: "") { $0.append($1) }
            let worktreeURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("sloppy-mesh-worktrees", isDirectory: true)
                .appendingPathComponent("\(safeTaskID)-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: worktreeURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try runGit(["worktree", "add", "--detach", worktreeURL.path, pinnedBase],
                       at: member.localRepoPath)
            workingDirectory = worktreeURL.path
        } else {
            throw NodeMeshWorkerError.unsafeCheckout
        }

        var commandResults: [NodeMeshWorkerCommandResult] = []
        let executionSummary: NodeMeshWorkerExecutionSummary
        switch executor {
        case .commands(let commands):
            for command in commands {
                let result = try runShell(command, at: workingDirectory)
                commandResults.append(result)
                guard result.exitCode == 0 else {
                    throw NodeMeshWorkerError.commandFailed(command, result.exitCode)
                }
            }
            executionSummary = NodeMeshWorkerExecutionSummary(
                summary: "Executed \(commands.count) command(s) on \(policy.executionBranch)."
            )
        case .autopilot(let run):
            let agentId = member.actorId?.hasPrefix("agent:") == true
                ? String(member.actorId!.dropFirst("agent:".count))
                : member.actorId
            executionSummary = try await run(NodeMeshWorkerExecutionContext(
                task: task,
                project: project,
                nodeId: nodeId,
                nodeName: nodeName,
                localRepoPath: workingDirectory,
                agentId: agentId
            ))
        }

        try runGit(["add", "-A"], at: workingDirectory)
        let dirtyOutput = try gitOutput(["status", "--porcelain"], at: workingDirectory)
        var commit: String?
        let diff = try gitOutput(["diff", "--cached", "--binary", pinnedBase, "--"], at: workingDirectory, trim: false)
        if commitChanges, !dirtyOutput.isEmpty {
            try runGit(
                [
                    "-c", "user.name=Sloppy Mesh Worker",
                    "-c", "user.email=mesh-worker@sloppy.local",
                    "commit",
                    "-m",
                    "Complete \(task.id): \(task.title)",
                ],
                at: workingDirectory
            )
            commit = try gitOutput(["rev-parse", "HEAD"], at: workingDirectory)
        }
        if push, commit != nil {
            try runGit(["push", "origin", "HEAD:refs/heads/" + policy.executionBranch], at: workingDirectory)
        }

        var result = NodeMeshWorkerResult(
            taskId: task.id,
            projectId: project.id,
            status: .readyForReview,
            branch: policy.executionBranch,
            commit: commit,
            commandResults: commandResults,
            summary: executionSummary.summary,
            tests: executionSummary.tests
        )
        result.baseRevision = pinnedBase
        result.diff = diff
        result.worktreePath = workingDirectory
        return result
    }

    /// Collect only in the isolated task worktree. Keep the patch's trailing newline intact.
    public static func resultDiff(at worktreePath: String, baseRevision: String) throws -> String {
        guard [40, 64].contains(baseRevision.count), baseRevision.allSatisfy({ $0.isHexDigit }) else {
            throw NodeMeshWorkerError.invalidBaseRevision
        }
        try runGit(["add", "-A"], at: worktreePath)
        return try gitOutput(["diff", "--cached", "--binary", baseRevision, "--"], at: worktreePath, trim: false)
    }

    private static func runShell(_ command: String, at repositoryPath: String) throws -> NodeMeshWorkerCommandResult {
        #if os(Windows)
        let executable = "cmd.exe"
        let arguments = ["/c", command]
        #else
        let executable = "/bin/sh"
        let arguments = ["-c", command]
        #endif
        let result = try NodeMeshProcess.run(executable: executable, arguments: arguments, directory: repositoryPath)
        let suffix = result.stdoutTruncated || result.stderrTruncated ? "\n[Mesh output truncated]" : ""
        return NodeMeshWorkerCommandResult(command: command, exitCode: result.exitCode,
            output: (result.stdout + result.stderr).trimmingCharacters(in: .whitespacesAndNewlines) + suffix)
    }

    private static func runGit(_ arguments: [String], at repositoryPath: String) throws {
        _ = try gitOutput(arguments, at: repositoryPath)
    }

    private static func gitOutput(_ arguments: [String], at repositoryPath: String, trim: Bool = true) throws -> String {
        let result = try NodeMeshProcess.run(executable: "/usr/bin/git",
            arguments: ["-c", "core.hooksPath=/dev/null", "-c", "core.fsmonitor=false"] + arguments,
            directory: repositoryPath)
        guard result.exitCode == 0 else {
            throw NodeMeshGitPolicyError.gitCommandFailed((["git"] + arguments).joined(separator: " ") + ": " + result.stderr)
        }
        // Patches must be complete, never a silently truncated success.
        guard !result.stdoutTruncated, !result.stderrTruncated else { throw NodeMeshWorkerError.outputTooLarge }
        return trim ? result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) : result.stdout
    }
}

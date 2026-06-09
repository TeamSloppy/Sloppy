import Foundation

public enum NodeMeshWorkerError: LocalizedError, Equatable, Sendable {
    case projectMemberMissing(String)
    case commandFailed(String, Int32)
    case noChangesToCommit

    public var errorDescription: String? {
        switch self {
        case .projectMemberMissing(let nodeId):
            "Node '\(nodeId)' is not a project member."
        case .commandFailed(let command, let exitCode):
            "Command failed with exit code \(exitCode): \(command)"
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
        push: Bool = true
    ) async throws -> NodeMeshWorkerResult {
        try await execute(
            task: task,
            project: project,
            nodeId: nodeId,
            nodeName: nodeName,
            executor: .commands(commands),
            push: push
        )
    }

    public static func execute(
        task: MeshTaskRecord,
        project: SharedProjectRecord,
        nodeId: String,
        nodeName: String,
        executor: NodeMeshWorkerExecutor,
        push: Bool = true
    ) async throws -> NodeMeshWorkerResult {
        guard let member = project.members.first(where: { $0.nodeId == nodeId }) else {
            throw NodeMeshWorkerError.projectMemberMissing(nodeId)
        }

        let policy = try NodeMeshGitPolicy.check(
            repositoryPath: member.localRepoPath,
            nodeName: nodeName,
            taskId: task.id,
            taskTitle: task.title,
            defaultBranch: project.defaultBranch,
            policies: project.policies
        )
        try runGit(["checkout", "-B", policy.executionBranch], at: member.localRepoPath)

        var commandResults: [NodeMeshWorkerCommandResult] = []
        let executionSummary: NodeMeshWorkerExecutionSummary
        switch executor {
        case .commands(let commands):
            for command in commands {
                let result = try runShell(command, at: member.localRepoPath)
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
                localRepoPath: member.localRepoPath,
                agentId: agentId
            ))
        }

        try runGit(["add", "-A"], at: member.localRepoPath)
        let dirtyOutput = try gitOutput(["status", "--porcelain"], at: member.localRepoPath)
        guard dirtyOutput.isEmpty == false else {
            throw NodeMeshWorkerError.noChangesToCommit
        }

        try runGit(
            [
                "-c", "user.name=Sloppy Mesh Worker",
                "-c", "user.email=mesh-worker@sloppy.local",
                "commit",
                "-m",
                "Complete \(task.id): \(task.title)",
            ],
            at: member.localRepoPath
        )
        let commit = try gitOutput(["rev-parse", "HEAD"], at: member.localRepoPath)
        if push {
            try runGit(["push", "-u", "origin", policy.executionBranch], at: member.localRepoPath)
        }

        return NodeMeshWorkerResult(
            taskId: task.id,
            projectId: project.id,
            status: .readyForReview,
            branch: policy.executionBranch,
            commit: commit,
            commandResults: commandResults,
            summary: executionSummary.summary,
            tests: executionSummary.tests
        )
    }

    private static func runShell(_ command: String, at repositoryPath: String) throws -> NodeMeshWorkerCommandResult {
        #if os(Windows)
        let executable = "cmd.exe"
        let arguments = ["/c", command]
        #else
        let executable = "/bin/sh"
        let arguments = ["-c", command]
        #endif
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.currentDirectoryURL = URL(fileURLWithPath: repositoryPath, isDirectory: true)
        process.arguments = arguments
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        let output = String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self) +
            String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return NodeMeshWorkerCommandResult(
            command: command,
            exitCode: process.terminationStatus,
            output: output.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private static func runGit(_ arguments: [String], at repositoryPath: String) throws {
        _ = try gitOutput(arguments, at: repositoryPath)
    }

    private static func gitOutput(_ arguments: [String], at repositoryPath: String) throws -> String {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.currentDirectoryURL = URL(fileURLWithPath: repositoryPath, isDirectory: true)
        process.arguments = arguments
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let data = stderr.fileHandleForReading.readDataToEndOfFile()
            let message = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw NodeMeshGitPolicyError.gitCommandFailed((["git"] + arguments).joined(separator: " ") + (message.isEmpty ? "" : ": \(message)"))
        }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

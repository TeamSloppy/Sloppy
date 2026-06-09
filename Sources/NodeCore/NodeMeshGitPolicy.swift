import Foundation

public enum NodeMeshGitPolicyError: LocalizedError, Equatable, Sendable {
    case repositoryMissing(String)
    case gitCommandFailed(String)
    case dirtyWorktree
    case directPushToDefaultBranch(String)

    public var errorDescription: String? {
        switch self {
        case .repositoryMissing(let path):
            "Repository does not exist: \(path)"
        case .gitCommandFailed(let command):
            "Git command failed: \(command)"
        case .dirtyWorktree:
            "Worktree has uncommitted changes."
        case .directPushToDefaultBranch(let branch):
            "Direct push to default branch '\(branch)' is disabled."
        }
    }
}

public struct NodeMeshGitPolicyReport: Sendable, Equatable {
    public var repositoryPath: String
    public var currentBranch: String
    public var isDirty: Bool
    public var executionBranch: String
    public var canExecute: Bool

    public init(
        repositoryPath: String,
        currentBranch: String,
        isDirty: Bool,
        executionBranch: String,
        canExecute: Bool
    ) {
        self.repositoryPath = repositoryPath
        self.currentBranch = currentBranch
        self.isDirty = isDirty
        self.executionBranch = executionBranch
        self.canExecute = canExecute
    }
}

public enum NodeMeshGitPolicy {
    public static func check(
        repositoryPath: String,
        nodeName: String,
        taskId: String,
        taskTitle: String,
        defaultBranch: String,
        policies: SharedProjectPolicies
    ) throws -> NodeMeshGitPolicyReport {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: repositoryPath, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw NodeMeshGitPolicyError.repositoryMissing(repositoryPath)
        }

        let currentBranch = try gitOutput(["branch", "--show-current"], at: repositoryPath)
        let dirtyOutput = try gitOutput(["status", "--porcelain"], at: repositoryPath)
        let isDirty = dirtyOutput.isEmpty == false
        if policies.requireCleanWorktree, isDirty {
            throw NodeMeshGitPolicyError.dirtyWorktree
        }

        let executionBranch: String
        if policies.branchPerTask {
            executionBranch = makeTaskBranchName(nodeName: nodeName, taskId: taskId, taskTitle: taskTitle)
        } else {
            executionBranch = currentBranch
            if policies.directPushToMain == false, currentBranch == defaultBranch {
                throw NodeMeshGitPolicyError.directPushToDefaultBranch(defaultBranch)
            }
        }

        return NodeMeshGitPolicyReport(
            repositoryPath: repositoryPath,
            currentBranch: currentBranch,
            isDirty: isDirty,
            executionBranch: executionBranch,
            canExecute: true
        )
    }

    public static func makeTaskBranchName(nodeName: String, taskId: String, taskTitle: String) -> String {
        let nodeSlug = slug(nodeName, fallback: "node")
        let taskSlug = slug(taskId, fallback: "task")
        let titleSlug = slug(taskTitle, fallback: "work")
        return "agent/\(nodeSlug)/\(taskSlug)-\(titleSlug)"
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

    private static func slug(_ value: String, fallback: String) -> String {
        let slug = value
            .lowercased()
            .unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) ? Character($0) : "-" }
            .reduce(into: "") { $0.append($1) }
            .split(separator: "-")
            .joined(separator: "-")
        return slug.isEmpty ? fallback : slug
    }
}

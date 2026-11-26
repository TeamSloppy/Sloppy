import Foundation
import Testing
@testable import sloppy
@testable import Protocols
@testable import PluginSDK

@Suite("Node source-control plugins", .serialized)
struct NodeSourceControlPluginTests {
    @Test
    func arcadiaPluginMountsAndReadsSourceControlState() async throws {
        guard nodeIsAvailable() else {
            return
        }

        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let pluginDir = root.appendingPathComponent("Plugins/command-source-control", isDirectory: true)
        let repoURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("sloppy-arcadia-source-control-\(UUID().uuidString)", isDirectory: true)
        let logURL = repoURL.appendingPathComponent("arc.log")
        try FileManager.default.createDirectory(at: repoURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let manifest = PluginManifest(
            name: "arcadia-source-control",
            protocol: "source_control",
            version: "0.1.0",
            apiVersion: PluginManifest.nodePluginAPIVersionV2,
            runtime: .nodejs,
            entrypoint: "index.js",
            config: [
                "displayName": .string("Arcadia Source Control"),
                "worktreeRootName": .string(".sloppy-arc-worktrees"),
                "commands": .object([
                    "createWorktree": .string("printf 'mount {worktreePath}\\ncheckout -b {branchName} {baseBranch}\\n' >> \"\(logURL.path)\" && mkdir -p {worktreePath}"),
                    "removeWorktree": .string("printf 'unmount --force {worktreePath}\\n' >> \"\(logURL.path)\" && rm -rf {worktreePath}"),
                    "workingTreeStatus": .string("printf '%s\\n' '{\"repository\":{\"providerId\":\"arcadia-source-control\",\"isRepository\":true,\"rootPath\":\"{path}\",\"branch\":\"feature/arcadia\"},\"files\":[{\"path\":\"file.txt\",\"kind\":\"modified\",\"staged\":false,\"unstaged\":true,\"linesAdded\":2,\"linesDeleted\":1},{\"path\":\"new.txt\",\"kind\":\"untracked\",\"staged\":false,\"unstaged\":true,\"linesAdded\":0,\"linesDeleted\":0}],\"linesAdded\":2,\"linesDeleted\":1}'"),
                    "workingTreeDiff": .string("printf 'diff --git a/file.txt b/file.txt\\n+hello\\n'"),
                ]),
            ]
        )
        let provider = try NodeSourceControlProvider(
            manifest: manifest,
            pluginDirectory: pluginDir,
            descriptor: NodePluginDescriptor(
                sourceControls: [
                    NodeSourceControlCapability(
                        name: "arcadia-source-control",
                        displayName: "Arcadia Source Control",
                        capabilities: ["worktrees", "working_tree_status", "working_tree_diff"]
                    )
                ]
            )
        )

        let worktree = try await provider.createWorktree(repoPath: repoURL.path, taskId: "TASK-1", baseBranch: "trunk")
        #expect(worktree.worktreePath == repoURL.appendingPathComponent(".sloppy-arc-worktrees/TASK-1").path)
        #expect(worktree.branchName == "sloppy/TASK-1")
        #expect(FileManager.default.fileExists(atPath: worktree.worktreePath))

        let status = try await provider.workingTreeStatus(at: worktree.worktreePath)
        #expect(status.repository.isRepository)
        #expect(status.repository.branch == "feature/arcadia")
        #expect(status.files.contains { $0.path == "file.txt" && $0.kind == .modified })
        #expect(status.files.contains { $0.path == "new.txt" && $0.kind == .untracked })
        #expect(status.linesAdded == 2)
        #expect(status.linesDeleted == 1)

        let diff = try await provider.workingTreeDiff(at: worktree.worktreePath, maxBytes: 1024)
        #expect(diff.providerId == "arcadia-source-control")
        #expect(diff.text.contains("+hello"))

        try await provider.removeWorktree(repoPath: repoURL.path, worktreePath: worktree.worktreePath)
        #expect(!FileManager.default.fileExists(atPath: worktree.worktreePath))

        let log = try String(contentsOf: logURL, encoding: .utf8)
        #expect(log.contains("mount \(worktree.worktreePath)"))
        #expect(log.contains("checkout -b sloppy/TASK-1 trunk"))
        #expect(log.contains("unmount --force \(worktree.worktreePath)"))
    }

    @Test
    func commandAdapterCreatesWorktreeAndReturnsDiff() async throws {
        guard nodeIsAvailable() else {
            return
        }

        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let pluginDir = root.appendingPathComponent("Plugins/command-source-control", isDirectory: true)
        let repoURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("sloppy-node-source-control-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: repoURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let manifest = PluginManifest(
            name: "command-source-control",
            protocol: "source_control",
            runtime: .nodejs,
            entrypoint: "index.js",
            config: [
                "displayName": .string("Command Source Control"),
                "worktreeRootName": .string(".sloppy-worktree"),
                "capabilities": .array([.string("worktrees"), .string("working_tree_diff")]),
                "commands": .object([
                    "createWorktree": .string("mkdir -p {worktreePath}"),
                    "workingTreeDiff": .string("printf 'diff --git a/file.txt b/file.txt\\n+hello\\n'"),
                ]),
            ]
        )
        let provider = try NodeSourceControlProvider(manifest: manifest, pluginDirectory: pluginDir)

        let worktree = try await provider.createWorktree(repoPath: repoURL.path, taskId: "task-1", baseBranch: "HEAD")
        #expect(worktree.worktreePath == repoURL.appendingPathComponent(".sloppy-worktree/task-1").path)
        #expect(worktree.branchName == "sloppy/task-1")
        #expect(FileManager.default.fileExists(atPath: worktree.worktreePath))

        let diff = try await provider.workingTreeDiff(at: worktree.worktreePath, maxBytes: 1024)
        #expect(diff.providerId == "command-source-control")
        #expect(diff.text.contains("+hello"))
    }

    @Test
    func commandAdapterReportsUnsupportedOperations() async throws {
        guard nodeIsAvailable() else {
            return
        }

        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let pluginDir = root.appendingPathComponent("Plugins/command-source-control", isDirectory: true)
        let manifest = PluginManifest(
            name: "command-source-control",
            protocol: "source_control",
            runtime: .nodejs,
            entrypoint: "index.js",
            config: [:]
        )
        let provider = try NodeSourceControlProvider(manifest: manifest, pluginDirectory: pluginDir)

        do {
            _ = try await provider.createWorktree(repoPath: "/tmp/repo", taskId: "task-1", baseBranch: "HEAD")
            Issue.record("Expected unsupported createWorktree to throw.")
        } catch let error as SourceControlProviderError {
            guard case .unsupportedOperation = error else {
                Issue.record("Expected unsupportedOperation, got \(error).")
                return
            }
        }
    }

    @Test
    func pullRequestOperationsUseTheV2SourceControlContract() async throws {
        guard nodeIsAvailable() else { return }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("pr-contract-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let script = """
        let input = "";
        process.stdin.on("data", chunk => input += chunk);
        process.stdin.on("end", () => {
          const request = JSON.parse(input);
          const result = request.method === "source_control.pollPullRequestEvents"
            && request.params.since === "1970-01-01T00:00:00Z"
            && request.params.account === "reviewer"
            ? { events: [], nextCursor: request.params.cursor, hasMore: false }
            : null;
          process.stdout.write(JSON.stringify({ id: request.id, result }));
        });
        """
        try script.write(to: root.appendingPathComponent("index.js"), atomically: true, encoding: .utf8)
        let provider = try NodeSourceControlProvider(
            manifest: .init(name: "pr-provider", protocol: "source_control",
                            apiVersion: PluginManifest.nodePluginAPIVersionV2, runtime: .nodejs, entrypoint: "index.js"),
            pluginDirectory: root,
            descriptor: .init(sourceControls: [.init(name: "pr-provider", capabilities: ["pull_request_events"])])
        )
        let cursor = JSONValue.object(["since": .string("provider-specific")])
        let page = try await provider.pollPullRequestEvents(.init(
            repositoryPath: root.path, account: "reviewer", reviewIDs: [], kinds: [.reviewRequested],
            since: Date(timeIntervalSince1970: 0), cursor: cursor
        ))
        #expect(page.nextCursor == cursor)
        #expect(page.events.isEmpty)
        #expect(provider.capabilities == [.pullRequestEvents])
    }
}

private func nodeIsAvailable() -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", "--version"]
    process.standardOutput = Pipe()
    process.standardError = Pipe()
    do {
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0
    } catch {
        return false
    }
}

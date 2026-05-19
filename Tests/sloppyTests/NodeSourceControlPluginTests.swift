import Foundation
import Testing
@testable import sloppy
@testable import Protocols
@testable import PluginSDK

@Suite("Node source-control plugins")
struct NodeSourceControlPluginTests {
    @Test
    func arcadiaPluginMountsAndReadsSourceControlState() async throws {
        guard nodeIsAvailable() else {
            return
        }

        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let pluginDir = root.appendingPathComponent("Plugins/arcadia-source-control", isDirectory: true)
        let repoURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("sloppy-arcadia-source-control-\(UUID().uuidString)", isDirectory: true)
        let binURL = repoURL.appendingPathComponent("bin", isDirectory: true)
        let arcURL = binURL.appendingPathComponent("arc")
        let logURL = repoURL.appendingPathComponent("arc.log")
        try FileManager.default.createDirectory(at: binURL, withIntermediateDirectories: true)
        try Data(fakeArcScript.utf8).write(to: arcURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: arcURL.path)
        setenv("SLOPPY_FAKE_ARC_LOG", logURL.path, 1)
        defer {
            unsetenv("SLOPPY_FAKE_ARC_LOG")
            try? FileManager.default.removeItem(at: repoURL)
        }

        let manifest = PluginManifest(
            name: "arcadia-source-control",
            protocol: "source_control",
            version: "0.1.0",
            apiVersion: PluginManifest.nodePluginAPIVersionV2,
            runtime: .nodejs,
            entrypoint: "index.js",
            config: [
                "displayName": .string("Arcadia Source Control"),
                "arcBinary": .string(arcURL.path),
                "worktreeRootName": .string(".sloppy-arc-worktrees"),
                "defaultBranch": .string("trunk"),
                "createBranchOnMount": .bool(true),
                "removeDirectoryAfterUnmount": .bool(true),
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
}

private let fakeArcScript = """
#!/bin/sh
if [ -n "$SLOPPY_FAKE_ARC_LOG" ]; then
  printf '%s\\n' "$*" >> "$SLOPPY_FAKE_ARC_LOG"
fi

case "$1" in
  mount)
    mkdir -p "$2"
    ;;
  unmount)
    exit 0
    ;;
  root)
    pwd
    ;;
  branch)
    if [ "$2" = "--show-current" ]; then
      printf 'feature/arcadia\\n'
    fi
    ;;
  rev-parse)
    if [ "$2" = "HEAD" ]; then
      printf 'abc123\\n'
    elif [ "$2" = "--abbrev-ref" ]; then
      printf 'feature/arcadia\\n'
    fi
    ;;
  status)
    printf ' M file.txt\\n'
    printf '?? new.txt\\n'
    ;;
  diff)
    case "$*" in
      *--numstat*)
        printf '2\\t1\\tfile.txt\\n'
        ;;
      *)
        printf 'diff --git a/file.txt b/file.txt\\n'
        printf '+hello\\n'
        ;;
    esac
    ;;
  checkout)
    exit 0
    ;;
  merge)
    exit 0
    ;;
esac
"""

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

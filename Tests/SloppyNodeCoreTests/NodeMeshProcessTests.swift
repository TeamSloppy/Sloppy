import Foundation
import Testing
@testable import SloppyNodeCore

@Suite("Mesh process safety prerequisites")
struct NodeMeshProcessTests {
    @Test func environmentIsExactAndDoesNotMergeHostValues() throws {
        let home = URL(fileURLWithPath: "/tmp/mesh-test-home")
        let env = NodeMeshProcess.environment(home: home)
        #expect(Set(env.keys) == Set(["PATH", "HOME", "TMPDIR", "XDG_CONFIG_HOME", "LANG", "LC_ALL",
                                    "GIT_CONFIG_NOSYSTEM", "GIT_CONFIG_GLOBAL", "GIT_TERMINAL_PROMPT"]))
        #expect(env["HOME"] == home.path)
        #expect(env["PATH"] == "/usr/bin:/bin:/usr/sbin:/sbin")
        #expect(env["SSH_AUTH_SOCK"] == nil)
        let result = try NodeMeshProcess.run(executable: "/usr/bin/env", arguments: [], directory: "/tmp")
        let keys = Set(result.stdout.split(separator: "\n").map { String($0.split(separator: "=", maxSplits: 1)[0]) })
        #expect(keys == Set(env.keys))
        #expect(result.exitCode == 0)
    }

    @Test func stdoutAndStderrBeyondPipeCapacityDrainWithoutDeadlockAndStayBounded() throws {
        let result = try NodeMeshProcess.run(executable: "/bin/sh",
            arguments: ["-c", "i=0; while [ $i -lt 20000 ]; do printf 'abcdefghijklmnopqrstuvwxyz0123456789\\n'; printf 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789\\n' >&2; i=$((i+1)); done"],
            directory: "/tmp", maxOutputBytes: 4096)
        #expect(result.exitCode == 0)
        #expect(result.stdout.utf8.count == 4096)
        #expect(result.stderr.utf8.count == 4096)
        #expect(result.stdoutTruncated && result.stderrTruncated)
    }

    @Test func stdinIsClosedAndNonzeroExitRetained() throws {
        let result = try NodeMeshProcess.run(executable: "/bin/sh", arguments: ["-c", "read input; exit 7"], directory: "/tmp")
        #expect(result.exitCode == 7)
        #expect(result.stdout.isEmpty && result.stderr.isEmpty)
    }

    @Test func cleanEnvironmentAndCwdAreNotFilesystemIsolation() throws {
        // Harmless canary, never an actual host credential. This records the production blocker.
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = root.appendingPathComponent("workspace")
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        let outside = root.appendingPathComponent("outside-canary")
        try "synthetic-outside-data".write(to: outside, atomically: true, encoding: .utf8)
        let result = try NodeMeshProcess.run(executable: "/bin/cat", arguments: [outside.path], directory: workspace.path)
        #expect(result.exitCode == 0)
        #expect(result.stdout == "synthetic-outside-data")
    }
}

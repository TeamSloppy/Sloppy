import Foundation
import Testing
@testable import sloppy

@Suite struct ConsoleRelayProcessLeaseTests {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("console-lease-\(UUID())")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    @Test func onlyOneOwnerAndReleaseAllowsTheNextOwner() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let first = try #require(try ConsoleRelayProcessLease.acquire(workspaceRoot: root))
        #expect(try ConsoleRelayProcessLease.acquire(workspaceRoot: root) == nil)
        first.release(); first.release()
        let next = try #require(try ConsoleRelayProcessLease.acquire(workspaceRoot: root))
        next.release()
        let attrs = try FileManager.default.attributesOfItem(atPath: root.appendingPathComponent(".sloppy/console-relay.lock").path)
        #expect((attrs[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    }
    @Test func separateProcessCannotReplaceAnOwner() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let first = try #require(try ConsoleRelayProcessLease.acquire(workspaceRoot: root))
        defer { first.release() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", "-I", "-S", "-c", "import fcntl,sys; f=open(sys.argv[1],'r+');\ntry: fcntl.flock(f,fcntl.LOCK_EX|fcntl.LOCK_NB)\nexcept BlockingIOError: sys.exit(7)\nsys.exit(0)", root.appendingPathComponent(".sloppy/console-relay.lock").path]
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try process.run(); process.waitUntilExit()
        #expect(process.terminationStatus == 7)
    }
    @Test func deinitReleasesAndDifferentWorkspacesAreIndependent() throws {
        let a = try directory(), b = try directory()
        defer { try? FileManager.default.removeItem(at: a); try? FileManager.default.removeItem(at: b) }
        var first = try #require(try ConsoleRelayProcessLease.acquire(workspaceRoot: a)) as ConsoleRelayProcessLease?
        #expect(first != nil)
        let other = try #require(try ConsoleRelayProcessLease.acquire(workspaceRoot: b)); other.release()
        first = nil
        let restored = try #require(try ConsoleRelayProcessLease.acquire(workspaceRoot: a)); restored.release()
    }
}

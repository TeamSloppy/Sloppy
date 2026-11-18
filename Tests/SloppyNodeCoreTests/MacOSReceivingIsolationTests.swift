import Foundation
import Testing
@testable import SloppyNodeCore

@Suite("macOS receiving isolation experimental")
struct MacOSReceivingIsolationTests {
    @Test func deniesHostAndSymlinkAccessWhileTaskAndPrivateGitWork() throws {
        #if os(macOS)
        let fixture = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixture) }
        let source = fixture.appendingPathComponent("source")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: false)
        func git(_ args: [String]) throws -> String {
            let result = try NodeMeshProcess.run(executable: "/usr/bin/git", arguments: args, directory: source.path)
            #expect(result.exitCode == 0)
            return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        _ = try git(["init", "."])
        try "base".write(to: source.appendingPathComponent("base.txt"), atomically: true, encoding: .utf8)
        _ = try git(["add", "."])
        _ = try git(["-c", "user.name=Test", "-c", "user.email=test@invalid", "commit", "-m", "base"])
        let base = try git(["rev-parse", "HEAD"])
        let dev = "/Applications/Xcode-26.6.0.app/Contents/Developer"
        let ws = try MacOSReceivingIsolation.prepare(source: source, base: base, destination: fixture.appendingPathComponent("task"))
        let secret = fixture.appendingPathComponent("secret")
        try "synthetic-secret".write(to: secret, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: ws.root.appendingPathComponent("escape"), withDestinationURL: secret)
        #expect(try ws.run("/bin/cat", [secret.path]).exitCode != 0)
        #expect(try ws.run("/bin/cat", ["/System/Volumes/Data" + secret.path]).exitCode != 0)
        #expect(try ws.run("/bin/cat", ["escape"]).exitCode != 0)
        #expect(try ws.run("/bin/sh", ["-c", "/bin/cat \"$1\"", "child", secret.path]).exitCode != 0)
        #expect(try ws.run("/bin/sh", ["-c", "echo forbidden >> \"$1\"", "child", source.appendingPathComponent(".git/config").path]).exitCode != 0)
        let edit = try ws.run("/bin/sh", ["-c", "echo changed > task.txt; "+dev+"/usr/bin/git config --local mesh.canary private"], toolchain: dev)
        #expect(edit.exitCode == 0, Comment(rawValue: edit.stderr))
        #expect(!(try String(contentsOf: source.appendingPathComponent(".git/config"), encoding: .utf8)).contains("canary"))
        #expect(try ws.run(dev + "/usr/bin/git", ["rev-parse", "HEAD"], toolchain: dev).stdout.trimmingCharacters(in: .whitespacesAndNewlines) == base)
        let env = try ws.run("/usr/bin/env", [])
        #expect(!env.stdout.contains("SSH_AUTH_SOCK="))
        #expect(!env.stdout.contains("DYLD_"))
        #expect(!FileManager.default.fileExists(atPath: ws.root.appendingPathComponent(".git/objects/info/alternates").path))
        try FileManager.default.removeItem(at: ws.root.appendingPathComponent(".home"))
        try FileManager.default.createSymbolicLink(at: ws.root.appendingPathComponent(".home"), withDestinationURL: fixture)
        #expect(throws: MacOSReceivingIsolation.Failure.invalidRoot) { try ws.run("/usr/bin/true", []) }
        #endif
    }

    @Test func rejectsBroadWritableRootsAndReplacedWorkspace() throws {
        #if os(macOS)
        #expect(throws: MacOSReceivingIsolation.Failure.invalidRoot) {
            try MacOSReceivingIsolation.profile(root: URL(fileURLWithPath: "/tmp"), toolchain: nil)
        }
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: parent) }
        let root = parent.appendingPathComponent("task")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let ws = try MacOSReceivingIsolation.Workspace(root: root, base: "fixture")
        try FileManager.default.moveItem(at: root, to: parent.appendingPathComponent("original"))
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        #expect(throws: MacOSReceivingIsolation.Failure.invalidRoot) { try ws.run("/usr/bin/true", []) }
        #endif
    }

    @Test func rejectsUntrustedToolchainAndHomeSymlinkWithoutMutatingOutside() throws {
        #if os(macOS)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(throws: MacOSReceivingIsolation.Failure.unapprovedToolchain) {
            try MacOSReceivingIsolation.profile(root: root, toolchain: "/Applications/Xcode-missing.app/Contents/Developer")
        }
        let outside = root.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o755])
        let task = root.appendingPathComponent("task")
        try FileManager.default.createDirectory(at: task, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        try FileManager.default.createSymbolicLink(at: task.appendingPathComponent(".home"), withDestinationURL: outside)
        let ws = try MacOSReceivingIsolation.Workspace(root: task, base: "fixture")
        #expect(throws: MacOSReceivingIsolation.Failure.invalidRoot) { try ws.run("/usr/bin/true", []) }
        #expect((try FileManager.default.attributesOfItem(atPath: outside.path)[.posixPermissions] as? NSNumber)?.intValue == 0o755)
        #endif
    }

    @Test func compilerSmoke() throws {
        #if os(macOS)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        let ws = try MacOSReceivingIsolation.Workspace(root: root.resolvingSymlinksInPath(), base: "fixture")
        let dev = "/Applications/Xcode-26.6.0.app/Contents/Developer"
        try """
        #include <sys/socket.h>
        #include <netinet/in.h>
        #include <errno.h>
        #include <unistd.h>
        int main(void) {
            int s = socket(AF_INET, SOCK_STREAM, 0);
            if (s < 0) return errno == EPERM ? 0 : 10;
            struct sockaddr_in a = {0};
            a.sin_family = AF_INET; a.sin_port = htons(9); a.sin_addr.s_addr = htonl(0x7f000001);
            int r = connect(s, (struct sockaddr *)&a, sizeof(a));
            int e = errno; close(s);
            return (r < 0 && e == EPERM) ? 0 : 11;
        }
        """.write(to: root.appendingPathComponent("main.c"), atomically: true, encoding: .utf8)
        let build = try ws.run(dev + "/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang",
            ["-isysroot", dev + "/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk", "main.c", "-o", "smoke"], toolchain: dev)
        #expect(build.exitCode == 0, Comment(rawValue: build.stderr))
        #expect(try ws.run(root.appendingPathComponent("smoke").path, []).exitCode == 0)
        #endif
    }
}

@Suite("macOS path binding characterization")
struct MacOSPathBindingTests {
    @Test(arguments: [false, true])
    func postValidationReplacementHasNoVnodeBinding(useSymlink: Bool) throws {
        #if os(macOS)
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: parent) }
        let task = parent.appendingPathComponent("task")
        let outside = parent.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: task, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        try FileManager.default.createDirectory(at: outside.appendingPathComponent(".home"), withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        try "synthetic-secret".write(to: outside.appendingPathComponent("secret"), atomically: true, encoding: .utf8)
        // This is exactly the production seam: validation/profile construction finished;
        // sandbox-exec has not yet compiled its path rules or installed its policy.
        let profile = try MacOSReceivingIsolation.profile(root: task, toolchain: nil)
        try FileManager.default.moveItem(at: task, to: parent.appendingPathComponent("original"))
        if useSymlink {
            try FileManager.default.createSymbolicLink(at: task, withDestinationURL: outside)
        } else {
            try FileManager.default.moveItem(at: outside, to: task)
        }
        let result = try NodeMeshProcess.run(executable: "/usr/bin/sandbox-exec",
            arguments: ["-p", profile, "/bin/cat", "secret"], directory: task.path, home: task.appendingPathComponent(".home"))
        // Characterize the vulnerability, not an isolation success. No real host secrets.
        if useSymlink {
            #expect(result.exitCode != 0)
            #expect(result.stdout.isEmpty)
        } else {
            // A passing characterization assertion records an OPEN security defect.
            #expect(result.exitCode == 0)
            #expect(result.stdout == "synthetic-secret")
        }
        #endif
    }
}

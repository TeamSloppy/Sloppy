import Foundation
#if os(macOS)
import Darwin
#endif

/// Experimental synchronous boundary for disposable receiving helpers, NOT production dispatch.
/// The caller owns a newly-created task directory. No host credentials/network exceptions.
/// SECURITY: rootIdentity is only a preflight check. The textual Seatbelt subpath and
/// Process.currentDirectoryURL are resolved later; replacement with another directory
/// after profile construction can grant access to the replacement. See MacOSPathBindingTests.
/// Do not expose this prototype as a hostile-task execution boundary.
enum MacOSReceivingIsolation {
    enum Failure: Error, Equatable { case unsupported, invalidRoot, invalidBase, gitFailed, unapprovedToolchain }

    struct Workspace {
        let root: URL
        let base: String
        private let identity: RootIdentity

        init(root: URL, base: String) throws {
            let canonical = try MacOSReceivingIsolation.canonicalPath(root)
            self.root = URL(fileURLWithPath: canonical)
            self.base = base
            self.identity = try MacOSReceivingIsolation.rootIdentity(self.root)
            let home = self.root.appendingPathComponent(".home")
            if !FileManager.default.fileExists(atPath: home.path) {
                try FileManager.default.createDirectory(at: home, withIntermediateDirectories: false,
                    attributes: [.posixPermissions: 0o700])
            }
        }

        /// Launches only bounded, short validation commands. Durable cancellation is not provided.
        func run(_ executable: String, _ arguments: [String], toolchain: String? = nil) throws -> NodeMeshProcess.Result {
            #if os(macOS)
            guard try MacOSReceivingIsolation.rootIdentity(root) == identity else { throw Failure.invalidRoot }
            let profile = try MacOSReceivingIsolation.profile(root: root, toolchain: toolchain)
            let home = root.appendingPathComponent(".home")
            if FileManager.default.fileExists(atPath: home.path) {
                let values = try home.resourceValues(forKeys: [.isSymbolicLinkKey])
                guard values.isSymbolicLink != true else { throw Failure.invalidRoot }
            }
            return try NodeMeshProcess.run(executable: "/usr/bin/sandbox-exec",
                arguments: ["-p", profile, executable] + arguments, directory: root.path, home: root.appendingPathComponent(".home"))
            #else
            throw Failure.unsupported
            #endif
        }
    }

    static func prepare(source: URL, base: String, destination: URL) throws -> Workspace {
        #if os(macOS)
        guard base.count == 40, base.allSatisfy(\.isHexDigit) else { throw Failure.invalidBase }
        guard !FileManager.default.fileExists(atPath: destination.path) else { throw Failure.invalidRoot }
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let root = destination.resolvingSymlinksInPath().standardizedFileURL
        func git(_ args: [String]) throws {
            let result = try NodeMeshProcess.run(executable: "/usr/bin/git", arguments:
                ["-c", "core.hooksPath=/dev/null", "-c", "core.fsmonitor=false"] + args, directory: root.path)
            guard result.exitCode == 0 else { throw Failure.gitFailed }
        }
        // Brokered preparation only. Fetch copies objects, not linked worktree metadata or hard links.
        try git(["init", "--template=", "."])
        try git(["fetch", "--no-tags", "--depth=1", source.resolvingSymlinksInPath().path, base])
        try git(["checkout", "--detach", base])
        try? FileManager.default.removeItem(at: root.appendingPathComponent(".git/FETCH_HEAD"))
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".home"), withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        return try .init(root: root, base: base)
        #else
        throw Failure.unsupported
        #endif
    }

    private struct RootIdentity: Equatable {
        let device: UInt64
        let inode: UInt64
    }

    private static func canonicalPath(_ root: URL) throws -> String {
        #if os(macOS)
        guard let resolved = realpath(root.path, nil) else { throw Failure.invalidRoot }
        defer { free(resolved) }
        let path = String(cString: resolved)
        guard !path.contains(where: { $0.asciiValue.map { $0 < 32 || $0 == 127 } ?? false }),
              !path.contains("\""), !path.contains("\\") else { throw Failure.invalidRoot }
        return path
        #else
        throw Failure.unsupported
        #endif
    }

    private static func rootIdentity(_ root: URL) throws -> RootIdentity {
        #if os(macOS)
        let path = try canonicalPath(root)
        let temporary = try canonicalPath(FileManager.default.temporaryDirectory)
        // Only a private child, never the temporary tree itself or arbitrary host directory.
        guard path.hasPrefix(temporary + "/"), path != temporary else { throw Failure.invalidRoot }
        var info = stat()
        guard lstat(root.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFDIR,
              info.st_uid == getuid(), (info.st_mode & 0o077) == 0 else { throw Failure.invalidRoot }
        return .init(device: UInt64(info.st_dev), inode: UInt64(info.st_ino))
        #else
        throw Failure.unsupported
        #endif
    }

    static func profile(root: URL, toolchain: String?) throws -> String {
        _ = try rootIdentity(root)
        let path = try canonicalPath(root)
        var readonly = ["/System/Library", "/System/Cryptexes", "/System/Volumes/Preboot/Cryptexes", "/usr/lib", "/usr/bin", "/bin"]
        if let toolchain {
            // Explicit operator SDK/Xcode install only; never arbitrary user-readable roots.
            guard toolchain.hasPrefix("/Applications/Xcode"), toolchain.hasSuffix(".app/Contents/Developer"),
                  !toolchain.contains(".."), !toolchain.contains("\""), !toolchain.contains("\\"), !toolchain.contains("\n") else {
                throw Failure.unapprovedToolchain
            }
            // Reject symlinked/missing installs; no silent canonical remap of a readable grant.
            guard let canonical = try? canonicalPath(URL(fileURLWithPath: toolchain)), canonical == toolchain else {
                throw Failure.unapprovedToolchain
            }
            readonly.append(canonical)
        }
        let reads = readonly.map { "(subpath \"\($0)\")" }.joined(separator: " ")
        return """
        (version 1)
        (deny default)
        (allow process-exec process-fork)
        (allow sysctl-read)
        (allow file-read-metadata file-test-existence)
        (allow file-read* (literal "/") (literal "/dev/null") (literal "/dev/urandom") (literal "/dev/random"))
        (allow file-write-data (literal "/dev/null"))
        (allow file-read* file-map-executable \(reads))
        (allow file-read* file-write* file-map-executable (subpath "\(path)"))
        """
    }
}

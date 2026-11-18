import Foundation

/// Transport-independent prerequisite for trusted Mesh helper commands. Not an OS sandbox.
/// Do not use this as the receiving remote-agent executor until process ownership and
/// filesystem/network isolation are implemented at every tool entry point.
enum NodeMeshProcess {
    struct Result: Sendable {
        var exitCode: Int32
        var stdout: String
        var stderr: String
        var stdoutTruncated: Bool
        var stderrTruncated: Bool
    }

    static func environment(home: URL) -> [String: String] {
        [
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "HOME": home.path,
            "TMPDIR": home.path,
            "XDG_CONFIG_HOME": home.path,
            "LANG": "C",
            "LC_ALL": "C",
            "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_CONFIG_GLOBAL": "/dev/null",
            "GIT_TERMINAL_PROMPT": "0",
        ]
    }

    static func run(executable: String, arguments: [String], directory: String,
                    maxOutputBytes: Int = 4 * 1024 * 1024, home requestedHome: URL? = nil) throws -> Result {
        let home = requestedHome ?? FileManager.default.temporaryDirectory.appendingPathComponent("mesh-process-" + UUID().uuidString)
        if requestedHome == nil {
            try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
        } else {
            // The caller prepares its private HOME before executing untrusted task code.
            // Never mkdir/chmod a task-controlled path outside the sandbox at launch time.
            let values = try home.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isDirectory == true, values.isSymbolicLink != true else {
                throw CocoaError(.fileReadNoPermission)
            }
        }
        defer { if requestedHome == nil { try? FileManager.default.removeItem(at: home) } }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: directory)
        process.environment = environment(home: home)
        process.standardInput = FileHandle.nullDevice
        let stdout = Pipe(), stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        let out = Capture(limit: maxOutputBytes), err = Capture(limit: maxOutputBytes)
        try process.run()
        // Close parent copies so readers see EOF when children close their descriptors.
        try? stdout.fileHandleForWriting.close()
        try? stderr.fileHandleForWriting.close()
        let readers = DispatchGroup()
        for (pipe, capture) in [(stdout, out), (stderr, err)] {
            readers.enter()
            // Dedicated readers must not compete with synchronous process waits in
            // a bounded cooperative/GCD pool (parallel tests exposed starvation).
            Thread.detachNewThread {
                defer { try? pipe.fileHandleForReading.close(); readers.leave() }
                while true {
                    let bytes = pipe.fileHandleForReading.readData(ofLength: 32 * 1024)
                    if bytes.isEmpty { break }
                    capture.append(bytes)
                }
            }
        }
        process.waitUntilExit()
        readers.wait()
        let output = out.value(), error = err.value()
        return .init(exitCode: process.terminationStatus,
                     stdout: String(decoding: output.0, as: UTF8.self),
                     stderr: String(decoding: error.0, as: UTF8.self),
                     stdoutTruncated: output.1, stderrTruncated: error.1)
    }

    /// Lock-protected because readers use GCD rather than the caller's executor.
    private final class Capture: @unchecked Sendable {
        private let lock = NSLock()
        private let limit: Int
        private var bytes = Data()
        private var truncated = false
        init(limit: Int) { self.limit = max(0, limit) }
        func append(_ data: Data) {
            lock.lock()
            defer { lock.unlock() }
            let remaining = max(0, limit - bytes.count)
            bytes.append(data.prefix(remaining))
            if data.count > remaining { truncated = true }
        }
        func value() -> (Data, Bool) {
            lock.lock()
            defer { lock.unlock() }
            return (bytes, truncated)
        }
    }
}

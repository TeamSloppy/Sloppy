import Foundation

/// Disposable copy of a task's `repo/` directory with a committed git baseline, so the agent's changes can be diffed.
struct BenchSandbox: Sendable {
    let root: URL
    let workspace: URL

    static func create(for task: BenchTask, baseDirectory: URL? = nil) throws -> BenchSandbox {
        let fileManager = FileManager.default
        let base = baseDirectory ?? fileManager.temporaryDirectory
        let root = base.appendingPathComponent("sloppy-bench-\(UUID().uuidString.prefix(8).lowercased())", isDirectory: true)
        let workspace = root.appendingPathComponent(task.id, isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        try fileManager.copyItem(at: task.repoDirectory, to: workspace)
        let sandbox = BenchSandbox(root: root, workspace: workspace)
        // A missing git binary only disables the diff; the run itself stays valid.
        _ = try? BenchProcess.run(["git", "init", "-q"], in: workspace, timeout: 30)
        _ = try? BenchProcess.run(["git", "add", "-A"], in: workspace, timeout: 30)
        _ = try? BenchProcess.run(
            ["git", "-c", "user.name=bench", "-c", "user.email=bench@localhost", "commit", "-q", "-m", "baseline"],
            in: workspace,
            timeout: 30
        )
        return sandbox
    }

    /// Unified diff of everything the agent changed since the baseline, or nil when git is unavailable.
    func diff(maxBytes: Int = 64 * 1024) -> String? {
        _ = try? BenchProcess.run(["git", "add", "-A", "-N"], in: workspace, timeout: 30)
        guard let result = try? BenchProcess.run(["git", "diff", "HEAD"], in: workspace, timeout: 30),
              result.exitCode == 0
        else { return nil }
        return String(result.output.prefix(maxBytes))
    }

    func destroy() {
        try? FileManager.default.removeItem(at: root)
    }
}

struct BenchProcessResult: Sendable, Equatable {
    var exitCode: Int32
    var output: String
    var timedOut: Bool
}

enum BenchProcess {
    /// Runs `arguments` (resolved through `/usr/bin/env`) in `directory`, merging stderr into stdout.
    static func run(
        _ arguments: [String],
        in directory: URL,
        timeout: TimeInterval,
        environment: [String: String] = [:]
    ) throws -> BenchProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = arguments
        process.currentDirectoryURL = directory
        var env = ProcessInfo.processInfo.environment
        for (key, value) in environment { env[key] = value }
        process.environment = env

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice

        let collector = OutputCollector()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if !chunk.isEmpty { collector.append(chunk) }
        }

        try process.run()

        let deadline = Date().addingTimeInterval(timeout)
        var timedOut = false
        while process.isRunning {
            if Date() >= deadline {
                timedOut = true
                process.terminate()
                break
            }
            Thread.sleep(forTimeInterval: 0.02)
        }
        process.waitUntilExit()
        pipe.fileHandleForReading.readabilityHandler = nil
        let tail = pipe.fileHandleForReading.readDataToEndOfFile()
        if !tail.isEmpty { collector.append(tail) }

        return BenchProcessResult(
            exitCode: timedOut ? -1 : process.terminationStatus,
            output: collector.string,
            timedOut: timedOut
        )
    }

    private final class OutputCollector: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()

        func append(_ chunk: Data) {
            lock.lock()
            data.append(chunk)
            lock.unlock()
        }

        var string: String {
            lock.lock()
            defer { lock.unlock() }
            return String(decoding: data, as: UTF8.self)
        }
    }
}

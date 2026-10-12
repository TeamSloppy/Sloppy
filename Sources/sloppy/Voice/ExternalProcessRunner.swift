import Foundation

/// Runs a short-lived helper binary off the cooperative thread pool with a hard timeout.
enum ExternalProcessRunner {
    struct Result: Sendable {
        let status: Int32
        let stdout: Data
        let stderr: Data
    }

    enum RunError: Error {
        case timedOut
    }

    static func run(
        executable: String,
        arguments: [String],
        timeout: TimeInterval,
        environment: [String: String] = [:]
    ) async throws -> Result {
        try await Task.detached(priority: .userInitiated) {
            try runBlocking(executable: executable, arguments: arguments, timeout: timeout, environment: environment)
        }.value
    }

    private static func runBlocking(
        executable: String,
        arguments: [String],
        timeout: TimeInterval,
        environment: [String: String]
    ) throws -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if !environment.isEmpty {
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        }
        process.standardInput = FileHandle.nullDevice
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        try process.run()

        // Drain both pipes concurrently so a chatty tool cannot block on a full pipe buffer.
        var outData = Data()
        var errData = Data()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        group.enter()
        DispatchQueue.global().async {
            errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }

        if finished.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            _ = finished.wait(timeout: .now() + 2)
            group.wait()
            throw RunError.timedOut
        }
        group.wait()
        return Result(status: process.terminationStatus, stdout: outData, stderr: errData)
    }

    /// Finds an executable by explicit path, then PATH, then common install locations
    /// (a launchd-started Core often has a minimal PATH).
    static func resolveExecutable(explicit: String, names: [String]) -> String? {
        let fileManager = FileManager.default
        let trimmed = explicit.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            let expanded = (trimmed as NSString).expandingTildeInPath
            return fileManager.isExecutableFile(atPath: expanded) ? expanded : nil
        }
        var directories = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
        directories += [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            (NSHomeDirectory() as NSString).appendingPathComponent(".local/bin"),
        ]
        for directory in directories {
            for name in names {
                let candidate = (directory as NSString).appendingPathComponent(name)
                if fileManager.isExecutableFile(atPath: candidate) {
                    return candidate
                }
            }
        }
        return nil
    }
}

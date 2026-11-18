import Foundation
import Protocols
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

actor SessionProcessRegistry {
    enum RegistryError: Error {
        case processLimitReached
        case processNotFound
        case waitTimedOut
        case invalidPayload
        case launchFailed
        case sessionClosing
    }

    private struct ManagedProcess {
        let id: String
        let command: String
        let arguments: [String]
        let cwd: String?
        let process: Process
        let startedAt: Date
        var finishedAt: Date?
        var exitCode: Int32?
        var outputBuffer: ProcessOutputBuffer?
        var outputPipe: Pipe?
        var outputReader: ProcessPipeReader?
        var ownsProcessGroup: Bool
    }

    private struct ProcessKey: Hashable {
        let sessionID: String
        let processID: String
    }

    private typealias Waiter = AsyncThrowingStream<JSONValue, Error>.Continuation
    private var waiters: [ProcessKey: [UUID: Waiter]] = [:]
    private var closingSessions: Set<String> = []
    private var processesBySession: [String: [String: ManagedProcess]] = [:]

    func activeCount(sessionID: String) -> Int {
        let processes = normalizedSessionProcesses(sessionID: sessionID)
        return processes.values.filter(\.process.isRunning).count
    }

    func start(
        sessionID: String,
        command: String,
        arguments: [String],
        cwd: String?,
        maxProcesses: Int,
        environmentOverrides: [String: String] = [:],
        captureOutput: Bool = false
    ) throws -> JSONValue {
        guard !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RegistryError.invalidPayload
        }

        guard !closingSessions.contains(sessionID) else { throw RegistryError.sessionClosing }
        let current = activeCount(sessionID: sessionID)
        if current >= maxProcesses {
            throw RegistryError.processLimitReached
        }

        let process = Process()
        try PlatformProcess.configure(process, command: command, arguments: arguments,
                                      environment: childProcessEnvironment(overrides: environmentOverrides))
        let outputBuffer = captureOutput ? ProcessOutputBuffer(maxBytes: 256 * 1024, keepsTail: true) : nil
        let outputPipe = captureOutput ? Pipe() : nil
        let outputReader: ProcessPipeReader?
        if let outputPipe, let outputBuffer {
            let reader = ProcessPipeReader(handle: outputPipe.fileHandleForReading, buffer: outputBuffer)
            outputReader = reader
            outputPipe.fileHandleForReading.readabilityHandler = { _ in reader.drain() }
            process.standardOutput = outputPipe
            process.standardError = outputPipe
        } else {
            outputReader = nil
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
        }

        if let cwd, !cwd.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            process.currentDirectoryURL = URL(fileURLWithPath: cwd, isDirectory: true)
        }

        process.environment = childProcessEnvironment(overrides: environmentOverrides)

        let id = "proc-\(UUID().uuidString.lowercased())"
        let key = ProcessKey(sessionID: sessionID, processID: id)
        process.terminationHandler = { [weak self] process in
            let status = process.terminationStatus
            Task { await self?.processDidExit(key, status: status) }
        }
        do {
            try process.run()
        } catch {
            outputPipe?.fileHandleForReading.readabilityHandler = nil
            outputReader?.stop()
            throw RegistryError.launchFailed
        }
        try? outputPipe?.fileHandleForWriting.close()

        let now = Date()
        let managed = ManagedProcess(
            id: id,
            command: command,
            arguments: arguments,
            cwd: cwd,
            process: process,
            startedAt: now,
            finishedAt: nil,
            exitCode: nil,
            outputBuffer: outputBuffer,
            outputPipe: outputPipe,
            outputReader: outputReader,
            ownsProcessGroup: ownsProcessGroup(process, captureOutput: captureOutput)
        )
        processesBySession[sessionID, default: [:]][id] = managed

        return .object([
            "processId": .string(id),
            "pid": .number(Double(process.processIdentifier)),
            "running": .bool(true),
            "startedAt": .string(iso8601(now))
        ])
    }

    func wait(sessionID: String, processID: String, timeoutMs: Int) async throws -> JSONValue {
        try Task.checkCancellation()
        let key = ProcessKey(sessionID: sessionID, processID: processID)
        guard let process = processesBySession[sessionID]?[processID] else {
            throw RegistryError.processNotFound
        }
        if process.exitCode != nil {
            return completionPayload(process, sessionID: sessionID)
        }

        let id = UUID()
        let (stream, waiter) = AsyncThrowingStream<JSONValue, Error>.makeStream(bufferingPolicy: .bufferingNewest(1))
        waiters[key, default: [:]][id] = waiter
        let timeout = Task {
            do { try await Task.sleep(for: .milliseconds(timeoutMs)) }
            catch { return }
            waiter.finish(throwing: RegistryError.waitTimedOut)
        }
        defer {
            timeout.cancel()
            waiters[key]?.removeValue(forKey: id)
            if waiters[key]?.isEmpty == true { waiters.removeValue(forKey: key) }
        }
        var iterator = stream.makeAsyncIterator()
        let result = try await iterator.next()
        try Task.checkCancellation()
        guard let result else { throw RegistryError.processNotFound }
        return result
    }

    private func processDidExit(_ key: ProcessKey, status: Int32) {
        guard var process = processesBySession[key.sessionID]?[key.processID] else { return }
        process.outputPipe?.fileHandleForReading.readabilityHandler = nil
        process.outputReader?.stop()
        process.finishedAt = Date()
        process.exitCode = status
        processesBySession[key.sessionID]?[key.processID] = process
        if let listeners = waiters.removeValue(forKey: key) {
            let result = completionPayload(process, sessionID: key.sessionID)
            for listener in listeners.values {
                listener.yield(result)
                listener.finish()
            }
        }
    }

    private func completionPayload(_ process: ManagedProcess, sessionID: String) -> JSONValue {
        var payload = processPayload(process).asObject ?? [:]
        payload["outputTail"] = .string(output(sessionID: sessionID, processID: process.id))
        return .object(payload)
    }

    func output(sessionID: String, processID: String) -> String {
        guard let buffer = processesBySession[sessionID]?[processID]?.outputBuffer else { return "" }
        let snapshot = buffer.snapshot()
        return String(decoding: snapshot.data, as: UTF8.self) + (snapshot.truncated ? "\n[Output truncated]\n" : "")
    }

    func status(sessionID: String, processID: String) throws -> JSONValue {
        guard let process = processesBySession[sessionID]?[processID] else {
            throw RegistryError.processNotFound
        }
        return processPayload(refreshed(process))
    }

    func stop(sessionID: String, processID: String) async throws -> JSONValue {
        let sessionProcesses = normalizedSessionProcesses(sessionID: sessionID)
        guard let process = sessionProcesses[processID] else {
            throw RegistryError.processNotFound
        }

        #if !os(Windows)
        if process.ownsProcessGroup {
            // Foundation creates a new process group; confirm ownership before signalling descendants.
            kill(-process.process.processIdentifier, SIGTERM)
        } else if process.process.isRunning && process.outputBuffer != nil {
            await terminateLaunchDescendants(process.process.processIdentifier)
        }
        if process.process.isRunning { await terminateProcess(process.process) }
        if process.ownsProcessGroup { kill(-process.process.processIdentifier, SIGKILL) }
        #else
        if process.process.isRunning { await terminateProcess(process.process) }
        #endif
        return processPayload(refreshed(processesBySession[sessionID]?[processID] ?? process))
    }

    func list(sessionID: String) -> JSONValue {
        let sessionProcesses = normalizedSessionProcesses(sessionID: sessionID)
        let items = sessionProcesses.values
            .sorted { $0.startedAt > $1.startedAt }


        return .array(items.map(processPayload))
    }

    func cleanup(sessionID: String) async {
        guard let sessionProcesses = processesBySession[sessionID], closingSessions.insert(sessionID).inserted else {
            return
        }
        defer { closingSessions.remove(sessionID) }
        for process in sessionProcesses.values where process.process.isRunning || process.ownsProcessGroup {
            _ = try? await stop(sessionID: sessionID, processID: process.id)
        }
        for process in sessionProcesses.values {
            process.outputPipe?.fileHandleForReading.readabilityHandler = nil
            process.outputReader?.stop()
            let key = ProcessKey(sessionID: sessionID, processID: process.id)
            waiters.removeValue(forKey: key)?.values.forEach { $0.finish() }
        }
        processesBySession.removeValue(forKey: sessionID)
    }

    func shutdown() async {
        for sessionID in Array(processesBySession.keys) {
            await cleanup(sessionID: sessionID)
        }
    }

    private func refreshed(_ process: ManagedProcess) -> ManagedProcess {
        guard !process.process.isRunning else {
            return process
        }

        if process.exitCode != nil {
            return process
        }

        var copy = process
        copy.exitCode = process.process.terminationStatus
        copy.finishedAt = Date()
        return copy
    }

    private func normalizedSessionProcesses(sessionID: String) -> [String: ManagedProcess] {
        (processesBySession[sessionID] ?? [:]).mapValues(refreshed)
    }

    private func processPayload(_ process: ManagedProcess) -> JSONValue {
        .object([
            "processId": .string(process.id),
            "command": .string(process.command),
            "arguments": .array(process.arguments.map { .string($0) }),
            "cwd": process.cwd.map(JSONValue.string) ?? .null,
            "running": .bool(process.process.isRunning),
            "startedAt": .string(iso8601(process.startedAt)),
            "finishedAt": process.finishedAt.map { .string(iso8601($0)) } ?? .null,
            "exitCode": process.exitCode.map { .number(Double($0)) } ?? .null
        ])
    }

    private func iso8601(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}

private func ownsProcessGroup(_ process: Process, captureOutput: Bool) -> Bool {
    #if os(Windows)
    return false
    #else
    return captureOutput && getpgid(process.processIdentifier) == process.processIdentifier
    #endif
}

/// Capture child identities before stopping the parent to avoid orphaning shell-launched servers.
private func terminateLaunchDescendants(_ parent: Int32) async {
#if canImport(Darwin) || canImport(Glibc)
    guard let result = try? await runForegroundProcess(command: "/usr/bin/pgrep", arguments: ["-P", String(parent)], cwd: nil, timeoutMs: 2_000, maxOutputBytes: 8192),
          let text = result.asObject?["stdout"]?.asString else { return }
    for child in text.split(whereSeparator: \.isWhitespace).compactMap({ Int32($0) }) {
        await terminateLaunchDescendants(child)
        kill(child, SIGTERM)
    }
#endif
}

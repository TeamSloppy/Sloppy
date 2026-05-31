//
//  TerminalDelegate.swift
//  ACP
//
//  Default terminal delegate implementation
//

import Foundation
import ACPModel

/// Tracks state of a single terminal
private struct TerminalState: @unchecked Sendable {
    let process: Process
    var outputBuffer: String = ""
    var outputByteLimit: Int?
    var lastReadIndex: Int = 0
    var isReleased: Bool = false
    var wasTruncated: Bool = false
    var exitWaiters: [CheckedContinuation<(exitCode: Int?, signal: String?), Never>] = []
}

/// Cached output for released terminals
private struct ReleasedTerminalOutput: Sendable {
    let output: String
    let exitCode: Int?
}

/// Actor responsible for handling terminal operations for agent sessions
public actor TerminalDelegate {

    // MARK: - Errors

    public enum TerminalError: LocalizedError, Sendable {
        case terminalNotFound(String)
        case terminalReleased(String)
        case executableNotFound(String)
        case commandParsingFailed(String)

        public var errorDescription: String? {
            switch self {
            case .terminalNotFound(let id):
                return "Terminal with ID '\(id)' not found"
            case .terminalReleased(let id):
                return "Terminal with ID '\(id)' has been released"
            case .executableNotFound(let path):
                return "Executable not found: '\(path)'"
            case .commandParsingFailed(let command):
                return "Failed to parse command string: '\(command)'"
            }
        }
    }

    // MARK: - Private Properties

    private var terminals: [String: TerminalState] = [:]
    private var releasedOutputs: [String: ReleasedTerminalOutput] = [:]
    private var releasedOutputOrder: [String] = []
    private let defaultOutputByteLimit = 1_000_000
    private let maxReleasedOutputEntries = 50

    // MARK: - Private Cleanup

    private func drainPipe(_ pipe: Pipe, terminalId: String) {
        let handle = pipe.fileHandleForReading
        handle.readabilityHandler = nil

        do {
            while true {
                guard let data = try handle.read(upToCount: 65536), !data.isEmpty else {
                    break
                }
                if let output = String(data: data, encoding: .utf8) {
                    appendOutput(terminalId: terminalId, output: output)
                }
            }
        } catch {
            // File handle already closed
        }
    }

    private func cleanupProcessPipes(_ process: Process, terminalId: String? = nil) {
        if let outputPipe = process.standardOutput as? Pipe {
            if let id = terminalId {
                drainPipe(outputPipe, terminalId: id)
            } else {
                outputPipe.fileHandleForReading.readabilityHandler = nil
            }
            try? outputPipe.fileHandleForReading.close()
        }
        if let errorPipe = process.standardError as? Pipe {
            if let id = terminalId {
                drainPipe(errorPipe, terminalId: id)
            } else {
                errorPipe.fileHandleForReading.readabilityHandler = nil
            }
            try? errorPipe.fileHandleForReading.close()
        }
    }

    // MARK: - Initialization

    public init() {}

    // MARK: - Terminal Operations

    /// Create a new terminal process
    public func handleTerminalCreate(
        command: String,
        sessionId: String,
        args: [String]?,
        cwd: String?,
        env: [EnvVariable]?,
        outputByteLimit: Int?
    ) async throws -> CreateTerminalResponse {
        var executablePath: String
        var finalArgs: [String]

        let shellOperators = ["|", "&&", "||", ";", ">", ">>", "<", "$(", "`", "&"]
        let needsShell = shellOperators.contains { command.contains($0) }

        if needsShell {
            executablePath = "/bin/sh"
            if let args = args, !args.isEmpty {
                finalArgs = ["-c", ([command] + args).joined(separator: " ")]
            } else {
                finalArgs = ["-c", command]
            }
        } else if args == nil || args?.isEmpty == true {
            if command.contains(" ") || command.contains("\"") {
                let (parsedExecutable, parsedArgs) = try parseCommandString(command)
                executablePath = try resolveExecutablePath(parsedExecutable)
                finalArgs = parsedArgs
            } else {
                executablePath = try resolveExecutablePath(command)
                finalArgs = []
            }
        } else {
            executablePath = try resolveExecutablePath(command)
            finalArgs = args ?? []
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = finalArgs

        if let cwd = cwd {
            process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        }

        var envDict = ShellEnvironment.loadUserShellEnvironment()
        if let envVars = env {
            for envVar in envVars {
                envDict[envVar.name] = envVar.value
            }
        }
        process.environment = envDict

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        let terminalIdValue = UUID().uuidString
        let terminalId = TerminalId(terminalIdValue)

        let state = TerminalState(process: process, outputByteLimit: outputByteLimit ?? defaultOutputByteLimit)
        terminals[terminalIdValue] = state

        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            do {
                guard let data = try handle.read(upToCount: 65536) else {
                    handle.readabilityHandler = nil
                    try? handle.close()
                    return
                }
                if data.isEmpty {
                    handle.readabilityHandler = nil
                    try? handle.close()
                    return
                }
                if let output = String(data: data, encoding: .utf8) {
                    Task {
                        await self?.appendOutput(terminalId: terminalIdValue, output: output)
                    }
                }
            } catch {
                handle.readabilityHandler = nil
            }
        }

        errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            do {
                guard let data = try handle.read(upToCount: 65536) else {
                    handle.readabilityHandler = nil
                    try? handle.close()
                    return
                }
                if data.isEmpty {
                    handle.readabilityHandler = nil
                    try? handle.close()
                    return
                }
                if let output = String(data: data, encoding: .utf8) {
                    Task {
                        await self?.appendOutput(terminalId: terminalIdValue, output: output)
                    }
                }
            } catch {
                handle.readabilityHandler = nil
            }
        }

        try process.run()
        return CreateTerminalResponse(terminalId: terminalId, _meta: nil)
    }

    /// Get output from a terminal process
    public func handleTerminalOutput(terminalId: TerminalId, sessionId: String) async throws -> TerminalOutputResponse {
        guard var state = terminals[terminalId.value] else {
            throw TerminalError.terminalNotFound(terminalId.value)
        }

        guard !state.isReleased else {
            throw TerminalError.terminalReleased(terminalId.value)
        }

        drainAvailableOutput(terminalId: terminalId.value, process: state.process)
        state = terminals[terminalId.value] ?? state

        let exitStatus: TerminalExitStatus?
        if state.process.isRunning {
            exitStatus = nil
        } else {
            exitStatus = TerminalExitStatus(
                exitCode: Int(state.process.terminationStatus),
                signal: nil,
                _meta: nil
            )
        }

        return TerminalOutputResponse(
            output: state.outputBuffer,
            exitStatus: exitStatus,
            truncated: state.wasTruncated,
            _meta: nil
        )
    }

    /// Wait for a terminal process to exit
    public func handleTerminalWaitForExit(terminalId: TerminalId, sessionId: String) async throws -> WaitForExitResponse {
        guard let state = terminals[terminalId.value] else {
            throw TerminalError.terminalNotFound(terminalId.value)
        }

        guard !state.isReleased else {
            throw TerminalError.terminalReleased(terminalId.value)
        }

        if !state.process.isRunning {
            return WaitForExitResponse(
                exitCode: Int(state.process.terminationStatus),
                signal: nil,
                _meta: nil
            )
        }

        let result = await withCheckedContinuation { continuation in
            var waiterState = state
            waiterState.exitWaiters.append(continuation)
            terminals[terminalId.value] = waiterState

            Task {
                await self.monitorProcessExit(terminalId: terminalId)
            }
        }

        return WaitForExitResponse(
            exitCode: result.exitCode,
            signal: result.signal,
            _meta: nil
        )
    }

    /// Kill a terminal process
    public func handleTerminalKill(terminalId: TerminalId, sessionId: String) async throws -> KillTerminalResponse {
        guard var state = terminals[terminalId.value] else {
            throw TerminalError.terminalNotFound(terminalId.value)
        }

        guard !state.isReleased else {
            throw TerminalError.terminalReleased(terminalId.value)
        }

        if state.process.isRunning {
            state.process.terminate()
            state.process.waitUntilExit()
        }

        let exitCode = Int(state.process.terminationStatus)
        for waiter in state.exitWaiters {
            waiter.resume(returning: (exitCode, nil))
        }
        state.exitWaiters.removeAll()
        terminals[terminalId.value] = state

        return KillTerminalResponse(success: true, _meta: nil)
    }

    /// Release a terminal process
    public func handleTerminalRelease(terminalId: TerminalId, sessionId: String) async throws -> ReleaseTerminalResponse {
        guard var state = terminals[terminalId.value] else {
            throw TerminalError.terminalNotFound(terminalId.value)
        }

        if state.process.isRunning {
            state.process.terminate()
            state.process.waitUntilExit()
        }

        cleanupProcessPipes(state.process, terminalId: terminalId.value)
        state = terminals[terminalId.value] ?? state

        let exitCode = Int(state.process.terminationStatus)
        for waiter in state.exitWaiters {
            waiter.resume(returning: (exitCode, nil))
        }

        cacheReleasedOutput(
            terminalId: terminalId.value,
            output: state.outputBuffer,
            exitCode: exitCode
        )

        state.isReleased = true
        state.exitWaiters.removeAll()
        terminals.removeValue(forKey: terminalId.value)

        return ReleaseTerminalResponse(success: true, _meta: nil)
    }

    /// Clean up all terminals
    public func cleanup() async {
        for (_, state) in terminals {
            if state.process.isRunning {
                state.process.terminate()
                state.process.waitUntilExit()
            }
            cleanupProcessPipes(state.process)
            let exitCode = Int(state.process.terminationStatus)
            for waiter in state.exitWaiters {
                waiter.resume(returning: (exitCode, nil))
            }
        }
        terminals.removeAll()
        releasedOutputs.removeAll()
        releasedOutputOrder.removeAll()
    }

    // MARK: - Public Helpers

    /// Get terminal output for display
    public func getOutput(terminalId: TerminalId) -> String? {
        if let state = terminals[terminalId.value] {
            drainAvailableOutput(terminalId: terminalId.value, process: state.process)
            return terminals[terminalId.value]?.outputBuffer ?? state.outputBuffer
        }
        return releasedOutputs[terminalId.value]?.output
    }

    /// Check if terminal is still running
    public func isRunning(terminalId: TerminalId) -> Bool {
        return terminals[terminalId.value]?.process.isRunning ?? false
    }

    private func drainAvailableOutput(terminalId: String, process: Process) {
        guard process.isRunning else { return }

        if let outputPipe = process.standardOutput as? Pipe {
            let handle = outputPipe.fileHandleForReading
            do {
                if let data = try handle.read(upToCount: 65536), !data.isEmpty,
                   let output = String(data: data, encoding: .utf8) {
                    appendOutput(terminalId: terminalId, output: output)
                }
            } catch {
                // File handle closed
            }
        }
        if let errorPipe = process.standardError as? Pipe {
            let handle = errorPipe.fileHandleForReading
            do {
                if let data = try handle.read(upToCount: 65536), !data.isEmpty,
                   let output = String(data: data, encoding: .utf8) {
                    appendOutput(terminalId: terminalId, output: output)
                }
            } catch {
                // File handle closed
            }
        }
    }

    // MARK: - Private Helpers

    private func appendOutput(terminalId: String, output: String) {
        guard var state = terminals[terminalId] else { return }

        state.outputBuffer += output

        if let limit = state.outputByteLimit, state.outputBuffer.count > limit {
            let startIndex = state.outputBuffer.index(
                state.outputBuffer.startIndex,
                offsetBy: state.outputBuffer.count - limit
            )
            state.outputBuffer = String(state.outputBuffer[startIndex...])
            state.wasTruncated = true
        }

        terminals[terminalId] = state
    }

    private func cacheReleasedOutput(terminalId: String, output: String, exitCode: Int) {
        releasedOutputs[terminalId] = ReleasedTerminalOutput(output: output, exitCode: exitCode)
        releasedOutputOrder.removeAll { $0 == terminalId }
        releasedOutputOrder.append(terminalId)

        while releasedOutputOrder.count > maxReleasedOutputEntries,
              let oldest = releasedOutputOrder.first {
            releasedOutputOrder.removeFirst()
            releasedOutputs.removeValue(forKey: oldest)
        }
    }

    private func monitorProcessExit(terminalId: TerminalId) async {
        guard let state = terminals[terminalId.value] else { return }
        let process = state.process

        while process.isRunning {
            try? await Task.sleep(nanoseconds: 100_000_000)
            guard terminals[terminalId.value] != nil else { return }
        }

        guard var currentState = terminals[terminalId.value],
              !currentState.exitWaiters.isEmpty else { return }

        let exitCode = Int(process.terminationStatus)
        for waiter in currentState.exitWaiters {
            waiter.resume(returning: (exitCode, nil))
        }
        currentState.exitWaiters.removeAll()
        terminals[terminalId.value] = currentState
    }

    private func parseCommandString(_ command: String) throws -> (String, [String]) {
        var executable: String?
        var args: [String] = []
        var currentArg = ""
        var inQuotes = false
        var escapeNext = false

        for char in command {
            if escapeNext {
                currentArg.append(char)
                escapeNext = false
                continue
            }

            if char == "\\" {
                escapeNext = true
                continue
            }

            if char == "\"" {
                inQuotes = !inQuotes
                continue
            }

            if char == " " && !inQuotes {
                if !currentArg.isEmpty {
                    if executable == nil {
                        executable = currentArg
                    } else {
                        args.append(currentArg)
                    }
                    currentArg = ""
                }
                continue
            }

            currentArg.append(char)
        }

        if !currentArg.isEmpty {
            if executable == nil {
                executable = currentArg
            } else {
                args.append(currentArg)
            }
        }

        guard let exec = executable, !exec.isEmpty else {
            throw TerminalError.commandParsingFailed(command)
        }

        return (exec, args)
    }

    private func resolveExecutablePath(_ command: String) throws -> String {
        let fileManager = FileManager.default

        if command.hasPrefix("/") {
            if fileManager.fileExists(atPath: command) {
                return command
            }
            throw TerminalError.executableNotFound(command)
        }

        let commonPaths = [
            "/usr/local/bin/\(command)",
            "/usr/bin/\(command)",
            "/bin/\(command)",
            "/opt/homebrew/bin/\(command)",
            "/opt/local/bin/\(command)",
        ]

        for path in commonPaths {
            if fileManager.fileExists(atPath: path) {
                return path
            }
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [command]

        let pipe = Pipe()
        process.standardOutput = pipe

        defer {
            try? pipe.fileHandleForReading.close()
        }

        do {
            try process.run()
            process.waitUntilExit()
            if let data = try? pipe.fileHandleForReading.read(upToCount: 4096),
               let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                if !path.isEmpty && FileManager.default.fileExists(atPath: path) {
                    return path
                }
            }
        } catch {
            // Fallback if 'which' fails
        }

        throw TerminalError.executableNotFound(command)
    }
}

// MARK: - Typealiases for backward compatibility

@available(*, deprecated, renamed: "TerminalDelegate")
public typealias ACPTerminalDelegate = TerminalDelegate

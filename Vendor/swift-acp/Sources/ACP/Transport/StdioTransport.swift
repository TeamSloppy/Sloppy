//
//  StdioTransport.swift
//  ACP
//
//  STDIO-based transport for subprocess communication
//

import Foundation
import ACPModel

/// Transport implementation using STDIO pipes for subprocess communication.
/// This transport launches and manages a subprocess, communicating via stdin/stdout.
public actor StdioTransport: Transport {
    // MARK: - Properties

    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?

    private var readBuffer: Data = Data()
    private let configuration: TransportConfiguration
    private let logger: Logger

    private var messageContinuation: AsyncStream<Data>.Continuation?
    private let messageStream: AsyncStream<Data>

    private let encoder: JSONEncoder

    // MARK: - Transport Protocol

    public nonisolated var messages: AsyncStream<Data> {
        messageStream
    }

    public var isConnected: Bool {
        process?.isRunning == true
    }

    // MARK: - Initialization

    public init(configuration: TransportConfiguration = .default) {
        self.configuration = configuration
        self.logger = Logger.forCategory("StdioTransport")
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.withoutEscapingSlashes]

        var continuation: AsyncStream<Data>.Continuation!
        self.messageStream = AsyncStream { cont in
            continuation = cont
        }
        self.messageContinuation = continuation
    }

    // MARK: - Lifecycle

    /// Launch a subprocess with the given executable path and arguments
    public func launch(
        executablePath: String,
        arguments: [String] = [],
        workingDirectory: String? = nil,
        environment: [String: String]? = nil
    ) throws {
        guard process == nil else {
            throw ClientError.transportError("Transport already has an active process")
        }

        let proc = Process()

        // Resolve symlinks
        let resolvedPath = (try? FileManager.default.destinationOfSymbolicLink(atPath: executablePath)) ?? executablePath
        let actualPath = resolvedPath.hasPrefix("/") ? resolvedPath : ((executablePath as NSString).deletingLastPathComponent as NSString).appendingPathComponent(resolvedPath)

        // Check for Node.js scripts
        let isNodeScript: Bool = {
            guard let handle = FileHandle(forReadingAtPath: actualPath) else { return false }
            defer { try? handle.close() }
            guard let data = try? handle.read(upToCount: 64),
                  let firstLine = String(data: data, encoding: .utf8) else { return false }
            return firstLine.hasPrefix("#!/usr/bin/env node")
        }()

        if isNodeScript {
            let searchPaths = [
                (executablePath as NSString).deletingLastPathComponent,
                (actualPath as NSString).deletingLastPathComponent,
                "/opt/homebrew/bin",
                "/usr/local/bin",
                "/usr/bin"
            ]

            var foundNode: String?
            for searchPath in searchPaths {
                let nodePath = (searchPath as NSString).appendingPathComponent("node")
                if FileManager.default.fileExists(atPath: nodePath) {
                    foundNode = nodePath
                    break
                }
            }

            if let nodePath = foundNode {
                proc.executableURL = URL(fileURLWithPath: nodePath)
                proc.arguments = [actualPath] + arguments
            } else {
                proc.executableURL = URL(fileURLWithPath: executablePath)
                proc.arguments = arguments
            }
        } else {
            proc.executableURL = URL(fileURLWithPath: executablePath)
            proc.arguments = arguments
        }

        // Set up environment
        var env = ShellEnvironment.loadUserShellEnvironment()

        if let customEnvironment = environment {
            for (key, value) in customEnvironment {
                env[key] = value
            }
        }

        if let workingDirectory, !workingDirectory.isEmpty {
            env["PWD"] = workingDirectory
            env["OLDPWD"] = workingDirectory
            proc.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        }

        let agentDir = (executablePath as NSString).deletingLastPathComponent
        if let existingPath = env["PATH"] {
            env["PATH"] = "\(agentDir):\(existingPath)"
        } else {
            env["PATH"] = agentDir
        }

        proc.environment = env

        // Set up pipes
        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()

        proc.standardInput = stdin
        proc.standardOutput = stdout
        proc.standardError = stderr

        stdinPipe = stdin
        stdoutPipe = stdout
        stderrPipe = stderr

        proc.terminationHandler = { [weak self] process in
            Task {
                await self?.handleTermination(exitCode: process.terminationStatus)
            }
        }

        try proc.run()
        process = proc

        startReading()
        startReadingStderr()
    }

    public func send(_ data: Data) async throws {
        guard let stdin = stdinPipe?.fileHandleForWriting else {
            throw ClientError.transportError("Transport not connected")
        }

        var lineData = data
        lineData.append(0x0A) // newline

        try stdin.write(contentsOf: lineData)
    }

    public func close() async {
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil

        try? stdinPipe?.fileHandleForWriting.close()
        try? stdoutPipe?.fileHandleForReading.close()
        try? stderrPipe?.fileHandleForReading.close()

        if let proc = process, proc.isRunning {
            proc.terminate()
        }

        messageContinuation?.finish()

        process = nil
        stdinPipe = nil
        stdoutPipe = nil
        stderrPipe = nil
        readBuffer.removeAll()
    }

    // MARK: - Private Methods

    private func startReading() {
        guard let stdout = stdoutPipe?.fileHandleForReading else { return }

        stdout.readabilityHandler = { [weak self] handle in
            let data = handle.availableData

            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }

            Task {
                await self?.processIncomingData(data)
            }
        }
    }

    private func startReadingStderr() {
        guard let stderr = stderrPipe?.fileHandleForReading else { return }

        stderr.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            // Discard stderr output
        }
    }

    private func processIncomingData(_ data: Data) async {
        readBuffer.append(data)
        await drainBufferedMessages()
    }

    private func drainBufferedMessages() async {
        while let message = popNextMessage() {
            messageContinuation?.yield(message)
        }
    }

    private func popNextMessage() -> Data? {
        let whitespace: Set<UInt8> = [0x20, 0x09, 0x0D, 0x0A]

        while true {
            while let first = readBuffer.first, whitespace.contains(first) {
                readBuffer.removeFirst()
            }

            guard !readBuffer.isEmpty else {
                return nil
            }

            guard let first = readBuffer.first else { return nil }

            // Must start with { or [
            if first != 0x7B && first != 0x5B {
                if let newline = readBuffer.firstIndex(of: 0x0A) {
                    let removeCount = readBuffer.distance(from: readBuffer.startIndex, to: newline) + 1
                    readBuffer.removeFirst(min(removeCount, readBuffer.count))
                    continue
                }

                if readBuffer.count > 4096 {
                    readBuffer.removeAll(keepingCapacity: true)
                }
                return nil
            }

            break
        }

        let bytes = Array(readBuffer)

        var depth = 0
        var inString = false
        var escaped = false

        for endIndex in 0..<bytes.count {
            let byte = bytes[endIndex]

            if inString {
                if escaped {
                    escaped = false
                    continue
                }
                if byte == 0x5C { // backslash
                    escaped = true
                    continue
                }
                if byte == 0x22 { // quote
                    inString = false
                }
                continue
            }

            if byte == 0x22 { // quote
                inString = true
                continue
            }

            if byte == 0x7B || byte == 0x5B { // { or [
                depth += 1
            } else if byte == 0x7D || byte == 0x5D { // } or ]
                depth -= 1
                if depth == 0 {
                    let messageData = Data(bytes[0...endIndex])
                    let removeCount = min(endIndex + 1, readBuffer.count)
                    readBuffer.removeFirst(removeCount)
                    return messageData
                }
            }
        }

        return nil
    }

    private func handleTermination(exitCode: Int32) async {
        logger.info("Process terminated with exit code: \(exitCode)")
        messageContinuation?.finish()
    }
}

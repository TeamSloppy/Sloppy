//
//  StdinTransport.swift
//  ACP
//
//  Transport for agents that read from stdin and write to stdout
//

import Foundation
import ACPModel

/// Transport for agents running as subprocesses.
/// Reads JSON-RPC messages from stdin and writes responses to stdout.
public actor StdinTransport: Transport {
    // MARK: - Properties

    private var readBuffer: Data = Data()
    private var isRunning = false
    private let logger: Logger

    private var messageContinuation: AsyncStream<Data>.Continuation?
    private let messageStream: AsyncStream<Data>

    // MARK: - Transport Protocol

    public nonisolated var messages: AsyncStream<Data> {
        messageStream
    }

    public var isConnected: Bool {
        isRunning
    }

    // MARK: - Initialization

    public init() {
        self.logger = Logger.forCategory("StdinTransport")

        var continuation: AsyncStream<Data>.Continuation!
        self.messageStream = AsyncStream { cont in
            continuation = cont
        }
        self.messageContinuation = continuation
    }

    // MARK: - Public Methods

    /// Start reading from stdin
    public func start() async {
        isRunning = true

        // Read from stdin in a background task
        Task {
            let stdin = FileHandle.standardInput

            while isRunning {
                let data = stdin.availableData

                if data.isEmpty {
                    // EOF reached
                    break
                }

                await processIncomingData(data)
            }

            messageContinuation?.finish()
        }
    }

    public func send(_ data: Data) async throws {
        var output = data
        output.append(0x0A) // newline

        FileHandle.standardOutput.write(output)
    }

    public func close() async {
        isRunning = false
        messageContinuation?.finish()
    }

    // MARK: - Private Methods

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
                if byte == 0x5C {
                    escaped = true
                    continue
                }
                if byte == 0x22 {
                    inString = false
                }
                continue
            }

            if byte == 0x22 {
                inString = true
                continue
            }

            if byte == 0x7B || byte == 0x5B {
                depth += 1
            } else if byte == 0x7D || byte == 0x5D {
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
}

//
//  StdinTransport.swift
//  ACP
//
//  Transport for agents that read from stdin and write to stdout
//

import Foundation
import ACPModel
#if os(Windows)
import Dispatch
import WinSDK
#endif

/// Transport for agents running as subprocesses.
/// Reads JSON-RPC messages from stdin and writes responses to stdout.
public actor StdinTransport: Transport {
    // MARK: - Properties

    private var readBuffer: Data = Data()
    private var isRunning = false
    private let logger: Logger
    private let input: FileHandle
    private let output: FileHandle
    private var readerTask: Task<Void, Never>?
    #if os(Windows)
    private var inputTimer: DispatchSourceTimer?
    #endif

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

    public init(input: FileHandle = .standardInput, output: FileHandle = .standardOutput) {
        self.logger = Logger.forCategory("StdinTransport")
        self.input = input
        self.output = output

        var continuation: AsyncStream<Data>.Continuation!
        self.messageStream = AsyncStream { cont in
            continuation = cont
        }
        self.messageContinuation = continuation
    }

    // MARK: - Public Methods

    /// Start reading from stdin
    public func start() async {
        guard !isRunning else { return }
        isRunning = true

        // One stream consumer preserves byte order. Input readiness must not
        // block the cooperative executor or Foundation's Windows I/O callbacks.
        let chunks = AsyncStream<Data>.makeStream()
        #if os(Windows)
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "sloppy.acp.stdin"))
        timer.schedule(deadline: .now(), repeating: .milliseconds(10))
        // This is the only reader. Reading at most PeekNamedPipe's byte count
        // cannot wait for the next request, so async request handlers stay live.
        timer.setEventHandler { [input] in
            var available: DWORD = 0
            guard PeekNamedPipe(input._handle, nil, 0, nil, &available, nil) else {
                chunks.continuation.finish()
                return
            }
            guard available > 0 else { return }
            var bytes = [UInt8](repeating: 0, count: Int(min(available, 65_536)))
            var count: DWORD = 0
            guard ReadFile(input._handle, &bytes, DWORD(bytes.count), &count, nil), count > 0 else {
                chunks.continuation.finish()
                return
            }
            chunks.continuation.yield(Data(bytes.prefix(Int(count))))
        }
        inputTimer = timer
        timer.resume()
        #else
        input.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                chunks.continuation.finish()
            } else {
                chunks.continuation.yield(data)
            }
        }
        #endif
        readerTask = Task {
            for await data in chunks.stream {
                guard !Task.isCancelled else { break }
                await processIncomingData(data)
            }
            finishMessages()
        }
    }

    public func send(_ data: Data) async throws {
        var output = data
        output.append(0x0A) // newline

        self.output.write(output)
    }

    public func close() async {
        isRunning = false
        stopReading()
        readerTask?.cancel()
        readerTask = nil
        messageContinuation?.finish()
    }

    // MARK: - Private Methods

    private func finishMessages() {
        isRunning = false
        stopReading()
        messageContinuation?.finish()
    }

    private func stopReading() {
        #if os(Windows)
        inputTimer?.cancel()
        inputTimer = nil
        #else
        input.readabilityHandler = nil
        #endif
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

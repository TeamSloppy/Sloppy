#if os(Windows)
import Foundation
import Logging
import MCP
import WinSDK

/// The MCP SDK's POSIX stdio transport is unavailable on Windows.
actor StdioTransport: Transport {
    nonisolated let logger: Logger
    private let input: FileHandle
    private let output: FileHandle
    private let stream: AsyncThrowingStream<Data, Error>
    private let continuation: AsyncThrowingStream<Data, Error>.Continuation
    private var timer: DispatchSourceTimer?
    private var pending = Data()

    init(input: FileHandle, output: FileHandle, logger: Logger) {
        self.input = input
        self.output = output
        self.logger = logger
        let (stream, continuation) = AsyncThrowingStream<Data, Error>.makeStream()
        self.stream = stream
        self.continuation = continuation
    }

    func connect() async throws {
        guard timer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now(), repeating: .milliseconds(10))
        timer.setEventHandler { [weak self] in Task { await self?.readAvailable() } }
        self.timer = timer
        timer.resume()
    }

    func disconnect() async {
        timer?.cancel()
        timer = nil
        continuation.finish()
    }

    func send(_ data: Data) async throws {
        var frame = data
        if frame.last != 10 { frame.append(10) }
        try output.write(contentsOf: frame)
    }

    func receive() -> AsyncThrowingStream<Data, Error> { stream }

    private func readAvailable() {
        guard timer != nil else { return }
        let handle = input._handle
        var available: DWORD = 0
        guard PeekNamedPipe(handle, nil, 0, nil, &available, nil) else {
            timer?.cancel()
            timer = nil
            continuation.finish(throwing: MCPRegistryError.invalidResult("MCP server closed its output stream."))
            return
        }
        guard available > 0 else { return }
        var bytes = [UInt8](repeating: 0, count: Int(min(available, 65_536)))
        var count: DWORD = 0
        guard ReadFile(handle, &bytes, DWORD(bytes.count), &count, nil), count > 0 else { return }
        pending.append(contentsOf: bytes.prefix(Int(count)))
        while let end = pending.firstIndex(of: 10) {
            let frame = Data(pending[..<end])
            pending = Data(pending[(end + 1)...])
            if !frame.isEmpty { continuation.yield(frame) }
        }
    }
}
#endif

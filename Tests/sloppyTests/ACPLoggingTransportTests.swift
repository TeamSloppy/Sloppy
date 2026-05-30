import ACP
import ACPModel
import Foundation
import Logging
import Testing
@testable import sloppy

private typealias ACPLoggingTransportTestLogger = Logging.Logger

private final class ACPLoggingTransportLogRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var records: [(level: ACPLoggingTransportTestLogger.Level, message: String, metadata: [String: String])] = []

    func append(
        level: ACPLoggingTransportTestLogger.Level,
        message: ACPLoggingTransportTestLogger.Message,
        metadata: ACPLoggingTransportTestLogger.Metadata
    ) {
        lock.withLock {
            records.append((
                level: level,
                message: message.description,
                metadata: metadata.mapValues { String(describing: $0) }
            ))
        }
    }

    func snapshot() -> [(level: ACPLoggingTransportTestLogger.Level, message: String, metadata: [String: String])] {
        lock.withLock { records }
    }
}

private struct ACPLoggingTransportRecordingLogHandler: LogHandler {
    let label: String
    let recorder: ACPLoggingTransportLogRecorder
    var metadata: ACPLoggingTransportTestLogger.Metadata = [:]
    var logLevel: ACPLoggingTransportTestLogger.Level = .trace

    subscript(metadataKey key: String) -> ACPLoggingTransportTestLogger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }

    func log(event: LogEvent) {
        var merged = metadata
        if let explicitMetadata = event.metadata {
            for (key, value) in explicitMetadata {
                merged[key] = value
            }
        }
        recorder.append(level: event.level, message: event.message, metadata: merged)
    }
}

private actor FakeACPTransport: Transport {
    private let continuation: AsyncStream<Data>.Continuation
    nonisolated let messages: AsyncStream<Data>
    private(set) var sent: [Data] = []

    init() {
        var continuation: AsyncStream<Data>.Continuation!
        self.messages = AsyncStream { cont in
            continuation = cont
        }
        self.continuation = continuation
    }

    var isConnected: Bool { true }

    func send(_ data: Data) async throws {
        sent.append(data)
    }

    func close() async {
        continuation.finish()
    }

    func emit(_ data: Data) {
        continuation.yield(data)
    }
}

private func makeACPLoggingTransportLogger(
    _ recorder: ACPLoggingTransportLogRecorder
) -> ACPLoggingTransportTestLogger {
    ACPLoggingTransportTestLogger(label: "test.acp.logging-transport") { label in
        ACPLoggingTransportRecordingLogHandler(label: label, recorder: recorder)
    }
}

@Test
func acpLoggingTransportLogsInboundAndOutboundMethodFrames() async throws {
    let recorder = ACPLoggingTransportLogRecorder()
    let inner = FakeACPTransport()
    let transport = ACPLoggingTransport(
        wrapping: inner,
        logger: makeACPLoggingTransportLogger(recorder)
    )

    let inbound = #"{"jsonrpc":"2.0","id":1,"method":"session/new","params":{"cwd":"/tmp","mcpServers":[]}}"#
    await inner.emit(Data(inbound.utf8))
    var iterator = transport.messages.makeAsyncIterator()
    _ = await iterator.next()

    let response = JSONRPCResponse(id: .number(1), result: nil, error: nil)
    try await transport.send(JSONEncoder().encode(response))

    let logs = recorder.snapshot()
    #expect(logs.contains { record in
        record.message == "ACP stdio frame"
            && record.metadata["direction"] == "inbound"
            && record.metadata["method"] == "session/new"
    })
    #expect(logs.contains { record in
        record.message == "ACP stdio frame"
            && record.metadata["direction"] == "outbound"
            && record.metadata["id"] == "1"
    })
}

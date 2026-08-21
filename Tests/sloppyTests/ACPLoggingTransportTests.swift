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
            && record.metadata["payload"] == inbound
    })
    #expect(logs.contains { record in
        record.message == "ACP stdio frame"
            && record.metadata["direction"] == "outbound"
            && record.metadata["id"] == "1"
    })
}

@Test
func acpServerRoutingTransportHandlesSessionConfigRequests() async throws {
    let inner = FakeACPTransport()
    let transport = ACPServerRequestRoutingTransport(wrapping: inner)
    await transport.setConfigOptionHandler { request in
        #expect(request.configId.value == "mode")
        return SetSessionConfigOptionResponse(configOptions: [])
    }
    await transport.start()

    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    let paramsData = try encoder.encode(
        SetSessionConfigOptionRequest(
            sessionId: SessionId("session-1"),
            configId: SessionConfigId("mode"),
            value: SessionConfigValueId("plan")
        )
    )
    let params = try decoder.decode(AnyCodable.self, from: paramsData)
    let request = JSONRPCRequest(
        id: .number(7),
        method: "session/set_config_option",
        params: params
    )
    await inner.emit(try encoder.encode(request))

    for _ in 0..<100 {
        if !(await inner.sent.isEmpty) { break }
        try await Task.sleep(for: .milliseconds(5))
    }
    let responseData = try #require(await inner.sent.first)
    let response = try decoder.decode(JSONRPCResponse.self, from: responseData)

    #expect(response.id == .number(7))
    #expect(response.error == nil)
    #expect(response.result != nil)
    await transport.close()
}

@Test
func acpServerRoutingTransportRoundTripsPermissionRequests() async throws {
    let inner = FakeACPTransport()
    let transport = ACPServerRequestRoutingTransport(wrapping: inner)
    await transport.start()
    let permissionTask = Task {
        try await transport.requestPermission(
            ACPServerPermissionRequest(
                sessionId: SessionId("session-1"),
                toolCall: .init(
                    toolCallId: "call-1",
                    title: "runtime.exec",
                    kind: "execute",
                    status: "pending",
                    rawInput: AnyCodable(["command": "/bin/echo"])
                ),
                options: [
                    PermissionOption(kind: "allow_once", name: "Allow Once", optionId: "allow_once")
                ]
            )
        )
    }

    for _ in 0..<100 {
        if !(await inner.sent.isEmpty) { break }
        try await Task.sleep(for: .milliseconds(5))
    }
    let requestData = try #require(await inner.sent.first)
    let decoder = JSONDecoder()
    let encoder = JSONEncoder()
    let request = try decoder.decode(JSONRPCRequest.self, from: requestData)
    #expect(request.method == "session/request_permission")
    let paramsData = try encoder.encode(try #require(request.params))
    let params = try decoder.decode(ACPServerPermissionRequest.self, from: paramsData)
    #expect(params.toolCall.status == "pending")

    let outcome = RequestPermissionResponse(outcome: PermissionOutcome(optionId: "allow_once"))
    let result = try decoder.decode(AnyCodable.self, from: encoder.encode(outcome))
    await inner.emit(try encoder.encode(JSONRPCResponse(id: request.id, result: result, error: nil)))
    let response = try await permissionTask.value

    #expect(response.outcome.optionId == "allow_once")
    await transport.close()
}

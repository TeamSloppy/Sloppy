import ACPModel
import Foundation
import Logging
import Testing
@testable import sloppy

private typealias TransportTestLogger = Logging.Logger

private final class ACPTransportLogRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var records: [(level: TransportTestLogger.Level, message: String, metadata: [String: String])] = []

    func append(
        level: TransportTestLogger.Level,
        message: TransportTestLogger.Message,
        metadata: TransportTestLogger.Metadata
    ) {
        lock.withLock {
            records.append((
                level: level,
                message: message.description,
                metadata: metadata.mapValues { String(describing: $0) }
            ))
        }
    }

    func snapshot() -> [(level: TransportTestLogger.Level, message: String, metadata: [String: String])] {
        lock.withLock { records }
    }
}

private struct ACPTransportRecordingLogHandler: LogHandler {
    let label: String
    let recorder: ACPTransportLogRecorder
    var metadata: TransportTestLogger.Metadata = [:]
    var logLevel: TransportTestLogger.Level = .trace

    subscript(metadataKey key: String) -> TransportTestLogger.Metadata.Value? {
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

private func makeACPTransportRecordingLogger(_ recorder: ACPTransportLogRecorder) -> TransportTestLogger {
    TransportTestLogger(label: "test.acp.transport") { label in
        ACPTransportRecordingLogHandler(label: label, recorder: recorder)
    }
}

@Test
func webSocketTransportLogsThrowingMethodFailuresBeforeRethrow() async throws {
    let recorder = ACPTransportLogRecorder()
    let client = try WebSocketACPClient(
        target: CoreConfig.ACP.Target(
            id: "ws",
            title: "WebSocket",
            transport: .websocket,
            url: "ws://127.0.0.1:9/acp"
        ),
        logger: makeACPTransportRecordingLogger(recorder)
    )

    do {
        _ = try await client.newSession(workingDirectory: "/tmp", timeout: nil)
        Issue.record("Expected newSession to throw while disconnected.")
    } catch {
        let logs = recorder.snapshot()
        #expect(logs.contains { record in
            record.level == .error
                && record.message == "ACP transport method failed"
                && record.metadata["method"] == "session/new"
                && record.metadata["transport"] == "websocket"
        })
    }
}

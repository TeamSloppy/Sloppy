#if DEBUG
import Foundation
#endif
import Logging
import OSLog

enum ClientLogging {
    private static let bootstrapOnce: Void = {
        LoggingSystem.bootstrap { label in
            var handler = StreamLogHandler.standardOutput(label: label)
            #if DEBUG
            handler.logLevel = .debug
            #else
            handler.logLevel = .info
            #endif
            #if DEBUG
            var combined = MultiplexLogHandler([
                handler, ClientNetworkFileLogHandler(label: label), ClientNetworkUnifiedLogHandler(label: label),
            ])
            combined.logLevel = .debug
            return combined
            #else
            return MultiplexLogHandler([handler, ClientNetworkUnifiedLogHandler(label: label)])
            #endif
        }
    }()

    static func bootstrap() {
        _ = bootstrapOnce
    }
}

private struct ClientNetworkUnifiedLogHandler: LogHandler {
    let label: String
    var metadata: Logging.Logger.Metadata = [:]
    var logLevel: Logging.Logger.Level = .info
    private static let logger = OSLog(subsystem: "team.sloppy.client", category: "Connection")

    subscript(metadataKey key: String) -> Logging.Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }

    func log(level: Logging.Logger.Level, message: Logging.Logger.Message, metadata extra: Logging.Logger.Metadata?,
             source: String, file: String, function: String, line: UInt) {
        let event = String(describing: message)
        switch (label, event) {
        case ("sloppy.backend-http", "http.request.completed") where level >= .warning:
            break
        case ("sloppy.backend-http", "http.request.failed"),
             ("sloppy.backend-http", "http.request.network-timing"),
             ("sloppy.connection-monitor", "connection.health.failed"),
             ("sloppy.connection-monitor", "connection.health.recovered"):
            break
        default:
            return
        }
        let keys = ["request_id", "elapsed", "error_domain", "error_code", "total_ms", "dns_ms",
                    "connect_ms", "tls_ms", "first_byte_ms", "download_ms", "reused_connection", "attempt", "in_flight", "status"]
        let fields = keys.compactMap { key in
            (extra?[key] ?? metadata[key]).map { "\(key)=\($0)" }
        }.joined(separator: " ")
        os_log("%{public}@ %{public}@", log: Self.logger, type: level >= .warning ? .error : .info, event, fields)
    }
}

#if DEBUG
private struct ClientNetworkFileLogHandler: LogHandler {
    let label: String
    var metadata: Logging.Logger.Metadata = [:]
    var logLevel: Logging.Logger.Level = .debug
    subscript(metadataKey key: String) -> Logging.Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }

    func log(level: Logging.Logger.Level, message: Logging.Logger.Message, metadata extra: Logging.Logger.Metadata?,
             source: String, file: String, function: String, line: UInt) {
        let labels: Set<String> = ["sloppy.root-shell", "sloppy.console-account", "sloppy.console-http",
            "sloppy.console-network", "sloppy.console-transport", "sloppy.connection-monitor", "sloppy.backend-http"]
        guard labels.contains(label) else { return }
        var merged = metadata
        if let extra { merged.merge(extra) { _, new in new } }
        for key in ["authorization", "cookie", "token", "access_token", "refresh_token", "body"] {
            merged.removeValue(forKey: key)
        }
        let record: [String: Any] = ["time_ms": Int64(Date().timeIntervalSince1970 * 1_000),
            "label": label, "level": String(describing: level), "event": String(describing: message),
            "metadata": merged.mapValues { String(describing: $0) }]
        guard var data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]),
              data.count <= 8_192 else { return }
        data.append(10)
        ClientNetworkLogFile.shared.append(data)
    }
}

/// Keep diagnostics off the caller's executor, including when the disk stalls.
private final class ClientNetworkLogFile: @unchecked Sendable {
    static let shared = ClientNetworkLogFile()
    private let queue = DispatchQueue(label: "sloppy.client-network-log", qos: .utility)
    private let availableSlots = DispatchSemaphore(value: 128)
    private let directory = (FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        ?? FileManager.default.temporaryDirectory).appendingPathComponent("SloppyNetwork", isDirectory: true)

    func append(_ data: Data) {
        guard availableSlots.wait(timeout: .now()) == .success else { return }
        queue.async {
            defer { self.availableSlots.signal() }
            self.write(data)
        }
    }

    private func write(_ data: Data) {
        let manager = FileManager.default
        let url = directory.appendingPathComponent("client-network.log")
        do {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
            if ((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0) > 512 * 1_024 {
                let previous = directory.appendingPathComponent("client-network.previous.log")
                if manager.fileExists(atPath: previous.path) { try manager.removeItem(at: previous) }
                try manager.moveItem(at: url, to: previous)
            }
            if !manager.fileExists(atPath: url.path) {
                guard manager.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { return }
            }
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch { /* Diagnostic IO must not interfere with the app. */ }
    }
}
#endif

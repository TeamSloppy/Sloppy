import ACP
import ACPModel
import Foundation
import Logging

final class ACPLoggingTransport: Transport, @unchecked Sendable {
    private let wrapped: any Transport
    private let logger: Logging.Logger
    private let decoder = JSONDecoder()

    private let continuation: AsyncStream<Data>.Continuation
    let messages: AsyncStream<Data>

    init(wrapping wrapped: any Transport, logger: Logging.Logger) {
        self.wrapped = wrapped
        self.logger = logger

        var continuation: AsyncStream<Data>.Continuation!
        self.messages = AsyncStream { cont in
            continuation = cont
        }
        self.continuation = continuation

        Task { [wrapped, logger, decoder, continuation] in
            for await data in wrapped.messages {
                Self.logFrame(
                    data,
                    direction: "inbound",
                    logger: logger,
                    decoder: decoder
                )
                continuation?.yield(data)
            }
            continuation?.finish()
        }
    }

    var isConnected: Bool {
        get async {
            await wrapped.isConnected
        }
    }

    func send(_ data: Data) async throws {
        Self.logFrame(
            data,
            direction: "outbound",
            logger: logger,
            decoder: decoder
        )
        try await wrapped.send(data)
    }

    func close() async {
        await wrapped.close()
        continuation.finish()
    }

    private static func logFrame(
        _ data: Data,
        direction: String,
        logger: Logging.Logger,
        decoder: JSONDecoder
    ) {
        var metadata: Logging.Logger.Metadata = [
            "direction": .string(direction),
            "bytes": .stringConvertible(data.count),
        ]
        if let payload = String(data: data, encoding: .utf8) {
            metadata["payload"] = .string(payload)
        } else {
            metadata["payload_base64"] = .string(data.base64EncodedString())
        }

        do {
            let message = try decoder.decode(Message.self, from: data)
            switch message {
            case .request(let request):
                metadata["kind"] = .string("request")
                metadata["method"] = .string(request.method)
                metadata["id"] = .string(request.id.description)
            case .notification(let notification):
                metadata["kind"] = .string("notification")
                metadata["method"] = .string(notification.method)
            case .response(let response):
                metadata["kind"] = .string("response")
                metadata["id"] = .string(response.id.description)
                if let error = response.error {
                    metadata["error"] = .string(error.message)
                }
            }
            logger.info("ACP stdio frame", metadata: metadata)
        } catch {
            metadata["error"] = .string(error.localizedDescription)
            logger.warning("ACP stdio frame decode failed", metadata: metadata)
        }
    }
}

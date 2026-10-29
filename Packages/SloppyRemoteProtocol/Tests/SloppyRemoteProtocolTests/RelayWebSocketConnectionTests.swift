import Foundation
import NIOCore
import NIOEmbedded
import NIOPosix
import NIOWebSocket
import Synchronization
import Testing
@testable import SloppyRemoteProtocol

@Suite("Relay WebSocket readiness")
struct RelayWebSocketConnectionTests {
    @Test func dnsFailureThrowsAndAllowsAnotherConnectionAttempt() async throws {
        // A DNS label longer than 63 bytes is invalid, regardless of connectivity.
        let url = try #require(URL(string: "https://" + String(repeating: "a", count: 256) + ".invalid"))
        let connection = RelayWebSocketConnection()
        for _ in 0..<3 {
            do {
                try await connection.connect(url: url, token: "test")
                Issue.record("An invalid DNS name must fail to connect")
            } catch let error as NIOConnectionError {
                #expect(error.dnsAError is SocketAddressError.UnknownHost)
                #expect(error.dnsAAAAError is SocketAddressError.UnknownHost)
            }
        }
        await connection.close()
    }

    @Test func upgradeWaitsForDeviceRegistrationBeforeBecomingReady() throws {
        let channel = EmbeddedChannel()
        let ready = channel.eventLoop.makePromise(of: Void.self)
        let completions = Mutex<[Bool]>([])
        ready.futureResult.whenComplete { result in
            completions.withLock { $0.append((try? result.get()) != nil) }
        }
        let pair = AsyncThrowingStream<Data, any Error>.makeStream()
        let handler = RelayFrameHandler(continuation: pair.continuation, ready: ready)
        try channel.pipeline.syncOperations.addHandler(handler)
        defer { _ = try? channel.finish() }

        // A ping or an unrelated control frame does not mean registration is done.
        var control = channel.allocator.buffer(capacity: 64)
        control.writeString("{\"type\":\"other\"}")
        try channel.writeInbound(WebSocketFrame(fin: true, opcode: .text, data: control))
        #expect(completions.withLock { $0.isEmpty })

        var registered = channel.allocator.buffer(capacity: 64)
        registered.writeBytes(try JSONEncoder().encode(RemoteRelayReadyFrame()))
        try channel.writeInbound(WebSocketFrame(fin: true, opcode: .text, data: registered))
        #expect(completions.withLock { $0 } == [true])

        // Repeated readiness and closing after success must not resolve twice.
        try channel.writeInbound(WebSocketFrame(fin: true, opcode: .text, data: registered))
        handler.failReadiness(RemoteTLSError.handshakeIncomplete)
        #expect(completions.withLock { $0 } == [true])
    }

    @Test func disconnectBeforeRegistrationFailsReadinessImmediately() throws {
        let channel = EmbeddedChannel()
        let ready = channel.eventLoop.makePromise(of: Void.self)
        let completions = Mutex<[Bool]>([])
        ready.futureResult.whenComplete { result in
            completions.withLock { $0.append((try? result.get()) != nil) }
        }
        let pair = AsyncThrowingStream<Data, any Error>.makeStream()
        let handler = RelayFrameHandler(continuation: pair.continuation, ready: ready)
        try channel.pipeline.syncOperations.addHandler(handler)
        try channel.writeInbound(WebSocketFrame(fin: true, opcode: .connectionClose, data: channel.allocator.buffer(capacity: 0)))
        #expect(completions.withLock { $0 } == [false])
        handler.failReadiness(RemoteTLSError.handshakeIncomplete)
        #expect(completions.withLock { $0 } == [false])
        _ = try channel.finish(acceptAlreadyClosed: true)
    }
}

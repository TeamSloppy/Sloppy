import Foundation
import MCP
import Protocols

actor MCPModernStdio {
    private struct Pending {
        let reply: AsyncThrowingStream<Data, any Error>.Continuation
        let progressToken: JSONValue?
        let onNotification: (@Sendable ([String: JSONValue]) -> Void)?
    }

    private let transport: any Transport
    private let timeoutMs: Int
    private var reader: Task<Void, Never>?
    private var pending: [String: Pending] = [:]
    private var closed = false

    init(transport: any Transport, timeoutMs: Int) {
        self.transport = transport
        self.timeoutMs = max(250, timeoutMs)
    }

    func probe() async throws -> MCPHTTPDiscovery.Server? {
        try await transport.connect()
        try Task.checkCancellation()
        let messages = await transport.receive()
        reader = Task { [weak self] in
            do {
                for try await message in messages { await self?.receive(message) }
                await self?.finish()
            } catch {
                await self?.finish()
            }
        }
        let id = UUID().uuidString
        let raw: Data
        do {
            raw = try await exchange("server/discover", id: id, timeoutMs: timeoutMs / 2)
        } catch {
            try Task.checkCancellation()
            return nil
        }
        return try MCPHTTPDiscovery.discoverStdio(raw, id: id)
    }

    func request(_ method: String, params: [String: JSONValue], capabilities: [String: JSONValue],
                 onNotification: (@Sendable ([String: JSONValue]) -> Void)?) async throws -> [String: JSONValue] {
        let id = UUID().uuidString
        let data = try await exchange(method, id: id, params: params, capabilities: capabilities,
                                      timeoutMs: timeoutMs, onNotification: onNotification)
        return try MCPHTTPDiscovery.decodeStdio(data, id: id)
    }

    private func exchange(_ method: String, id: String, params: [String: JSONValue] = [:],
                          capabilities: [String: JSONValue] = [:], timeoutMs: Int,
                          onNotification: (@Sendable ([String: JSONValue]) -> Void)? = nil) async throws -> Data {
        guard !closed else { throw MCPRegistryError.invalidResult("MCP stdio stream is closed.") }
        let payload = try MCPHTTPDiscovery.body(method: method, id: id, params: params, capabilities: capabilities)
        let (stream, reply) = AsyncThrowingStream<Data, any Error>.makeStream()
        pending[id] = Pending(reply: reply, progressToken: params["_meta"]?.asObject?["progressToken"],
                              onNotification: onNotification)
        let timer = Task {
            do {
                try await Task.sleep(for: .milliseconds(timeoutMs))
                reply.finish(throwing: URLError(.timedOut))
            } catch {}
        }
        defer {
            timer.cancel()
            pending.removeValue(forKey: id)
        }
        try await transport.send(payload)
        var messages = stream.makeAsyncIterator()
        do {
            if let data = try await messages.next() { return data }
            throw CancellationError()
        } catch {
            if method != "server/discover" {
                let packet: JSONValue = .object([
                    "jsonrpc": .string("2.0"), "method": .string("notifications/cancelled"),
                    "params": .object(["requestId": .string(id)])
                ])
                if let data = try? JSONEncoder().encode(packet) { try? await transport.send(data) }
            }
            throw error
        }
    }

    private func receive(_ data: Data) {
        guard data.count <= 8 * 1024 * 1024,
              let packet = (try? JSONDecoder().decode(JSONValue.self, from: data))?.asObject,
              packet["jsonrpc"]?.asString == "2.0" else { return }
        if let id = packet["id"]?.asString, packet["method"] == nil {
            if let reply = pending[id]?.reply {
                reply.yield(data)
                reply.finish()
            }
        } else if packet["method"]?.asString == "notifications/progress",
                  let token = packet["params"]?.asObject?["progressToken"] {
            for request in pending.values where request.progressToken == token {
                request.onNotification?(packet)
            }
        }
    }

    private func finish() {
        closed = true
        for request in pending.values {
            request.reply.finish(throwing: MCPRegistryError.invalidResult("MCP stdio stream is closed."))
        }
        pending.removeAll()
    }

    func isClosed() -> Bool { closed }

    func disconnect() async {
        reader?.cancel()
        finish()
        await transport.disconnect()
    }
}

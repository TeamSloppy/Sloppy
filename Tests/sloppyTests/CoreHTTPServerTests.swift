import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Logging
import Testing
@testable import sloppy
@testable import Protocols

private struct SSEMalformedResponseError: Error {}
private struct WebSocketMalformedResponseError: Error {}

private final class SSEDataCollector: NSObject, @unchecked Sendable, URLSessionDataDelegate {
    private let lock = NSLock()
    private var receivedData = Data()
    private var httpResponse: HTTPURLResponse?
    private var continuation: CheckedContinuation<(HTTPURLResponse, Data), Error>?
    private var task: URLSessionDataTask?

    func start(request: URLRequest) async throws -> (HTTPURLResponse, Data) {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            self.continuation = continuation
            lock.unlock()
            let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
            lock.lock()
            self.task = session.dataTask(with: request)
            lock.unlock()
            self.task?.resume()
            session.finishTasksAndInvalidate()
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        receivedData.append(data)
        let response = httpResponse
        let count = receivedData.count
        let dataCopy = receivedData
        lock.unlock()
        if let response = response, count > 0 {
            let text = String(data: dataCopy, encoding: .utf8) ?? ""
            if text.contains("data: ") {
                lock.lock()
                let cont = continuation
                continuation = nil
                lock.unlock()
                if let cont = cont {
                    dataTask.cancel()
                    cont.resume(returning: (response, dataCopy))
                }
            }
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        lock.lock()
        httpResponse = response as? HTTPURLResponse
        lock.unlock()
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let cont = continuation
        continuation = nil
        let response = httpResponse
        let data = receivedData
        lock.unlock()
        guard let cont = cont else { return }
        if let error = error {
            cont.resume(throwing: error)
        } else if let response = response {
            cont.resume(returning: (response, data))
        } else {
            cont.resume(throwing: SSEMalformedResponseError())
        }
    }
}

private func readFirstSSEEvent(url: URL) async throws -> (HTTPURLResponse, String, Data) {
    var request = URLRequest(url: url)
    request.timeoutInterval = 10

    let collector = SSEDataCollector()
    let (response, data) = try await collector.start(request: request)

    let text = String(data: data, encoding: .utf8) ?? ""
    let lines = text.components(separatedBy: CharacterSet.newlines)

    var eventName = "message"
    for line in lines {
        if line.hasPrefix(":") || line.isEmpty {
            continue
        }
        if line.hasPrefix("event: ") {
            eventName = String(line.dropFirst("event: ".count)).trimmingCharacters(in: .whitespaces)
            continue
        }
        if line.hasPrefix("data: ") {
            let payload = String(line.dropFirst("data: ".count))
            return (response, eventName, Data(payload.utf8))
        }
    }

    throw SSEMalformedResponseError()
}

@Test
func sseStreamEndpointOverHTTPServerReturnsSessionReadyEvent() async throws {
    let config = CoreConfig.test
    let service = CoreService(config: config)
    let router = CoreRouter(service: service)
    let server = CoreHTTPServer(
        host: "127.0.0.1",
        port: 0,
        router: router,
        logger: Logger(label: "sloppy.core.httpserver.tests")
    )
    try server.start()
    defer { try? server.shutdown() }

    guard let boundPort = server.boundPort else {
        throw SSEMalformedResponseError()
    }

    _ = try await service.createAgent(
        AgentCreateRequest(
            id: "agent-http-stream",
            displayName: "Agent HTTP Stream",
            role: "SSE regression"
        )
    )
    let session = try await service.createAgentSession(
        agentID: "agent-http-stream",
        request: AgentSessionCreateRequest(title: "HTTP SSE Session")
    )

    let url = try #require(
        URL(string: "http://127.0.0.1:\(boundPort)/v1/agents/agent-http-stream/sessions/\(session.id)/stream")
    )

    let (httpResponse, eventName, payload) = try await readFirstSSEEvent(url: url)

    #expect(httpResponse.statusCode == 200)
    #expect((httpResponse.value(forHTTPHeaderField: "content-type") ?? "").contains("text/event-stream"))
    #expect(eventName == AgentSessionStreamUpdateKind.sessionReady.rawValue)

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let update = try decoder.decode(AgentSessionStreamUpdate.self, from: payload)
    #expect(update.kind == .sessionReady)
    #expect(update.summary?.id == session.id)
}

@Test
func webSocketSessionStreamPublishesToolEventsOverHTTPServer() async throws {
    let config = CoreConfig.test
    let service = CoreService(config: config)
    let router = CoreRouter(service: service)
    let server = CoreHTTPServer(
        host: "127.0.0.1",
        port: 0,
        router: router,
        logger: Logger(label: "sloppy.core.httpserver.tests")
    )
    try server.start()
    defer { try? server.shutdown() }

    guard let boundPort = server.boundPort else {
        throw WebSocketMalformedResponseError()
    }

    _ = try await service.createAgent(
        AgentCreateRequest(
            id: "agent-http-ws",
            displayName: "Agent HTTP WS",
            role: "WS regression"
        )
    )
    let session = try await service.createAgentSession(
        agentID: "agent-http-ws",
        request: AgentSessionCreateRequest(title: "HTTP WS Session")
    )

    let wsURL = try #require(
        URL(string: "ws://127.0.0.1:\(boundPort)/v1/agents/agent-http-ws/sessions/\(session.id)/ws")
    )
    let webSocket = URLSession.shared.webSocketTask(with: wsURL)
    webSocket.resume()
    defer { webSocket.cancel(with: .normalClosure, reason: nil) }

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    let readyMessage = try await webSocket.receive()
    guard case .string(let readyPayload) = readyMessage else {
        throw WebSocketMalformedResponseError()
    }
    let readyUpdate = try decoder.decode(AgentSessionStreamUpdate.self, from: Data(readyPayload.utf8))
    #expect(readyUpdate.kind == .sessionReady)
    #expect(readyUpdate.summary?.id == session.id)

    async let invocation: ToolInvocationResult = service.invokeToolFromRuntime(
        agentID: "agent-http-ws",
        sessionID: session.id,
        request: ToolInvocationRequest(tool: "sessions.list", arguments: [:], reason: "ws regression")
    )

    let firstEventMessage = try await webSocket.receive()
    let secondEventMessage = try await webSocket.receive()
    _ = await invocation

    let firstPayload = try #require(messagePayload(firstEventMessage))
    let secondPayload = try #require(messagePayload(secondEventMessage))
    let firstUpdate = try decoder.decode(AgentSessionStreamUpdate.self, from: Data(firstPayload.utf8))
    let secondUpdate = try decoder.decode(AgentSessionStreamUpdate.self, from: Data(secondPayload.utf8))

    #expect(firstUpdate.kind == .sessionEvent)
    #expect(firstUpdate.event?.type == .toolCall)
    #expect(firstUpdate.event?.toolCall?.tool == "sessions.list")
    #expect(secondUpdate.kind == .sessionEvent)
    #expect(secondUpdate.event?.type == .toolResult)
    #expect(secondUpdate.event?.toolResult?.tool == "sessions.list")
    #expect(secondUpdate.cursor > firstUpdate.cursor)
}

private func messagePayload(_ message: URLSessionWebSocketTask.Message) -> String? {
    switch message {
    case .string(let payload):
        return payload
    case .data(let payload):
        return String(data: payload, encoding: .utf8)
    @unknown default:
        return nil
    }
}

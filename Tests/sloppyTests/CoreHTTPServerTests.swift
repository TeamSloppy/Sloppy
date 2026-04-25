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
private struct DashboardTerminalClientFrame: Encodable {
    let type: String
    let token: String?
    let projectId: String?
    let cwd: String?
    let cols: Int?
    let rows: Int?
    let data: String?
}
private struct DashboardTerminalServerFrame: Decodable {
    let type: String
    let sessionId: String?
    let cwd: String?
    let shell: String?
    let pid: Int32?
    let data: String?
    let exitCode: Int32?
    let code: String?
    let message: String?
}
private struct AsyncTestTimeoutError: Error {
    let operation: String
}

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
    var mutableRequest = URLRequest(url: url)
    mutableRequest.timeoutInterval = 10
    let request = mutableRequest

    let collector = SSEDataCollector()
    let (response, data) = try await withAsyncTestTimeout(
        operation: "SSE session-ready event"
    ) {
        try await collector.start(request: request)
    }

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

// Linux Foundation uses libcurl for URLSession; WebSocket tasks are not supported there
// (NSURLErrorDomain -1002 "WebSockets not supported by libcurl").
#if !os(Linux)
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

    let readyMessage = try await withAsyncTestTimeout(
        operation: "WebSocket session-ready event"
    ) {
        try await webSocket.receive()
    }
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

    let firstEventMessage = try await withAsyncTestTimeout(
        operation: "WebSocket tool-call event"
    ) {
        try await webSocket.receive()
    }
    let secondEventMessage = try await withAsyncTestTimeout(
        operation: "WebSocket tool-result event"
    ) {
        try await webSocket.receive()
    }
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

@Test
func dashboardTerminalWebSocketAcceptsInputAndAllowsReconnect() async throws {
    var config = CoreConfig.test
    config.ui.dashboardAuth.enabled = true
    config.ui.dashboardAuth.token = "dashboard-secret"
    config.ui.dashboardTerminal.enabled = true
    config.ui.dashboardTerminal.localOnly = true

    let service = CoreService(config: config)
    let router = CoreRouter(service: service)
    let server = CoreHTTPServer(
        host: "127.0.0.1",
        port: 0,
        router: router,
        logger: Logger(label: "sloppy.dashboard.terminal.httpserver.tests")
    )
    try server.start()
    defer { try? server.shutdown() }

    let port = try #require(server.boundPort)
    let wsURL = try #require(URL(string: "ws://127.0.0.1:\(port)/v1/dashboard/terminal/ws"))

    let unauthenticatedSocket = URLSession.shared.webSocketTask(with: wsURL)
    unauthenticatedSocket.resume()
    defer { unauthenticatedSocket.cancel(with: .normalClosure, reason: nil) }

    try await sendDashboardTerminalMessage(
        DashboardTerminalClientFrame(type: "start", token: nil, projectId: nil, cwd: nil, cols: 80, rows: 24, data: nil),
        over: unauthenticatedSocket
    )
    let unauthorized = try await receiveDashboardTerminalMessage(over: unauthenticatedSocket)
    #expect(unauthorized.type == "error")
    #expect(unauthorized.code == "unauthorized")

    let badAuthSocket = URLSession.shared.webSocketTask(with: wsURL)
    badAuthSocket.resume()
    defer { badAuthSocket.cancel(with: .normalClosure, reason: nil) }

    try await sendDashboardTerminalMessage(
        DashboardTerminalClientFrame(type: "auth", token: "wrong-token", projectId: nil, cwd: nil, cols: nil, rows: nil, data: nil),
        over: badAuthSocket
    )
    let badAuth = try await receiveDashboardTerminalMessage(over: badAuthSocket)
    #expect(badAuth.type == "error")
    #expect(badAuth.code == "unauthorized")

    let firstSocket = URLSession.shared.webSocketTask(with: wsURL)
    firstSocket.resume()
    defer { firstSocket.cancel(with: .normalClosure, reason: nil) }

    try await sendDashboardTerminalMessage(
        DashboardTerminalClientFrame(type: "auth", token: "dashboard-secret", projectId: nil, cwd: nil, cols: nil, rows: nil, data: nil),
        over: firstSocket
    )
    let authenticated = try await receiveDashboardTerminalMessage(over: firstSocket)
    #expect(authenticated.type == "authenticated")

    try await sendDashboardTerminalMessage(
        DashboardTerminalClientFrame(type: "start", token: nil, projectId: nil, cwd: nil, cols: 80, rows: 24, data: nil),
        over: firstSocket
    )
    let ready = try await receiveDashboardTerminalMessage(over: firstSocket)
    #expect(ready.type == "ready")
    #expect((ready.sessionId ?? "").isEmpty == false)

    let marker = "__sloppy_terminal_input_ok_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))__"
    try await sendDashboardTerminalMessage(
        DashboardTerminalClientFrame(type: "input", token: nil, projectId: nil, cwd: nil, cols: nil, rows: nil, data: "printf '\(marker)\\n'\r"),
        over: firstSocket
    )

    let combinedOutput = try await collectDashboardTerminalOutput(untilContains: marker, over: firstSocket)
    #expect(combinedOutput.contains(marker))

    try await sendDashboardTerminalMessage(
        DashboardTerminalClientFrame(type: "close", token: nil, projectId: nil, cwd: nil, cols: nil, rows: nil, data: nil),
        over: firstSocket
    )
    let closed = try await receiveDashboardTerminalMessage(over: firstSocket)
    #expect(closed.type == "closed")

    try await sendDashboardTerminalMessage(
        DashboardTerminalClientFrame(type: "start", token: nil, projectId: nil, cwd: nil, cols: 100, rows: 30, data: nil),
        over: firstSocket
    )
    let restarted = try await receiveDashboardTerminalMessage(over: firstSocket)
    #expect(restarted.type == "ready")
    #expect((restarted.sessionId ?? "").isEmpty == false)
    #expect(restarted.sessionId != ready.sessionId)

    firstSocket.cancel(with: .normalClosure, reason: nil)

    let secondSocket = URLSession.shared.webSocketTask(with: wsURL)
    secondSocket.resume()
    defer { secondSocket.cancel(with: .normalClosure, reason: nil) }

    try await sendDashboardTerminalMessage(
        DashboardTerminalClientFrame(type: "auth", token: "dashboard-secret", projectId: nil, cwd: nil, cols: nil, rows: nil, data: nil),
        over: secondSocket
    )
    let reauthenticated = try await receiveDashboardTerminalMessage(over: secondSocket)
    #expect(reauthenticated.type == "authenticated")

    try await sendDashboardTerminalMessage(
        DashboardTerminalClientFrame(type: "start", token: nil, projectId: nil, cwd: nil, cols: 90, rows: 28, data: nil),
        over: secondSocket
    )
    let reconnected = try await receiveDashboardTerminalMessage(over: secondSocket)
    #expect(reconnected.type == "ready")
    #expect((reconnected.sessionId ?? "").isEmpty == false)
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

private func sendDashboardTerminalMessage(
    _ message: DashboardTerminalClientFrame,
    over socket: URLSessionWebSocketTask
) async throws {
    let payload = try JSONEncoder().encode(message)
    let text = try #require(String(data: payload, encoding: .utf8))
    try await socket.send(.string(text))
}

private func receiveDashboardTerminalMessage(
    over socket: URLSessionWebSocketTask
) async throws -> DashboardTerminalServerFrame {
    try await withThrowingTaskGroup(of: DashboardTerminalServerFrame.self) { group in
        group.addTask {
            let message = try await socket.receive()
            let payload = try #require(messagePayload(message))
            return try JSONDecoder().decode(DashboardTerminalServerFrame.self, from: Data(payload.utf8))
        }
        group.addTask {
            try await Task.sleep(nanoseconds: 10_000_000_000)
            socket.cancel(with: .goingAway, reason: nil)
            throw AsyncTestTimeoutError(operation: "dashboard terminal websocket message")
        }

        let result = try await group.next()
        group.cancelAll()
        return try #require(result)
    }
}

private func collectDashboardTerminalOutput(
    untilContains needle: String,
    over socket: URLSessionWebSocketTask
) async throws -> String {
    var combined = ""

    while !combined.contains(needle) {
        let message = try await receiveDashboardTerminalMessage(over: socket)
        if message.type == "output" {
            combined += message.data ?? ""
            continue
        }
        if message.type == "error" {
            Issue.record("Terminal error while waiting for output: \(message.message ?? "(unknown)")")
            break
        }
    }

    return combined
}
#endif

private func withAsyncTestTimeout<T: Sendable>(
    seconds: Double = 10,
    operation: String,
    _ work: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await work()
        }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw AsyncTestTimeoutError(operation: operation)
        }

        let result = try await group.next()
        group.cancelAll()
        return try #require(result)
    }
}

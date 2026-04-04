import ACP
import ACPModel
import Foundation
import Testing
@testable import Protocols
@testable import sloppy

private final class MockACPClientQueue: @unchecked Sendable {
    private let lock = NSLock()
    private var clients: [MockACPTransportClient]

    init(clients: [MockACPTransportClient]) {
        self.clients = clients
    }

    func next() -> MockACPTransportClient {
        lock.withLock {
            clients.removeFirst()
        }
    }
}

private actor MockACPTransportClient: ACPTransportClient {
    private let initializeResponse: InitializeResponse
    private let promptResponse: SessionPromptResponse
    private let newSessionResponse: NewSessionResponse
    private let loadSessionResponse: LoadSessionResponse
    private let loadSessionError: Error?
    private let permissionRequest: RequestPermissionRequest?

    private var delegate: ClientDelegate?
    private var connectCount = 0
    private var newSessionCount = 0
    private var loadSessionCount = 0
    private var sendPromptCount = 0
    private var terminateCount = 0
    private var sentPromptTexts: [String] = []
    private var lastPermissionOutcome: RequestPermissionResponse?

    private let notificationContinuation: AsyncStream<JSONRPCNotification>.Continuation
    private let notificationStream: AsyncStream<JSONRPCNotification>

    init(
        initializeResponse: InitializeResponse,
        promptResponse: SessionPromptResponse = SessionPromptResponse(stopReason: .endTurn),
        newSessionResponse: NewSessionResponse = NewSessionResponse(sessionId: SessionId("upstream-1")),
        loadSessionResponse: LoadSessionResponse = LoadSessionResponse(sessionId: SessionId("upstream-1")),
        loadSessionError: Error? = nil,
        permissionRequest: RequestPermissionRequest? = nil
    ) {
        self.initializeResponse = initializeResponse
        self.promptResponse = promptResponse
        self.newSessionResponse = newSessionResponse
        self.loadSessionResponse = loadSessionResponse
        self.loadSessionError = loadSessionError
        self.permissionRequest = permissionRequest

        var continuation: AsyncStream<JSONRPCNotification>.Continuation!
        self.notificationStream = AsyncStream { cont in
            continuation = cont
        }
        self.notificationContinuation = continuation
    }

    func setDelegate(_ delegate: ClientDelegate?) async {
        self.delegate = delegate
    }

    func notificationsStream() async -> AsyncStream<JSONRPCNotification> {
        notificationStream
    }

    func connect(
        workingDirectory _: String,
        capabilities _: ClientCapabilities,
        clientInfo _: ClientInfo,
        timeout _: TimeInterval?
    ) async throws -> InitializeResponse {
        connectCount += 1
        return initializeResponse
    }

    func newSession(workingDirectory _: String, timeout _: TimeInterval?) async throws -> NewSessionResponse {
        newSessionCount += 1
        return newSessionResponse
    }

    func loadSession(sessionId _: SessionId, cwd _: String?) async throws -> LoadSessionResponse {
        loadSessionCount += 1
        if let loadSessionError {
            throw loadSessionError
        }
        return loadSessionResponse
    }

    func sendPrompt(sessionId _: SessionId, content: [ContentBlock]) async throws -> SessionPromptResponse {
        sendPromptCount += 1
        sentPromptTexts.append(content.compactMap(Self.text(from:)).joined(separator: "\n"))
        if let permissionRequest, let delegate {
            lastPermissionOutcome = try await delegate.handlePermissionRequest(request: permissionRequest)
        }
        return promptResponse
    }

    func cancelSession(sessionId _: SessionId) async throws {}

    func terminate() async {
        terminateCount += 1
        notificationContinuation.finish()
    }

    func snapshot() -> (connects: Int, newSessions: Int, loads: Int, prompts: Int, terminated: Int, promptTexts: [String], permissionOutcome: RequestPermissionResponse?) {
        (
            connects: connectCount,
            newSessions: newSessionCount,
            loads: loadSessionCount,
            prompts: sendPromptCount,
            terminated: terminateCount,
            promptTexts: sentPromptTexts,
            permissionOutcome: lastPermissionOutcome
        )
    }

    private static func text(from block: ContentBlock) -> String? {
        switch block {
        case .text(let text):
            return text.text
        default:
            return nil
        }
    }
}

private actor EventRecorder {
    private(set) var events: [AgentSessionEvent] = []
    private(set) var chunks: [String] = []

    func append(event: AgentSessionEvent) {
        events.append(event)
    }

    func append(chunk: String) {
        chunks.append(chunk)
    }
}

private func makeInitializeResponse(loadSession: Bool) -> InitializeResponse {
    InitializeResponse(
        protocolVersion: 1,
        agentCapabilities: AgentCapabilities(
            loadSession: loadSession,
            mcpCapabilities: MCPCapabilities(http: true, sse: false),
            promptCapabilities: PromptCapabilities(image: true),
            sessionCapabilities: SessionCapabilities(list: SessionListCapabilities())
        ),
        agentInfo: AgentInfo(name: "Mock Agent", version: "1.0.0")
    )
}

private func makeSessionManagerFixture(
    target: CoreConfig.ACP.Target,
    clients: [MockACPTransportClient]
) throws -> (manager: ACPSessionManager, agentsRootURL: URL, sessionID: String) {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("acp-session-manager-\(UUID().uuidString)", isDirectory: true)
    let agentsRootURL = root.appendingPathComponent("agents", isDirectory: true)
    let sessionsURL = agentsRootURL.appendingPathComponent("agent-1", isDirectory: true).appendingPathComponent("sessions", isDirectory: true)
    try FileManager.default.createDirectory(at: sessionsURL, withIntermediateDirectories: true)

    let queue = MockACPClientQueue(clients: clients)
    let manager = ACPSessionManager(
        config: .init(enabled: true, targets: [target]),
        workspaceRootURL: root,
        agentsRootURL: agentsRootURL,
        clientFactory: ACPClientFactory { _ in
            queue.next()
        }
    )

    return (manager, agentsRootURL, "session-1")
}

@Test
func acpSessionManagerCreatesSessionSendsPrimerAndPersistsSidecar() async throws {
    let target = CoreConfig.ACP.Target(
        id: "local",
        title: "Local ACP",
        transport: .stdio,
        command: "/bin/echo"
    )
    let client = MockACPTransportClient(initializeResponse: makeInitializeResponse(loadSession: true))
    let (manager, agentsRootURL, sessionID) = try makeSessionManagerFixture(target: target, clients: [client])
    let recorder = EventRecorder()

    let result = try await manager.postMessage(
        agentID: "agent-1",
        sloppySessionID: sessionID,
        runtime: .init(type: .acp, acp: .init(targetId: "local")),
        content: [.text(TextContent(text: "hello"))],
        localSessionHadPriorMessages: false,
        primerContent: "BOOTSTRAP",
        onChunk: { chunk in await recorder.append(chunk: chunk) },
        onEvent: { event in await recorder.append(event: event) }
    )

    #expect(result.didResetContext == false)

    let snapshot = await client.snapshot()
    #expect(snapshot.newSessions == 1)
    #expect(snapshot.loads == 0)
    #expect(snapshot.prompts == 2)
    #expect(snapshot.promptTexts.first == "BOOTSTRAP")
    #expect(snapshot.promptTexts.last == "hello")

    let sidecarURL = agentsRootURL
        .appendingPathComponent("agent-1", isDirectory: true)
        .appendingPathComponent("sessions", isDirectory: true)
        .appendingPathComponent("\(sessionID).acp-state.json")
    #expect(FileManager.default.fileExists(atPath: sidecarURL.path))

    let sidecarData = try Data(contentsOf: sidecarURL)
    let sidecar = try JSONDecoder().decode(ACPPersistedSessionState.self, from: sidecarData)
    #expect(sidecar.targetId == "local")
    #expect(sidecar.upstreamSessionId == "upstream-1")
    #expect(sidecar.supportsLoadSession == true)
}

@Test
func acpSessionManagerRestoresMatchingSidecarViaLoadSessionWithoutPrimer() async throws {
    let target = CoreConfig.ACP.Target(
        id: "local",
        title: "Local ACP",
        transport: .stdio,
        command: "/bin/echo"
    )
    let firstClient = MockACPTransportClient(initializeResponse: makeInitializeResponse(loadSession: true))
    let fixture = try makeSessionManagerFixture(target: target, clients: [firstClient])

    _ = try await fixture.manager.postMessage(
        agentID: "agent-1",
        sloppySessionID: fixture.sessionID,
        runtime: .init(type: .acp, acp: .init(targetId: "local")),
        content: [.text(TextContent(text: "first"))],
        localSessionHadPriorMessages: false,
        primerContent: "BOOTSTRAP",
        onChunk: { _ in },
        onEvent: { _ in }
    )

    let secondClient = MockACPTransportClient(initializeResponse: makeInitializeResponse(loadSession: true))
    let queue = MockACPClientQueue(clients: [secondClient])
    let restoredManager = ACPSessionManager(
        config: .init(enabled: true, targets: [target]),
        workspaceRootURL: fixture.agentsRootURL.deletingLastPathComponent(),
        agentsRootURL: fixture.agentsRootURL,
        clientFactory: ACPClientFactory { _ in queue.next() }
    )

    let result = try await restoredManager.postMessage(
        agentID: "agent-1",
        sloppySessionID: fixture.sessionID,
        runtime: .init(type: .acp, acp: .init(targetId: "local")),
        content: [.text(TextContent(text: "second"))],
        localSessionHadPriorMessages: true,
        primerContent: "BOOTSTRAP",
        onChunk: { _ in },
        onEvent: { _ in }
    )

    #expect(result.didResetContext == false)

    let snapshot = await secondClient.snapshot()
    #expect(snapshot.loads == 1)
    #expect(snapshot.newSessions == 0)
    #expect(snapshot.prompts == 1)
    #expect(snapshot.promptTexts == ["second"])
}

@Test
func acpSessionManagerDropsMismatchedSidecarAndCreatesNewUpstreamSession() async throws {
    let originalTarget = CoreConfig.ACP.Target(
        id: "local",
        title: "Local ACP",
        transport: .stdio,
        command: "/bin/echo"
    )
    let fixture = try makeSessionManagerFixture(
        target: originalTarget,
        clients: [MockACPTransportClient(initializeResponse: makeInitializeResponse(loadSession: true))]
    )

    _ = try await fixture.manager.postMessage(
        agentID: "agent-1",
        sloppySessionID: fixture.sessionID,
        runtime: .init(type: .acp, acp: .init(targetId: "local")),
        content: [.text(TextContent(text: "first"))],
        localSessionHadPriorMessages: false,
        primerContent: "BOOTSTRAP",
        onChunk: { _ in },
        onEvent: { _ in }
    )

    let changedTarget = CoreConfig.ACP.Target(
        id: "local",
        title: "Local ACP",
        transport: .stdio,
        command: "/bin/cat"
    )
    let client = MockACPTransportClient(initializeResponse: makeInitializeResponse(loadSession: true))
    let queue = MockACPClientQueue(clients: [client])
    let manager = ACPSessionManager(
        config: .init(enabled: true, targets: [changedTarget]),
        workspaceRootURL: fixture.agentsRootURL.deletingLastPathComponent(),
        agentsRootURL: fixture.agentsRootURL,
        clientFactory: ACPClientFactory { _ in queue.next() }
    )

    let result = try await manager.postMessage(
        agentID: "agent-1",
        sloppySessionID: fixture.sessionID,
        runtime: .init(type: .acp, acp: .init(targetId: "local")),
        content: [.text(TextContent(text: "second"))],
        localSessionHadPriorMessages: true,
        primerContent: "BOOTSTRAP",
        onChunk: { _ in },
        onEvent: { _ in }
    )

    #expect(result.didResetContext == true)

    let snapshot = await client.snapshot()
    #expect(snapshot.loads == 0)
    #expect(snapshot.newSessions == 1)
    #expect(snapshot.prompts == 2)
}

@Test
func acpSessionManagerSelectsExactAllowOncePermissionOption() async throws {
    let target = CoreConfig.ACP.Target(
        id: "local",
        title: "Local ACP",
        transport: .stdio,
        command: "/bin/echo",
        permissionMode: .allowOnce
    )
    let client = MockACPTransportClient(
        initializeResponse: makeInitializeResponse(loadSession: false),
        permissionRequest: RequestPermissionRequest(
            message: "Run dangerous tool?",
            options: [
                PermissionOption(kind: "decision", name: "Allow once", optionId: "allow_once"),
                PermissionOption(kind: "decision", name: "Always allow", optionId: "allow_always")
            ]
        )
    )
    let (manager, _, sessionID) = try makeSessionManagerFixture(target: target, clients: [client])
    let recorder = EventRecorder()

    _ = try await manager.postMessage(
        agentID: "agent-1",
        sloppySessionID: sessionID,
        runtime: .init(type: .acp, acp: .init(targetId: "local")),
        content: [.text(TextContent(text: "hello"))],
        localSessionHadPriorMessages: false,
        primerContent: nil,
        onChunk: { _ in },
        onEvent: { event in await recorder.append(event: event) }
    )

    let snapshot = await client.snapshot()
    #expect(snapshot.permissionOutcome?.outcome.optionId == "allow_once")
    let permissionEvent = await recorder.events.last(where: { $0.type == .runStatus })
    #expect(permissionEvent?.runStatus?.details?.contains("allow_once") == true)
}

@Test
func acpSessionManagerRejectsWhenAllowOnceIsUnavailableOrDeniedByMode() async throws {
    let target = CoreConfig.ACP.Target(
        id: "local",
        title: "Local ACP",
        transport: .stdio,
        command: "/bin/echo",
        permissionMode: .deny
    )
    let client = MockACPTransportClient(
        initializeResponse: makeInitializeResponse(loadSession: false),
        permissionRequest: RequestPermissionRequest(
            message: "Run dangerous tool?",
            options: [
                PermissionOption(kind: "decision", name: "Allow once", optionId: "allow_once"),
                PermissionOption(kind: "decision", name: "Always allow", optionId: "allow_always")
            ]
        )
    )
    let (manager, _, sessionID) = try makeSessionManagerFixture(target: target, clients: [client])
    let recorder = EventRecorder()

    _ = try await manager.postMessage(
        agentID: "agent-1",
        sloppySessionID: sessionID,
        runtime: .init(type: .acp, acp: .init(targetId: "local")),
        content: [.text(TextContent(text: "hello"))],
        localSessionHadPriorMessages: false,
        primerContent: nil,
        onChunk: { _ in },
        onEvent: { event in await recorder.append(event: event) }
    )

    let snapshot = await client.snapshot()
    #expect(snapshot.permissionOutcome?.outcome.optionId == nil)
    #expect(snapshot.permissionOutcome?.outcome.outcome == "cancelled")
    let permissionEvent = await recorder.events.last(where: { $0.type == .runStatus })
    #expect(permissionEvent?.runStatus?.details?.contains("denied") == true)
}

@Test
func acpSessionManagerRejectsAllowAlwaysFallbackWhenAllowOnceMissing() async throws {
    let target = CoreConfig.ACP.Target(
        id: "local",
        title: "Local ACP",
        transport: .stdio,
        command: "/bin/echo",
        permissionMode: .allowOnce
    )
    let client = MockACPTransportClient(
        initializeResponse: makeInitializeResponse(loadSession: false),
        permissionRequest: RequestPermissionRequest(
            message: "Run dangerous tool?",
            options: [
                PermissionOption(kind: "decision", name: "Always allow", optionId: "allow_always")
            ]
        )
    )
    let (manager, _, sessionID) = try makeSessionManagerFixture(target: target, clients: [client])
    let recorder = EventRecorder()

    _ = try await manager.postMessage(
        agentID: "agent-1",
        sloppySessionID: sessionID,
        runtime: .init(type: .acp, acp: .init(targetId: "local")),
        content: [.text(TextContent(text: "hello"))],
        localSessionHadPriorMessages: false,
        primerContent: nil,
        onChunk: { _ in },
        onEvent: { event in await recorder.append(event: event) }
    )

    let snapshot = await client.snapshot()
    #expect(snapshot.permissionOutcome?.outcome.optionId == nil)
    #expect(snapshot.permissionOutcome?.outcome.outcome == "cancelled")
    let permissionEvent = await recorder.events.last(where: { $0.type == .runStatus })
    #expect(permissionEvent?.runStatus?.details?.contains("allow_once unavailable") == true)
}

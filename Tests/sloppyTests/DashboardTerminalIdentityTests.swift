import Foundation
import SloppyNodeCore
import Testing
@testable import Protocols
@testable import sloppy

private actor TerminalAuthFrames {
    var frames: [[String: String]] = []

    func append(_ text: String) throws {
        frames.append(try JSONDecoder().decode([String: String].self, from: Data(text.utf8)))
    }
}

@Test(arguments: [true, false])
func dashboardTerminalUsesIdentityAuthRegardlessOfLegacyToggle(legacyEnabled: Bool) async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    var config = CoreConfig.test
    config.ui.dashboardAuth.enabled = legacyEnabled
    config.ui.dashboardAuth.token = "legacy-secret"
    let service = CoreService(
        config: config,
        currentDirectory: root.path,
        persistenceBuilder: InMemoryCorePersistenceBuilder(),
        nodeConfigStore: NodeConfigStore(configURL: root.appendingPathComponent("node.json")),
        sharedSkillsRootURLs: [],
        identityPasswordHashIterations: 1
    )
    await service.setIdentityAuthEnabled(true)
    let session = try await service.bootstrapIdentityAdmin(.init(login: "admin", password: "test-password", name: "Admin"))
    let router = CoreRouter(service: service)

    for token in [session.accessToken, "legacy-secret", "invalid-token", ""] {
        let frames = TerminalAuthFrames()
        let message = String(decoding: try JSONEncoder().encode(["type": "auth", "token": token]), as: UTF8.self)
        let stream = AsyncStream<String> { continuation in
            continuation.yield(message)
            continuation.finish()
        }
        let connection = WebSocketConnectionContext(
            sendText: { text in
                try? await frames.append(text)
                return true
            },
            close: {},
            incomingMessages: { stream }
        )
        let handled = await router.handleWebSocket(path: "/v1/dashboard/terminal/ws", connection: connection, remoteAddress: "127.0.0.1")
        #expect(handled)
        let frame = try #require(await frames.frames.first)
        #expect(frame["type"] == (token == session.accessToken ? "authenticated" : "error"))
        if token != session.accessToken {
            #expect(frame["code"] == "unauthorized")
        }
    }
}

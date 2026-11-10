import Foundation
import Protocols
import Testing
@testable import sloppy

@Suite("Chat approval defaults")
struct SessionApprovalDefaultsTests {
    @Test(arguments: [SessionApprovalMode.askForApproval, .approveForMe, .fullAccess])
    func configurationRemainsBackwardCompatible(mode: SessionApprovalMode) throws {
        let encoded = try JSONEncoder().encode(CoreConfig.test)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["defaultChatApprovalMode"] = nil
        let legacy = try JSONSerialization.data(withJSONObject: object)
        let legacyConfig = try JSONDecoder().decode(CoreConfig.self, from: legacy)
        #expect(legacyConfig.defaultChatApprovalMode == nil)
        #expect(legacyConfig.effectiveDefaultChatApprovalMode == .fullAccess)
        object["defaultChatApprovalMode"] = mode.rawValue
        let chosen = try JSONDecoder().decode(CoreConfig.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(chosen.defaultChatApprovalMode == mode)
        #expect(try JSONDecoder().decode(CoreConfig.self, from: JSONEncoder().encode(chosen)).defaultChatApprovalMode == mode)
        object["defaultChatApprovalMode"] = "unsupported"
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(CoreConfig.self, from: JSONSerialization.data(withJSONObject: object))
        }
    }

    @Test func newChatsSnapshotTheDefaultAndExistingChatsKeepTheirMode() async throws {
        let service = try await makeService()
        defer { Task { await service.stop() } }
        let legacy = try await service.sessionStore.createSession(agentID: "defaults-agent", request: .init())
        let first = try await service.createAgentSession(agentID: "defaults-agent", request: .init())
        let standalone = try await service.createAgentSession(agentID: "defaults-agent", request: .init(kind: .worker))
        var config = await service.getConfig()
        config.defaultChatApprovalMode = .approveForMe
        _ = try await service.updateConfig(config)
        let second = try await service.createAgentSession(agentID: "defaults-agent", request: .init())
        #expect(try await mode(legacy, service) == .askForApproval)
        #expect(try await mode(first, service) == .fullAccess)
        #expect(try await mode(standalone, service) == .fullAccess)
        #expect(try await mode(second, service) == .approveForMe)
        config.defaultChatApprovalMode = .askForApproval
        _ = try await service.updateConfig(config)
        #expect(try await mode(second, service) == .approveForMe)
        _ = try await service.setSessionApprovalPolicy(agentID: second.agentId, sessionID: second.id, policy: .init(mode: .askForApproval))
        #expect(try await mode(second, service) == .askForApproval)
    }

    @Test func childrenInheritTheParentInsteadOfTheNewDefault() async throws {
        let service = try await makeService()
        defer { Task { await service.stop() } }
        let parent = try await service.createAgentSession(agentID: "defaults-agent", request: .init())
        var config = await service.getConfig()
        config.defaultChatApprovalMode = .approveForMe
        _ = try await service.updateConfig(config)
        let child = try await service.createAgentSession(agentID: "defaults-agent", request: .init(parentSessionId: parent.id))
        #expect(try await mode(child, service) == .fullAccess)
        _ = try await service.setSessionApprovalPolicy(agentID: parent.agentId, sessionID: parent.id, policy: .init(mode: .askForApproval))
        #expect(try await mode(child, service) == .askForApproval)
    }

    @Test func newPersistentConversationsUseTheDefaultAndReopeningPreservesIt() async throws {
        let service = try await makeService()
        defer { Task { await service.stop() } }
        let conversation = try await service.openLongChat(agentID: "defaults-agent", userID: "user-one")
        let worker = try await service.sessionStore.createSession(
            agentID: conversation.agentId, request: .init(parentSessionId: conversation.id, kind: .longChatWorker))
        #expect(try await mode(conversation, service) == .fullAccess)
        #expect(try await mode(worker, service) == .fullAccess)
        _ = try await service.setDefaultChatApprovalPolicy(.init(mode: .askForApproval))
        let reopened = try await service.openLongChat(agentID: "defaults-agent", userID: "user-one")
        #expect(reopened.id == conversation.id)
        #expect(try await mode(reopened, service) == .fullAccess)
        let other = try await service.openLongChat(agentID: "defaults-agent", userID: "user-two")
        #expect(try await mode(other, service) == .askForApproval)
    }

    @Test func focusedSettingsAPIIsDurableAndPreservesOtherConfiguration() async throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("approval-default-\(UUID().uuidString).json")
        let service = CoreService(config: .test, configPath: path.path, persistenceBuilder: InMemoryCorePersistenceBuilder())
        defer { Task { await service.stop() }; try? FileManager.default.removeItem(at: path) }
        let router = CoreRouter(service: service)
        let endpoint = "/v1/config/chat-approval-default"
        let before = await service.getConfig()
        let initial = await router.handle(method: "GET", path: endpoint, body: nil)
        #expect(initial.status == 200)
        #expect(try JSONDecoder().decode(SessionApprovalPolicy.self, from: initial.body).mode == .fullAccess)
        let runtimeConfig = await router.handle(method: "GET", path: "/v1/config", body: nil)
        #expect(try JSONDecoder().decode(CoreConfig.self, from: runtimeConfig.body).defaultChatApprovalMode == .fullAccess)
        let response = await router.handle(method: "PUT", path: endpoint, body: Data(#"{"mode":"approve_for_me"}"#.utf8))
        #expect(response.status == 200)
        #expect(try JSONDecoder().decode(SessionApprovalPolicy.self, from: response.body).mode == .approveForMe)
        let persisted = try JSONDecoder().decode(CoreConfig.self, from: Data(contentsOf: path))
        #expect(persisted.defaultChatApprovalMode == .approveForMe)
        #expect(persisted.sessionRetention == before.sessionRetention)
        #expect(persisted.auth.token == before.auth.token)
        #expect(await router.handle(method: "PUT", path: endpoint, body: Data(#"{"mode":"unsupported"}"#.utf8)).status == 400)
        let restarted = CoreService(config: persisted, configPath: path.path, persistenceBuilder: InMemoryCorePersistenceBuilder())
        defer { Task { await restarted.stop() } }
        #expect(await restarted.getDefaultChatApprovalPolicy().mode == .approveForMe)
    }

    private func makeService() async throws -> CoreService {
        let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
        _ = try await service.createAgent(.init(id: "defaults-agent", displayName: "Defaults", role: "Test"))
        return service
    }

    private func mode(_ session: AgentSessionSummary, _ service: CoreService) async throws -> SessionApprovalMode {
        try await service.getSessionApprovalPolicy(agentID: session.agentId, sessionID: session.id).mode
    }
}

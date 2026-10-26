import Foundation
import Protocols
import Testing
@testable import sloppy

@Suite("Chat approval defaults")
struct SessionApprovalDefaultsTests {
    @Test func configurationRemainsBackwardCompatible() throws {
        let encoded = try JSONEncoder().encode(CoreConfig.test)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["defaultChatApprovalMode"] = nil
        let legacy = try JSONSerialization.data(withJSONObject: object)
        #expect(try JSONDecoder().decode(CoreConfig.self, from: legacy).defaultChatApprovalMode == nil)
        object["defaultChatApprovalMode"] = "approve_for_me"
        let chosen = try JSONDecoder().decode(CoreConfig.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(chosen.defaultChatApprovalMode == .approveForMe)
        #expect(try JSONDecoder().decode(CoreConfig.self, from: JSONEncoder().encode(chosen)).defaultChatApprovalMode == .approveForMe)
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
        var config = await service.getConfig()
        config.defaultChatApprovalMode = .approveForMe
        _ = try await service.updateConfig(config)
        let second = try await service.createAgentSession(agentID: "defaults-agent", request: .init())
        #expect(try await mode(legacy, service) == .askForApproval)
        #expect(try await mode(first, service) == .askForApproval)
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
        #expect(try await mode(child, service) == .askForApproval)
        _ = try await service.setSessionApprovalPolicy(agentID: parent.agentId, sessionID: parent.id, policy: .init(mode: .approveForMe))
        #expect(try await mode(child, service) == .approveForMe)
    }

    @Test func newPersistentConversationsUseTheDefaultAndReopeningPreservesIt() async throws {
        let service = try await makeService()
        defer { Task { await service.stop() } }
        var config = await service.getConfig()
        config.defaultChatApprovalMode = .approveForMe
        _ = try await service.updateConfig(config)
        let conversation = try await service.openLongChat(agentID: "defaults-agent", userID: "user-one")
        #expect(try await mode(conversation, service) == .approveForMe)
        config.defaultChatApprovalMode = .askForApproval
        _ = try await service.updateConfig(config)
        let reopened = try await service.openLongChat(agentID: "defaults-agent", userID: "user-one")
        #expect(reopened.id == conversation.id)
        #expect(try await mode(reopened, service) == .approveForMe)
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
        #expect(await router.handle(method: "GET", path: endpoint, body: nil).status == 200)
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

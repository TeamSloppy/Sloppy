import Foundation
import Protocols
import AgentRuntime
import SloppyRuntime
import Testing
@testable import sloppy

// Faithful old discriminator decoding: defaults apply to absent fields, never unknown present values.
private struct LegacyStoredProfile: Decodable {
    private struct Runtime: Decodable {
        enum Kind: String, Decodable { case native, acp }
        enum CodingKeys: String, CodingKey { case type, acp, sharedMemoryEnabled }
        var type: Kind
        var sharedMemoryEnabled: Bool
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            type = try values.decodeIfPresent(Kind.self, forKey: .type) ?? .native
            _ = try values.decodeIfPresent(JSONValue.self, forKey: .acp)
            sharedMemoryEnabled = try values.decodeIfPresent(Bool.self, forKey: .sharedMemoryEnabled) ?? true
        }
    }
    private var runtime: Runtime
}

private func engineConfig(_ engine: String) throws -> AgentRuntimeConfig {
    try JSONDecoder().decode(AgentRuntimeConfig.self,
        from: JSONSerialization.data(withJSONObject: ["type": "native", "nativeEngine": engine]))
}

@Suite("Agent storage compatibility")
struct AgentCatalogStorageCompatibilityTests {
    @Test(arguments: [3, 4, 5, 6, 7, 8])
    func lifecycleProtectedProfilesRemainReadableAndCannotBeDowngraded(version: Int) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("profile-v3-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let models = [ProviderModelOption(id: "openai-api:test-model", title: "test", capabilities: ["tools"])]
        let store = AgentCatalogFileStore(agentsRootURL: root)
        let agent = try store.createAgent(.init(id: "profile-v3", displayName: "Gate", role: "Developer"), availableModels: models)
        let files = ["agent.json", "config.json"].map { root.appendingPathComponent(agent.id).appendingPathComponent($0) }
        for file in files {
            var object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
            var runtime = try #require(object["runtime"] as? [String: Any])
            runtime["type"] = "native_v\(version)"
            runtime["storageRuntimeType"] = "native"
            runtime["nativeEngine"] = "legacy"
            object["runtime"] = runtime
            try JSONSerialization.data(withJSONObject: object).write(to: file, options: .atomic)
        }
        var failure: Error?
        do {
            let config = try store.getAgentConfig(agentID: agent.id, availableModels: models)
            #expect(config.runtime.type == .native)
            _ = try store.updateAgentConfig(agentID: agent.id,
                request: .init(role: "Updated", selectedModel: models[0].id, documents: config.documents,
                    runtime: try engineConfig("legacy")), availableModels: models)
            try store.verifyUnifiedJournalStorage(agentID: agent.id)
        } catch { failure = error }
        #expect(failure == nil)
        for file in files {
            let object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
            #expect((object["runtime"] as? [String: Any])?["type"] as? String == "native_v\(version)")
            #expect(throws: DecodingError.self) { _ = try JSONDecoder().decode(LegacyStoredProfile.self, from: Data(contentsOf: file)) }
        }
    }

    @Test
    func unknownStorageProtectionCannotBeNormalizedAsReadable() throws {
        let bytes = try JSONSerialization.data(withJSONObject: ["runtime": [
            "type": "native_v9", "storageRuntimeType": "native", "nativeEngine": "legacy"
        ]])
        #expect(throws: AgentProfileStorageCodec.CodecError.self) { _ = try AgentProfileStorageCodec.normalized(bytes) }
    }

    @Test(arguments: [["files.read"], []] as [[String]], [NativeCompletionContract.worker, .coordinator])
    func workerScopeSnapshotReadersPreserveAuthority(scope: [String], contract: NativeCompletionContract) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("worker-scope-reader-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("agent"), withIntermediateDirectories: true)
        let store = AgentSessionFileStore(agentsRootURL: root)
        let session = try store.createSession(agentID: "agent", request: .init())
        let config = NativeAgentLoopConfig(finalizerToolNames: ["agent_delegate.finish"], engine: .unified, requiresExplicitCompletion: true)
        var raw = try #require(JSONValueCoder.encode(RunStateSnapshot(runID: "run", userTurnID: "turn", loopConfig: config)).asObject)
        raw["schemaVersion"] = .number(2)
        var settings = try #require(JSONValueCoder.encode(RunRequestSettings(retryDelays: [], reasoningEffort: nil)).asObject)
        settings["toolScope"] = .array(scope.map(JSONValue.string))
        let authority = RunRequestSettings.ToolAuthority(policy: .init(), workingDirectory: root.path, extraRoots: [root.path])
        settings["delegatedAuthority"] = try JSONValueCoder.encode(authority)
        raw["requestSettings"] = .object(settings)
        var policy = try #require(raw["loopConfig"]?.asObject)
        policy["completionContract"] = .string(contract.rawValue)
        raw["loopConfig"] = .object(policy)
        _ = try store.appendEvents(agentID: "agent", sessionID: session.id, events: [
            .init(version: 2, agentId: "agent", sessionId: session.id, type: .runStatus,
                runtimeMetadata: .init(runId: "run", userTurnId: "turn", runState: .object(raw)))
        ])
        let journal = SessionLoopJournal(store: AgentSessionFileStore(agentsRootURL: root), agentID: "agent", sessionID: session.id, authorizeWriter: {})
        let restored = try #require(try await journal.restoreRunState())
        let roundTrip = try JSONValueCoder.encode(await restored.snapshot())
        #expect(roundTrip.asObject?["requestSettings"]?.asObject?["toolScope"] == .array(scope.map(JSONValue.string)))
        #expect(roundTrip.asObject?["loopConfig"]?.asObject?["completionContract"] == .string(contract.rawValue))
        #expect(roundTrip.asObject?["requestSettings"]?.asObject?["delegatedAuthority"] == (try JSONValueCoder.encode(authority)))
        var withoutResources = raw
        var withoutAuthority = settings
        withoutAuthority.removeValue(forKey: "delegatedAuthority")
        withoutResources["requestSettings"] = .object(withoutAuthority)
        #expect(throws: (any Error).self) { try JSONValueCoder.decode(RunStateSnapshot.self, from: .object(withoutResources)).validate() }
        settings.removeValue(forKey: "toolScope")
        var missing = raw
        missing["requestSettings"] = .object(settings)
        #expect(throws: (any Error).self) { try JSONValueCoder.decode(RunStateSnapshot.self, from: .object(missing)).validate() }
        policy["completionContract"] = .string("future")
        var future = raw
        future["loopConfig"] = .object(policy)
        #expect(throws: (any Error).self) { try JSONValueCoder.decode(RunStateSnapshot.self, from: .object(future)).validate() }
    }

    @Test
    func protectedProfileVerificationDoesNotRewriteEitherFile() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("profile-read-only-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let models = [ProviderModelOption(id: "openai-api:test-model", title: "test", capabilities: ["tools"])]
        let store = AgentCatalogFileStore(agentsRootURL: root)
        let agent = try store.createAgent(.init(id: "profile-read-only", displayName: "Gate", role: "Developer"), availableModels: models)
        let initial = try store.getAgentConfig(agentID: agent.id, availableModels: models)
        _ = try store.updateAgentConfig(agentID: agent.id,
            request: .init(role: initial.role, selectedModel: models[0].id,
                documents: initial.documents, runtime: try engineConfig("unified")), availableModels: models)
        try store.protectUnifiedJournalStorage(agentID: agent.id, availableModels: models)
        let files = ["agent.json", "config.json"].map { root.appendingPathComponent(agent.id).appendingPathComponent($0) }
        let historical = Date(timeIntervalSince1970: 1_234_567_890)
        let before = try files.map { try Data(contentsOf: $0) }
        for file in files { try FileManager.default.setAttributes([.modificationDate: historical], ofItemAtPath: file.path) }
        // On Windows these live readers also expose unnecessary atomic replacement
        // as a sharing violation. Modification dates establish the invariant everywhere.
        let handles = try files.map { try FileHandle(forReadingFrom: $0) }
        defer { for handle in handles { try? handle.close() } }
        var failure: Error?
        do { try store.protectUnifiedJournalStorage(agentID: agent.id, availableModels: models) }
        catch { failure = error }
        #expect(failure == nil)
        try store.verifyUnifiedJournalStorage(agentID: agent.id)
        for (index, file) in files.enumerated() {
            let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
            #expect(attributes[.modificationDate] as? Date == historical)
            #expect(try Data(contentsOf: file) == before[index])
        }
    }


    @Test(arguments: [false, true])
    func unifiedStorageBlocksOldReadersAndSurvivesRollback(changeRole: Bool) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("profile-gate-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let models = [ProviderModelOption(id: "openai-api:test-model", title: "test", capabilities: ["tools"])]
        let store = AgentCatalogFileStore(agentsRootURL: root)
        let agent = try store.createAgent(.init(id: "profile-gate", displayName: "Gate", role: "Developer"), availableModels: models)
        let initial = try store.getAgentConfig(agentID: agent.id, availableModels: models)
        let updated = try store.updateAgentConfig(agentID: agent.id,
            request: .init(role: changeRole ? "Updated developer" : initial.role, selectedModel: models[0].id,
                documents: initial.documents, runtime: try engineConfig("unified")), availableModels: models)
        let publicRuntime = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(updated.runtime)) as? [String: Any])
        #expect(publicRuntime["type"] as? String == "native")
        #expect(publicRuntime["nativeEngine"] as? String == "unified")
        try assertOldReaderRejected(root: root, agentID: agent.id)
        let reopened = AgentCatalogFileStore(agentsRootURL: root)
        #expect(try reopened.getAgent(id: agent.id).runtime.type == .native)
        let config = try reopened.getAgentConfig(agentID: agent.id, availableModels: models)
        // An older client omits the new field when saving an unrelated setting.
        let unchanged = try reopened.updateAgentConfig(agentID: agent.id,
            request: .init(role: config.role, selectedModel: models[0].id,
                documents: config.documents, runtime: .init(type: .native)), availableModels: models)
        let preserved = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(unchanged.runtime)) as? [String: Any])
        #expect(preserved["nativeEngine"] as? String == "unified")
        _ = try reopened.updateAgentConfig(agentID: agent.id,
            request: .init(role: config.role, selectedModel: models[0].id,
                documents: config.documents, runtime: try engineConfig("legacy")), availableModels: models)
        // Rollback changes new-run selection; it cannot erase protection for existing unified journals.
        try assertOldReaderRejected(root: root, agentID: agent.id)
        #expect(try AgentCatalogFileStore(agentsRootURL: root).getAgentRuntimeConfig(agentID: agent.id).type == .native)
    }

    private func assertOldReaderRejected(root: URL, agentID: String) throws {
        for name in ["agent.json", "config.json"] {
            let data = try Data(contentsOf: root.appendingPathComponent(agentID).appendingPathComponent(name))
            #expect(throws: DecodingError.self) { _ = try JSONDecoder().decode(LegacyStoredProfile.self, from: data) }
        }
    }
}

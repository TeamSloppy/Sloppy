import Foundation
import Testing
@testable import Protocols
@testable import sloppy

private let uiCreationJSON = """
    [{"version":"v0.9.1","createSurface":{"surfaceId":"demo","catalogId":"urn:sloppy:a2ui:catalog:v1"}},
     {"version":"v0.9.1","updateComponents":{"surfaceId":"demo","components":[{"id":"root","component":"Text","text":"Initial"}]}}]
    """
private let uiUpdateJSON = """
    [{"version":"v0.9.1","updateComponents":{"surfaceId":"demo","components":[{"id":"root","component":"Text","text":"Updated"}]}}]
    """
private func uiArguments(_ json: String, revision: Int) -> [String: JSONValue] {
    ["messages": .string(json), "expectedRevision": .number(Double(revision)), "fallbackText": .string("Readable fallback")]
}

@Test func a2uiPublishingIsAtomicScopedStreamedAndDurable() async throws {
    let config = CoreConfig.test
    let service = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
    _ = try await service.createAgent(.init(id: "publisher", displayName: "Publisher", role: "Testing"))
    let session = try await service.createAgentSession(agentID: "publisher", request: .init(title: "UI"))
    let other = try await service.createAgentSession(agentID: "publisher", request: .init(title: "Other"))
    let context = await service.toolExecution.makeContext(agentID: "publisher", sessionID: session.id, policy: .init())
    #expect(ToolRegistry.makeDefault().knownToolIDs.contains("ui.render"))
    #expect(ToolRegistry.makeDefault().knownToolIDs.contains("ui.catalog"))
    let registry = ToolRegistry(tools: [UICatalogTool(), UIRenderTool()])
    let catalog = try #require(await registry.invoke(request: .init(tool: "ui.catalog", arguments: [:]), context: context))
    try #require(catalog.ok, "\(catalog.error?.message ?? "UI catalog unavailable")")
    #expect(catalog.data?.asObject?["version"]?.asString == "v0.9.1")
    #expect(catalog.data?.asObject?["componentSchemas"]?.asObject?["Text"] != nil)
    var foreign = uiArguments(uiCreationJSON, revision: 0)
    foreign["sessionId"] = .string(other.id)
    #expect(await UIRenderTool().invoke(arguments: foreign, context: context).error?.code == "invalid_arguments")
    var iterator = try await service.streamAgentSessionEvents(agentID: "publisher", sessionID: session.id).makeAsyncIterator()
    #expect(await iterator.next()?.kind == .sessionReady)
    let result = await UIRenderTool().invoke(arguments: uiArguments(uiCreationJSON, revision: 0), context: context)
    try #require(result.ok, "\(result.error?.message ?? "UI publication failed")")
    #expect(result.data?.asObject?["revision"]?.asInt == 1)
    #expect(result.data?.asObject?["components"] == nil)
    let streamed = await iterator.next()
    #expect(streamed?.event?.message?.uiSurface?.revision == 1)
    #expect(streamed?.event?.message?.segments.first?.text == "Readable fallback")
    #expect(try await service.listAgentUISurfaces(agentID: "publisher", sessionID: other.id).isEmpty)
    let before = try await service.getAgentSession(agentID: "publisher", sessionID: session.id).events.count
    let bad = uiUpdateJSON.replacingOccurrences(of: "Text", with: "ExecutableWidget")
    var partial: [Protocols.JSONValue] = try JSONDecoder().decode([Protocols.JSONValue].self, from: Data(uiUpdateJSON.utf8))
    let invalidNode: Protocols.JSONValue = .object([
        "id": .string("root"), "component": .string("Column"), "children": .array([.string("missing")]),
    ])
    let invalidFrame: Protocols.JSONValue = .object([
        "version": .string("v0.9.1"),
        "updateComponents": .object([
            "surfaceId": .string("demo"), "components": .array([invalidNode]),
        ]),
    ])
    partial.append(invalidFrame)
    for invalid in [bad, String(decoding: try JSONEncoder().encode(partial), as: UTF8.self)] {
        let refused = await UIRenderTool().invoke(arguments: uiArguments(invalid, revision: 1), context: context)
        #expect(!refused.ok && refused.error?.code == "invalid_ui_payload")
        #expect(refused.data?.asObject?["path"]?.asString?.isEmpty == false)
        #expect(try await service.getAgentSession(agentID: "publisher", sessionID: session.id).events.count == before)
        #expect(
            try await service.listAgentUISurfaces(agentID: "publisher", sessionID: session.id).first?.components.first?.text == "Initial")
    }
    async let first = UIRenderTool().invoke(arguments: uiArguments(uiUpdateJSON, revision: 1), context: context)
    async let second = UIRenderTool().invoke(arguments: uiArguments(uiUpdateJSON, revision: 1), context: context)
    let concurrent = await [first, second]
    #expect(concurrent.filter(\.ok).count == 1)
    #expect(concurrent.first { !$0.ok }?.error?.code == "ui_revision_conflict")
    #expect(try await service.getAgentSession(agentID: "publisher", sessionID: session.id).events.count == before + 1)
    let deletion = #"[{"version":"v0.9.1","deleteSurface":{"surfaceId":"demo"}}]"#
    let closed = await UIRenderTool().invoke(arguments: uiArguments(deletion, revision: 2), context: context)
    #expect(closed.ok && closed.data?.asObject?["isDeleted"]?.asBool == true)
    #expect(try await service.listAgentUISurfaces(agentID: "publisher", sessionID: session.id).isEmpty)
    let stale = await UIRenderTool().invoke(arguments: uiArguments(uiCreationJSON, revision: 0), context: context)
    #expect(stale.error?.code == "ui_revision_conflict" && stale.data?.asObject?["currentRevision"]?.asInt == 3)
    await service.stop()
    let reopened = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
    #expect(try await reopened.listAgentUISurfaces(agentID: "publisher", sessionID: session.id).isEmpty)
    let state = try await reopened.agentUICatalog(agentID: "publisher", sessionID: session.id, surfaceID: "demo")
    #expect(state.asObject?["surface"]?.asObject?["revision"]?.asInt == 3)
    let restored = try await reopened.renderAgentUI(
        agentID: "publisher", sessionID: session.id, request: .init(messages: uiCreationJSON, expectedRevision: 3, fallbackText: "Reopened")
    )
    #expect(restored.revision == 4 && restored.isDeleted == nil)
    await reopened.stop()
}

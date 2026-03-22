import Foundation
import Testing
@testable import sloppy
import PluginSDK

private actor RecordingStreamingGatewayPlugin: StreamingGatewayPlugin {
    struct Snapshot: Sendable {
        var started: [(channelId: String, userId: String)]
        var updated: [String]
        var ended: [String?]
        var sent: [String]
    }

    nonisolated let id: String = "streaming-mock"
    nonisolated let channelIds: [String]

    private var started: [(channelId: String, userId: String)] = []
    private var updated: [String] = []
    private var ended: [String?] = []
    private var sent: [String] = []

    init(channelIds: [String]) {
        self.channelIds = channelIds
    }

    func start(inboundReceiver: any InboundMessageReceiver) async throws {}

    func stop() async {}

    func send(channelId: String, message: String) async throws {
        sent.append(message)
    }

    func beginStreaming(channelId: String, userId: String) async throws -> GatewayOutboundStreamHandle {
        started.append((channelId: channelId, userId: userId))
        return GatewayOutboundStreamHandle(id: "mock-stream-\(started.count)")
    }

    func updateStreaming(handle: GatewayOutboundStreamHandle, channelId: String, content: String) async throws {
        updated.append(content)
    }

    func endStreaming(
        handle: GatewayOutboundStreamHandle,
        channelId: String,
        userId: String,
        finalContent: String?
    ) async throws {
        ended.append(finalContent)
    }

    func snapshot() -> Snapshot {
        Snapshot(started: started, updated: updated, ended: ended, sent: sent)
    }
}

private actor RecordingGatewayPlugin: GatewayPlugin {
    nonisolated let id: String = "gateway-mock"
    nonisolated let channelIds: [String]

    private var sent: [String] = []

    init(channelIds: [String]) {
        self.channelIds = channelIds
    }

    func start(inboundReceiver: any InboundMessageReceiver) async throws {}

    func stop() async {}

    func send(channelId: String, message: String) async throws {
        sent.append(message)
    }

    func messages() -> [String] {
        sent
    }
}

@Test
func channelDeliveryServiceStreamsThroughStreamingPlugin() async throws {
    let store = InMemoryPersistenceStore()
    let delivery = ChannelDeliveryService(store: store)
    let plugin = RecordingStreamingGatewayPlugin(channelIds: ["channel:stream"])
    await delivery.registerPlugin(plugin)

    let streamID = await delivery.beginStream(channelId: "channel:stream", userId: "assistant")
    #expect(streamID != nil)

    if let streamID {
        #expect(await delivery.updateStream(id: streamID, content: "hello") == true)
        #expect(await delivery.endStream(id: streamID, finalContent: "hello world") == true)
    }

    let snapshot = await plugin.snapshot()
    #expect(snapshot.started.count == 1)
    #expect(snapshot.started.first?.channelId == "channel:stream")
    #expect(snapshot.started.first?.userId == "assistant")
    #expect(snapshot.updated == ["hello"])
    #expect(snapshot.ended == ["hello world"])
    #expect(snapshot.sent.isEmpty)
}

@Test
func channelDeliveryServiceFallsBackToRegularSendForPlainPlugin() async throws {
    let store = InMemoryPersistenceStore()
    let delivery = ChannelDeliveryService(store: store)
    let plugin = RecordingGatewayPlugin(channelIds: ["channel:plain"])
    await delivery.registerPlugin(plugin)

    let streamID = await delivery.beginStream(channelId: "channel:plain", userId: "assistant")
    #expect(streamID == nil)
    #expect(await delivery.deliver(channelId: "channel:plain", userId: "assistant", content: "final reply") == true)

    let messages = await plugin.messages()
    #expect(messages == ["final reply"])
}

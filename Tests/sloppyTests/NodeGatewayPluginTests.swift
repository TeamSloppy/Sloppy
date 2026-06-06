import Foundation
import Testing
import PluginSDK
@testable import sloppy

private actor RecordingNodeGatewayReceiver: InboundMessageReceiver {
    struct Message: Sendable, Equatable {
        var channelId: String
        var userId: String
        var content: String
        var topicId: String?
    }

    private var messages: [Message] = []

    func postMessage(
        channelId: String,
        userId: String,
        content: String,
        topicId: String?,
        inboundContext: ChannelInboundContext?,
        attachments: [ChannelAttachment]
    ) async -> Bool {
        messages.append(Message(channelId: channelId, userId: userId, content: content, topicId: topicId))
        return true
    }

    func snapshot() -> [Message] {
        messages
    }
}

@Test
func persistentNodeGatewayProcessHandlesMultipleCallsAndHostRpc() async throws {
    guard nodeIsAvailableForGatewayTests() else {
        return
    }

    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("persistent-node-gateway-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let pluginsRoot = root.appendingPathComponent("plugins", isDirectory: true)
    let pluginDir = pluginsRoot.appendingPathComponent("persistent-gateway", isDirectory: true)
    let stateFile = root.appendingPathComponent("state.jsonl")
    try FileManager.default.createDirectory(at: pluginDir, withIntermediateDirectories: true)

    let manifest = """
    {
      "name": "persistent-gateway",
      "protocol": "gateway",
      "runtime": "nodejs",
      "apiVersion": "2026-05-plugins-v2",
      "entrypoint": "index.js",
      "config": {
        "channelIds": ["main"],
        "stateFile": "\(stateFile.path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))",
        "timeoutMs": 30000
      }
    }
    """
    let script = """
    const fs = require("node:fs");
    const readline = require("node:readline");
    let manifest = null;
    let nextId = 1;
    const pending = new Map();

    function state(event) {
      fs.appendFileSync(manifest.config.stateFile, JSON.stringify(event) + "\\n");
    }
    function write(value) {
      process.stdout.write(JSON.stringify(value) + "\\n");
    }
    function call(method, params) {
      const id = "host-" + nextId++;
      write({ id, method, params });
      return new Promise((resolve, reject) => pending.set(id, { resolve, reject }));
    }

    readline.createInterface({ input: process.stdin, crlfDelay: Infinity }).on("line", async (line) => {
      const request = JSON.parse(line);
      if (request.id && (Object.prototype.hasOwnProperty.call(request, "result") || request.error)) {
        const waiter = pending.get(request.id);
        pending.delete(request.id);
        if (request.error) waiter.reject(new Error(request.error.message));
        else waiter.resolve(request.result);
        return;
      }
      manifest = request.manifest || manifest;
      if (request.method === "plugin.describe") {
        write({
          id: request.id,
          result: {
            gateways: [{
              name: "persistent-gateway",
              channelIds: ["main"],
              capabilities: ["inbound", "streaming", "tool_approval", "plan_input"]
            }]
          }
        });
        process.exit(0);
      } else if (request.method === "gateway.start") {
        state({ event: "start" });
        await call("host.inbound.postMessage", {
          channelId: "main",
          userId: "node:user",
          content: "hello from node",
          topicId: null
        });
        write({ id: request.id, result: { ok: true } });
      } else if (request.method === "gateway.send") {
        state({ event: "send", message: request.params.message });
        write({ id: request.id, result: { ok: true } });
      } else if (request.method === "gateway.stream.start") {
        state({ event: "stream.start" });
        write({ id: request.id, result: { streamId: "stream-1" } });
      } else if (request.method === "gateway.stream.update") {
        state({ event: "stream.update", content: request.params.content });
        write({ id: request.id, result: { ok: true } });
      } else if (request.method === "gateway.stream.end") {
        state({ event: "stream.end", content: request.params.content });
        write({ id: request.id, result: { ok: true } });
      } else if (request.method === "gateway.stop") {
        state({ event: "stop" });
        write({ id: request.id, result: { ok: true } });
        process.exit(0);
      } else {
        write({ id: request.id, error: { message: "unsupported " + request.method } });
      }
    });
    """
    try Data(manifest.utf8).write(to: pluginDir.appendingPathComponent("plugin.json"))
    try Data(script.utf8).write(to: pluginDir.appendingPathComponent("index.js"))

    let receiver = RecordingNodeGatewayReceiver()
    let loader = PluginLoader()
    let loaded = await loader.loadGatewayPluginBundles(
        from: pluginsRoot,
        cacheRootURL: root.appendingPathComponent("plugin-cache", isDirectory: true),
        inboundReceiver: receiver
    )
    let plugin = try #require(loaded.first?.plugin)
    let streaming = try #require(plugin as? any StreamingGatewayPlugin)

    try await plugin.start(inboundReceiver: receiver)
    try await plugin.send(channelId: "main", message: "one", topicId: nil)
    try await plugin.send(channelId: "main", message: "two", topicId: nil)
    let handle = try await streaming.beginStreaming(channelId: "main", userId: "assistant", topicId: nil)
    try await streaming.updateStreaming(handle: handle, channelId: "main", content: "partial")
    try await streaming.endStreaming(handle: handle, channelId: "main", userId: "assistant", finalContent: "final")
    await plugin.stop()

    let inbound = await receiver.snapshot()
    #expect(inbound == [
        .init(channelId: "main", userId: "node:user", content: "hello from node", topicId: nil)
    ])

    let lines = try String(contentsOf: stateFile, encoding: .utf8)
        .split(separator: "\n")
        .map(String.init)
    #expect(lines.contains(#"{"event":"start"}"#))
    #expect(lines.contains(#"{"event":"send","message":"one"}"#))
    #expect(lines.contains(#"{"event":"send","message":"two"}"#))
    #expect(lines.contains(#"{"event":"stream.start"}"#))
    #expect(lines.contains(#"{"event":"stream.update","content":"partial"}"#))
    #expect(lines.contains(#"{"event":"stream.end","content":"final"}"#))
    #expect(lines.contains(#"{"event":"stop"}"#))
}

private func nodeIsAvailableForGatewayTests() -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", "--version"]
    process.standardOutput = Pipe()
    process.standardError = Pipe()
    do {
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0
    } catch {
        return false
    }
}

import Foundation
import PluginSDK
import Protocols
import Testing
@testable import sloppy

@Suite("Node plugin API v2")
struct NodePluginV2Tests {
    @Test
    func manifestDetectsV2AndParsesPermissions() throws {
        let manifest = try JSONDecoder().decode(
            PluginManifest.self,
            from: Data("""
            {
              "name": "weather-plugin",
              "version": "1.0.0",
              "runtime": "nodejs",
              "apiVersion": "2026-05-plugins-v2",
              "entrypoint": "index.js",
              "permissions": {
                "secrets": ["WEATHER_API_KEY"],
                "network": ["api.weather.example"],
                "filesystem": [],
                "tool_dispatch": ["system.list_tools"],
                "model_calls": true,
                "project_context": true,
                "channel_send": ["telegram"],
                "channel_inject": []
              }
            }
            """.utf8)
        )

        #expect(manifest.protocol == "plugin")
        #expect(manifest.isNodePluginAPIV2)
        #expect(manifest.permissions.secrets == ["WEATHER_API_KEY"])
        #expect(manifest.permissions.network == ["api.weather.example"])
        #expect(manifest.permissions.toolDispatch == ["system.list_tools"])
        #expect(manifest.permissions.modelCalls)
        #expect(manifest.permissions.projectContext)
        #expect(manifest.matches(protocol: "tool"))
    }

    @Test
    func installerAcceptsV2ManifestWithoutProtocol() throws {
        let root = try makePluginFixture(
            manifest: """
            {
              "name": "installable-v2",
              "version": "1.0.0",
              "runtime": "nodejs",
              "apiVersion": "2026-05-plugins-v2",
              "entrypoint": "index.js"
            }
            """,
            script: nodeV2FixtureScript,
            directoryName: "installable-v2"
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let installer = PluginPackageInstaller(
            pluginsRootURL: root.appendingPathComponent("plugins", isDirectory: true),
            cacheRootURL: root.appendingPathComponent("plugin-cache", isDirectory: true)
        )

        let manifest = try installer.validateSourcePackage(
            at: root.appendingPathComponent("installable-v2", isDirectory: true)
        )
        #expect(manifest.protocol == "plugin")
        #expect(manifest.isNodePluginAPIV2)
    }

    @Test
    func describeHandshakeRegistersToolSchemaAndInvokesNamespacedTool() async throws {
        guard nodeIsAvailableForV2Tests() else {
            return
        }

        let root = try makePluginFixture(
            manifest: """
            {
              "name": "echo-v2",
              "version": "1.0.0",
              "runtime": "nodejs",
              "apiVersion": "2026-05-plugins-v2",
              "entrypoint": "index.js"
            }
            """,
            script: nodeV2FixtureScript
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let loader = PluginLoader()
        let loaded = await loader.loadToolPluginBundles(
            from: root,
            cacheRootURL: root.appendingPathComponent("plugin-cache", isDirectory: true)
        )

        let plugin = try #require(loaded.first?.plugin)
        #expect(plugin.supportedTools == ["echo.v2"])
        #expect(plugin.toolDefinitions.first?.title == "Echo v2")
        #expect(plugin.toolDefinitions.first?.inputSchema.asObject?["required"]?.asArray == [.string("message")])

        let result = try await plugin.invoke(tool: "echo.v2", arguments: ["message": .string("hello")])
        #expect(result.asObject?["echo"] == .string("hello"))
        #expect(result.asObject?["method"] == .string("tool.invoke"))
    }

    @Test
    func unsupportedV2MethodSurfacesPluginError() async throws {
        guard nodeIsAvailableForV2Tests() else {
            return
        }

        let root = try makePluginFixture(
            manifest: """
            {
              "name": "echo-v2",
              "version": "1.0.0",
              "runtime": "nodejs",
              "apiVersion": "2026-05-plugins-v2",
              "entrypoint": "index.js"
            }
            """,
            script: nodeV2FixtureScript
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let pluginDir = root.appendingPathComponent("echo-v2", isDirectory: true)
        let manifest = try #require(PluginLoader().loadManifest(at: pluginDir))
        let runtime = try NodePluginRuntime(manifest: manifest, pluginDirectory: pluginDir)

        await #expect(throws: NodePluginRuntimeError.self) {
            _ = try await runtime.callJSON("missing.method")
        }
    }

    @Test
    func sourceControlProviderUsesNamespacedV2Methods() async throws {
        guard nodeIsAvailableForV2Tests() else {
            return
        }

        let root = try makePluginFixture(
            manifest: """
            {
              "name": "scm-v2",
              "version": "1.0.0",
              "runtime": "nodejs",
              "apiVersion": "2026-05-plugins-v2",
              "entrypoint": "index.js"
            }
            """,
            script: nodeV2FixtureScript,
            directoryName: "scm-v2"
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let loader = PluginLoader()
        let loaded = await loader.loadSourceControlPluginBundles(
            from: root,
            cacheRootURL: root.appendingPathComponent("plugin-cache", isDirectory: true)
        )
        let provider = try #require(loaded.first?.provider)
        #expect(provider.displayName == "Source Control v2")
        #expect(provider.capabilities.contains(.worktrees))

        let worktree = try await provider.createWorktree(repoPath: "/tmp/repo", taskId: "task-1", baseBranch: "HEAD")
        #expect(worktree.worktreePath == "/tmp/repo/.sloppy-worktrees/task-1")
        #expect(worktree.branchName == "sloppy/task-1")
    }
}

private func makePluginFixture(
    manifest: String,
    script: String,
    directoryName: String = "echo-v2"
) throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("sloppy-node-plugin-v2-\(UUID().uuidString)", isDirectory: true)
    let pluginDir = root.appendingPathComponent(directoryName, isDirectory: true)
    try FileManager.default.createDirectory(at: pluginDir, withIntermediateDirectories: true)
    try Data(manifest.utf8).write(to: pluginDir.appendingPathComponent("plugin.json"))
    try Data(script.utf8).write(to: pluginDir.appendingPathComponent("index.js"))
    return root
}

private let nodeV2FixtureScript = """
#!/usr/bin/env node
"use strict";

let input = "";
process.stdin.setEncoding("utf8");
process.stdin.on("data", (chunk) => {
  input += chunk;
});
process.stdin.on("end", () => {
  const request = JSON.parse(input.trim().split("\\n").find(Boolean));
  const respond = (payload) => process.stdout.write(`${JSON.stringify({ id: request.id, ...payload })}\\n`);
  if (request.method === "plugin.describe") {
    respond({
      result: {
        tools: [{
          name: "echo.v2",
          title: "Echo v2",
          description: "Echoes a message through the v2 tool API.",
          inputSchema: {
            type: "object",
            properties: { message: { type: "string" } },
            required: ["message"]
          }
        }],
        source_control: [{
          name: "scm-v2",
          displayName: "Source Control v2",
          capabilities: ["worktrees"]
        }]
      }
    });
    return;
  }
  if (request.method === "tool.invoke") {
    respond({ result: { echo: request.params.arguments.message, method: request.method } });
    return;
  }
  if (request.method === "source_control.createWorktree") {
    respond({
      result: {
        worktreePath: `${request.params.repoPath}/.sloppy-worktrees/${request.params.taskId}`,
        branchName: `sloppy/${request.params.taskId}`
      }
    });
    return;
  }
  respond({ error: { code: "unsupported", message: `Unsupported method: ${request.method}` } });
});
"""

private func nodeIsAvailableForV2Tests() -> Bool {
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

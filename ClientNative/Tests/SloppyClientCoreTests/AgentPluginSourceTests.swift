import Foundation
import Testing
@testable import SloppyClientCore

@Suite("Agent Plugin client")
struct AgentPluginSourceTests {
    private func source(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }

    @Test("settings expose installed store and registry management")
    func settingsSurface() throws {
        let view = try source("Sources/SloppyFeatureSettings/Screens/Settings/Sections/PluginsSection.swift")
        #expect(view.contains("case installed = \"Installed\""))
        #expect(view.contains("case store = \"Store\""))
        #expect(view.contains("case registries = \"Registries\""))
        #expect(view.contains(".fileImporter("))
        #expect(view.contains("allowedContentTypes: [.zip]"))
        #expect(view.contains(".sheet(item: $model.presentedInstall)"))
        #expect(view.contains("Legacy plugin connections"))
    }

    @Test("API client uses dedicated package endpoints")
    func apiSurface() throws {
        let api = try source("Sources/SloppyClientCore/SloppyAPIClient.swift")
        #expect(api.contains("/v1/agent-plugins/uploads"))
        #expect(api.contains("/v1/agent-plugins/inspections"))
        #expect(api.contains("/v1/agent-plugins/plans"))
        #expect(api.contains("/v1/agent-plugin-registries"))
        #expect(api.contains("/v1/agent-plugin-catalog"))
    }

    @Test("installed package payload decodes component inventory")
    func installedPackageDecodes() throws {
        let data = Data(#"{"id":"tests.sample","name":"Sample","version":"1.0.0","source":{"kind":"url","url":"https://example.com/sample.zip"},"sha256":"abc","status":"installed","agentIds":["main"],"manifest":{"schemaVersion":1,"id":"tests.sample","name":"Sample","version":"1.0.0","inputs":[],"components":{"skills":[{"id":"review","path":"skills/review"}],"mcpServers":[],"sloppyPlugins":[],"software":[]}},"componentHashes":{},"installedAt":"2026-09-17T00:00:00Z","updatedAt":"2026-09-17T00:00:00Z"}"#.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let value = try decoder.decode(ClientInstalledAgentPlugin.self, from: data)
        #expect(value.id == "tests.sample")
        #expect(value.manifest.components.skills.map(\.id) == ["review"])
    }
}

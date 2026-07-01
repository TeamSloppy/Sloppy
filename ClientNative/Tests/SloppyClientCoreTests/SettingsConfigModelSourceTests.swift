import Foundation
import Testing

@Suite("Settings config model source")
struct SettingsConfigModelSourceTests {
    private func source(_ relativePath: String) throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: packageRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    @Test("sloppy config supports dashboard browser mcp and model routing fields")
    func sloppyConfigSupportsDashboardBrowserMcpAndModelRoutingFields() throws {
        let sourceText = try source("Sources/SloppyClientCore/SloppyConfig.swift")

        #expect(sourceText.contains("public struct Browser"))
        #expect(sourceText.contains("public struct MCP"))
        #expect(sourceText.contains("public struct MCPServer"))
        #expect(sourceText.contains("public struct UI"))
        #expect(sourceText.contains("public struct TUI"))
        #expect(sourceText.contains("public struct ToolHooks"))
        #expect(sourceText.contains("public struct Compactor"))
        #expect(sourceText.contains("public var browser: Browser"))
        #expect(sourceText.contains("public var mcp: MCP"))
        #expect(sourceText.contains("public var ui: UI"))
        #expect(sourceText.contains("public var tui: TUI"))
        #expect(sourceText.contains("public var toolHooks: ToolHooks"))
        #expect(sourceText.contains("public var toolBudgetExhausted: Int"))
        #expect(sourceText.contains("public var modelRouting: [String: String]"))
        #expect(sourceText.contains("public var compactor: Compactor"))
    }

    @Test("client core exposes approvals endpoints")
    func clientCoreExposesApprovalsEndpoints() throws {
        let backend = try source("Sources/SloppyClientCore/BackendServices.swift")
        let api = try source("Sources/SloppyClientCore/SloppyAPIClient.swift")

        #expect(backend.contains("public struct AccessUser"))
        #expect(backend.contains("fetchAccessUsers("))
        #expect(backend.contains("deleteAccessUser("))
        #expect(api.contains("fetchAccessUsers("))
        #expect(api.contains("deleteAccessUser("))
    }
}

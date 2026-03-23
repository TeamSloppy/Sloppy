import Foundation
import Testing
@testable import Protocols
@testable import sloppy

@Test
func missingACPConfigFallsBackToDefaults() throws {
    let json =
        """
        {
          "listen": { "host": "0.0.0.0", "port": 25101 },
          "auth": { "token": "dev-token" },
          "models": [],
          "memory": { "backend": "sqlite-local-vectors" },
          "nodes": ["local"],
          "gateways": [],
          "plugins": [],
          "sqlitePath": "core.sqlite"
        }
        """

    let decoded = try JSONDecoder().decode(CoreConfig.self, from: Data(json.utf8))
    #expect(decoded.acp.enabled == false)
    #expect(decoded.acp.targets.isEmpty)
}

@Test
func acpConfigDecodesTargetsFromJSON() throws {
    let json =
        """
        {
          "listen": { "host": "0.0.0.0", "port": 25101 },
          "auth": { "token": "dev-token" },
          "models": [],
          "memory": { "backend": "sqlite-local-vectors" },
          "nodes": ["local"],
          "gateways": [],
          "plugins": [],
          "sqlitePath": "core.sqlite",
          "acp": {
            "enabled": true,
            "targets": [
              {
                "id": "claude-code",
                "title": "Claude Code",
                "transport": "stdio",
                "command": "/usr/local/bin/claude",
                "arguments": ["--mcp"],
                "cwd": "/tmp/workspace",
                "environment": { "ANTHROPIC_API_KEY": "sk-test" },
                "timeoutMs": 60000,
                "enabled": true
              }
            ]
          }
        }
        """

    let decoded = try JSONDecoder().decode(CoreConfig.self, from: Data(json.utf8))
    #expect(decoded.acp.enabled == true)
    #expect(decoded.acp.targets.count == 1)

    let target = decoded.acp.targets[0]
    #expect(target.id == "claude-code")
    #expect(target.title == "Claude Code")
    #expect(target.transport == .stdio)
    #expect(target.command == "/usr/local/bin/claude")
    #expect(target.arguments == ["--mcp"])
    #expect(target.cwd == "/tmp/workspace")
    #expect(target.environment["ANTHROPIC_API_KEY"] == "sk-test")
    #expect(target.timeoutMs == 60000)
    #expect(target.enabled == true)
}

@Test
func acpTargetDecodesWithMinimalFields() throws {
    let json =
        """
        {
          "id": "minimal",
          "command": "/usr/bin/agent"
        }
        """

    let decoded = try JSONDecoder().decode(CoreConfig.ACP.Target.self, from: Data(json.utf8))
    #expect(decoded.id == "minimal")
    #expect(decoded.title == "minimal")
    #expect(decoded.transport == .stdio)
    #expect(decoded.command == "/usr/bin/agent")
    #expect(decoded.arguments.isEmpty)
    #expect(decoded.cwd == nil)
    #expect(decoded.environment.isEmpty)
    #expect(decoded.timeoutMs == 30_000)
    #expect(decoded.enabled == true)
}

@Test
func acpConfigRoundTrips() throws {
    let original = CoreConfig.ACP(
        enabled: true,
        targets: [
            .init(
                id: "test-agent",
                title: "Test Agent",
                transport: .stdio,
                command: "/usr/local/bin/test-agent",
                arguments: ["--verbose"],
                cwd: "/tmp/test",
                environment: ["KEY": "VALUE"],
                timeoutMs: 45_000,
                enabled: true
            )
        ]
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    let data = try encoder.encode(original)
    let decoded = try JSONDecoder().decode(CoreConfig.ACP.self, from: data)

    #expect(decoded == original)
}

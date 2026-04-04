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
                "enabled": true,
                "permissionMode": "allow_once"
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
    #expect(target.permissionMode == .allowOnce)
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
    #expect(decoded.permissionMode == .allowOnce)
    #expect(decoded.strictHostKeyChecking == true)
    #expect(decoded.headers.isEmpty)
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
                enabled: true,
                permissionMode: .allowOnce
            )
        ]
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    let data = try encoder.encode(original)
    let decoded = try JSONDecoder().decode(CoreConfig.ACP.self, from: data)

    #expect(decoded == original)
}

@Test
func acpConfigDecodesSSHAndWebSocketTargets() throws {
    let json =
        """
        {
          "enabled": true,
          "targets": [
            {
              "id": "ssh-agent",
              "title": "SSH Agent",
              "transport": "ssh",
              "host": "example.com",
              "user": "deploy",
              "port": 2222,
              "identityFile": "~/.ssh/id_ed25519",
              "strictHostKeyChecking": false,
              "remoteCommand": "/usr/local/bin/agent",
              "cwd": "/srv/app",
              "timeoutMs": 5000,
              "enabled": true,
              "permissionMode": "deny"
            },
            {
              "id": "ws-agent",
              "title": "WS Agent",
              "transport": "websocket",
              "url": "wss://agent.example/ws",
              "headers": { "Authorization": "Bearer token" },
              "cwd": "/workspace",
              "timeoutMs": 4000,
              "enabled": true
            }
          ]
        }
        """

    let decoded = try JSONDecoder().decode(CoreConfig.ACP.self, from: Data(json.utf8))
    #expect(decoded.targets.count == 2)
    #expect(decoded.targets[0].transport == .ssh)
    #expect(decoded.targets[0].host == "example.com")
    #expect(decoded.targets[0].remoteCommand == "/usr/local/bin/agent")
    #expect(decoded.targets[0].permissionMode == .deny)
    #expect(decoded.targets[1].transport == .websocket)
    #expect(decoded.targets[1].url == "wss://agent.example/ws")
    #expect(decoded.targets[1].headers["Authorization"] == "Bearer token")
    #expect(decoded.targets[1].permissionMode == .allowOnce)
}

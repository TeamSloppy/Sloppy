import Foundation
import Testing
@testable import Protocols

@Test
func agentRuntimeConfigDecodesNativeByDefault() throws {
    let json = """
        { "id": "agent-1", "displayName": "Agent One", "role": "dev", "createdAt": "2025-01-01T00:00:00Z" }
        """

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let summary = try decoder.decode(AgentSummary.self, from: Data(json.utf8))
    #expect(summary.runtime.type == .native)
    #expect(summary.runtime.acp == nil)
}

@Test
func agentRuntimeConfigDecodesACPRuntime() throws {
    let json = """
        {
          "id": "acp-agent",
          "displayName": "ACP Agent",
          "role": "coder",
          "createdAt": "2025-01-01T00:00:00Z",
          "runtime": {
            "type": "acp",
            "acp": {
              "targetId": "claude-code",
              "cwd": "/tmp/workspace"
            }
          }
        }
        """

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let summary = try decoder.decode(AgentSummary.self, from: Data(json.utf8))
    #expect(summary.runtime.type == .acp)
    #expect(summary.runtime.acp?.targetId == "claude-code")
    #expect(summary.runtime.acp?.cwd == "/tmp/workspace")
}

@Test
func agentRuntimeConfigRoundTrips() throws {
    let native = AgentRuntimeConfig(type: .native, acp: nil)
    let acpConfig = AgentRuntimeConfig(type: .acp, acp: .init(targetId: "test", cwd: "/tmp"))

    let encoder = JSONEncoder()
    let nativeData = try encoder.encode(native)
    let acpData = try encoder.encode(acpConfig)
    let decodedNative = try JSONDecoder().decode(AgentRuntimeConfig.self, from: nativeData)
    let decodedACP = try JSONDecoder().decode(AgentRuntimeConfig.self, from: acpData)

    #expect(decodedNative == native)
    #expect(decodedACP == acpConfig)
}

@Test
func agentConfigDetailDecodesRuntimeFromJSON() throws {
    let json = """
        {
          "agentId": "coder",
          "selectedModel": null,
          "availableModels": [],
          "documents": {
            "userMarkdown": "# User\\n",
            "agentsMarkdown": "# Agent\\n",
            "soulMarkdown": "# Soul\\n",
            "identityMarkdown": "# Identity\\n"
          },
          "runtime": {
            "type": "acp",
            "acp": { "targetId": "claude-code" }
          }
        }
        """

    let decoded = try JSONDecoder().decode(AgentConfigDetail.self, from: Data(json.utf8))
    #expect(decoded.runtime.type == .acp)
    #expect(decoded.runtime.acp?.targetId == "claude-code")
    #expect(decoded.runtime.acp?.cwd == nil)
    #expect(decoded.selectedModel == nil)
}

@Test
func agentConfigUpdateRequestDecodesRuntimeFromJSON() throws {
    let json = """
        {
          "selectedModel": null,
          "documents": {
            "userMarkdown": "# User\\n",
            "agentsMarkdown": "# Agent\\n",
            "soulMarkdown": "# Soul\\n",
            "identityMarkdown": "# Identity\\n"
          },
          "runtime": {
            "type": "acp",
            "acp": { "targetId": "test-target", "cwd": "/projects/app" }
          }
        }
        """

    let decoded = try JSONDecoder().decode(AgentConfigUpdateRequest.self, from: Data(json.utf8))
    #expect(decoded.runtime.type == .acp)
    #expect(decoded.runtime.acp?.targetId == "test-target")
    #expect(decoded.runtime.acp?.cwd == "/projects/app")
}

@Test
func acpProbeTargetEncodesCorrectly() throws {
    let target = ACPProbeTarget(
        id: "test-acp",
        title: "Test ACP",
        transport: "stdio",
        command: "/usr/local/bin/claude",
        arguments: ["--flag"],
        cwd: "/tmp",
        environment: ["KEY": "val"],
        timeoutMs: 15_000,
        enabled: true
    )

    let request = ACPTargetProbeRequest(target: target)
    let data = try JSONEncoder().encode(request)
    let decoded = try JSONDecoder().decode(ACPTargetProbeRequest.self, from: data)

    #expect(decoded.target == target)
}

@Test
func acpTargetProbeResponseEncodesAllFields() throws {
    let response = ACPTargetProbeResponse(
        ok: true,
        targetId: "test",
        targetTitle: "Test",
        agentName: "Claude",
        agentVersion: "1.0.0",
        supportsSessionList: true,
        supportsLoadSession: false,
        supportsPromptImage: true,
        supportsMCPHTTP: false,
        supportsMCPSSE: false,
        message: "Connected"
    )

    let data = try JSONEncoder().encode(response)
    let decoded = try JSONDecoder().decode(ACPTargetProbeResponse.self, from: data)

    #expect(decoded == response)
}

@Test
func agentCreateRequestWithACPRuntime() throws {
    let request = AgentCreateRequest(
        id: "acp-agent",
        displayName: "ACP Agent",
        role: "coder",
        runtime: .init(type: .acp, acp: .init(targetId: "claude-code"))
    )

    let data = try JSONEncoder().encode(request)
    let decoded = try JSONDecoder().decode(AgentCreateRequest.self, from: data)

    #expect(decoded.runtime?.type == .acp)
    #expect(decoded.runtime?.acp?.targetId == "claude-code")
}

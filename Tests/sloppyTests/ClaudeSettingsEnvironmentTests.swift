import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import sloppy
@testable import Protocols

private func makeAnthropicProbeHTTPResponse(url: URL, statusCode: Int = 200) -> HTTPURLResponse {
    HTTPURLResponse(
        url: url,
        statusCode: statusCode,
        httpVersion: nil,
        headerFields: ["Content-Type": "application/json"]
    )!
}

private actor AnthropicProbeRecorder {
    private(set) var url: String?
    private(set) var authorization: String?

    func record(url: String?, authorization: String?) {
        self.url = url
        self.authorization = authorization
    }
}

@Test
func claudeSettingsEnvironmentReadsAnthropicEnvKeys() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("sloppy-claude-settings-\(UUID().uuidString)", isDirectory: true)
    let settingsURL = root
        .appendingPathComponent(".claude", isDirectory: true)
        .appendingPathComponent("settings.json")
    try FileManager.default.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    try Data("""
    {
      "env": {
        "ANTHROPIC_BASE_URL": "https://api.anthropic.com",
        "ANTHROPIC_AUTH_TOKEN": "settings-oauth-token"
      }
    }
    """.utf8).write(to: settingsURL)

    let settings = ClaudeSettingsEnvironment.load(
        workspaceRootURL: root,
        currentDirectoryURL: nil,
        homeDirectoryURL: FileManager.default.temporaryDirectory
    )

    #expect(settings.baseURLString == "https://api.anthropic.com")
    #expect(settings.authToken == "settings-oauth-token")
    #expect(settings.baseURL == URL(string: "https://api.anthropic.com"))
}

@Test
func anthropicProbeUsesClaudeSettingsAuthTokenWhenCredentialsAreEmpty() async throws {
    var config = CoreConfig.test
    config.models = [
        .init(
            title: "anthropic-oauth",
            apiKey: "",
            apiUrl: "",
            model: "anthropic:claude-3-5-haiku-20241022",
            providerCatalogId: "anthropic-oauth"
        )
    ]

    let recorder = AnthropicProbeRecorder()
    let settings = ClaudeSettingsEnvironment(
        baseURLString: "https://api.anthropic.com",
        authToken: "settings-oauth-token"
    )
    let service = ProviderProbeService(
        environmentLookup: { _ in nil },
        transport: { request in
            await recorder.record(
                url: request.url?.absoluteString,
                authorization: request.value(forHTTPHeaderField: "Authorization")
            )
            return (Data(), makeAnthropicProbeHTTPResponse(url: request.url!))
        },
        claudeSettingsProvider: { settings }
    )

    let response = await service.probe(
        config: config,
        request: ProviderProbeRequest(
            providerId: .anthropic,
            apiUrl: ""
        )
    )

    #expect(response.ok == true)
    #expect(response.usedEnvironmentKey == true)
    #expect(await recorder.url == "https://api.anthropic.com/v1/messages")
    #expect(await recorder.authorization == "Bearer settings-oauth-token")
}

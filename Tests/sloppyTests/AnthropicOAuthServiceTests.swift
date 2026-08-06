import Foundation
import Testing
@testable import sloppy

@Test
func anthropicOAuthStartLoginUsesSupportedScopes() throws {
    let workspaceRootURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("anthropic-oauth-start-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: workspaceRootURL) }

    let service = AnthropicOAuthService(workspaceRootURL: workspaceRootURL)
    let response = try service.startLogin(redirectURI: "http://127.0.0.1:4173/config")
    let authorizationURL = try #require(URL(string: response.authorizationURL))
    let components = try #require(URLComponents(url: authorizationURL, resolvingAgainstBaseURL: false))
    let queryItems = components.queryItems ?? []
    let scopes = Set(
        queryItems
            .first(where: { $0.name == "scope" })?
            .value?
            .split(separator: " ")
            .map(String.init) ?? []
    )

    #expect(components.scheme == "https")
    #expect(components.host == "platform.claude.com")
    #expect(scopes == [
        "user:inference",
        "user:profile",
        "user:sessions:claude_code",
    ])
    #expect(scopes.contains("offline_access") == false)
    #expect(queryItems.first(where: { $0.name == "client_id" })?.value == "9d1c250a-e61b-44d9-88ed-5944d1962f5e")
    #expect(queryItems.first(where: { $0.name == "redirect_uri" })?.value == "http://127.0.0.1:4173/config")
    #expect(queryItems.first(where: { $0.name == "code_challenge_method" })?.value == "S256")
    #expect(queryItems.first(where: { $0.name == "state" })?.value == response.state)

    let pendingURL = workspaceRootURL.appendingPathComponent("auth/anthropic-oauth-pending.json")
    #expect(FileManager.default.fileExists(atPath: pendingURL.path))
}

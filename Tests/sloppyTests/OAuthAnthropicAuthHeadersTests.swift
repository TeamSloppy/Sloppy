import Foundation
import PluginSDK
import Testing

@Test
func oauthAnthropicAuth_consoleApiKeyUsesXApiKey() {
    let base = URL(string: "https://api.anthropic.com")!
    let headers = OAuthAnthropicAuthHeaders.authenticationHeaders(
        apiKey: "sk-ant-api03-xxx",
        baseURL: base,
        additionalBetas: nil
    )
    #expect(headers["x-api-key"] == "sk-ant-api03-xxx")
    #expect(headers["Authorization"] == nil)
}

@Test
func oauthAnthropicAuth_oauthStyleUsesBearerAndClaudeCodeHeaders() {
    let base = URL(string: "https://api.anthropic.com")!
    let headers = OAuthAnthropicAuthHeaders.authenticationHeaders(
        apiKey: "sk-ant-oat01-oauth-token",
        baseURL: base,
        additionalBetas: nil
    )
    #expect(headers["Authorization"] == "Bearer sk-ant-oat01-oauth-token")
    #expect(headers["x-api-key"] == nil)
    #expect(headers["x-app"] == "cli")
    #expect(headers["user-agent"]?.contains("claude-cli/") == true)
    #expect(headers["anthropic-beta"]?.contains("oauth-2025-04-20") == true)
}

@Test
func oauthAnthropicAuth_thirdPartyHostAlwaysUsesXApiKeyEvenForNonSkAntApi() {
    let base = URL(string: "https://bedrock-proxy.example/v1")!
    let headers = OAuthAnthropicAuthHeaders.authenticationHeaders(
        apiKey: "some-proxy-secret",
        baseURL: base,
        additionalBetas: nil
    )
    #expect(headers["x-api-key"] == "some-proxy-secret")
    #expect(headers["Authorization"] == nil)
}

@Test
func oauthAnthropicAuth_miniMaxUsesBearer() {
    let base = URL(string: "https://api.minimax.io/anthropic/v1")!
    let headers = OAuthAnthropicAuthHeaders.authenticationHeaders(
        apiKey: "minimax-key",
        baseURL: base,
        additionalBetas: nil
    )
    #expect(headers["Authorization"] == "Bearer minimax-key")
    #expect(headers["x-api-key"] == nil)
}

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import Core
@testable import Protocols

private func makeOAuthHTTPResponse(url: URL, statusCode: Int = 200) -> HTTPURLResponse {
    HTTPURLResponse(
        url: url,
        statusCode: statusCode,
        httpVersion: nil,
        headerFields: ["Content-Type": "application/json"]
    )!
}

private func makeJWT(claims: [String: Any]) throws -> String {
    let header = try JSONSerialization.data(withJSONObject: ["alg": "none", "typ": "JWT"])
    let payload = try JSONSerialization.data(withJSONObject: claims)
    return "\(base64URLEncode(header)).\(base64URLEncode(payload)).signature"
}

private func base64URLEncode(_ data: Data) -> String {
    data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

@Test
func openAIOAuthStartLoginPersistsPendingSession() throws {
    let workspaceRootURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("openai-oauth-start-\(UUID().uuidString)", isDirectory: true)
    let service = OpenAIOAuthService(workspaceRootURL: workspaceRootURL)

    let response = try service.startLogin(redirectURI: "http://127.0.0.1:4173/config")
    let authorizationURL = try #require(URL(string: response.authorizationURL))
    let components = try #require(URLComponents(url: authorizationURL, resolvingAgainstBaseURL: false))
    let queryItems = components.queryItems ?? []

    #expect(components.scheme == "https")
    #expect(components.host == "auth.openai.com")
    #expect(queryItems.first(where: { $0.name == "client_id" })?.value == "app_EMoamEEZ73f0CkXaXp7hrann")
    #expect(queryItems.first(where: { $0.name == "redirect_uri" })?.value == "http://127.0.0.1:4173/config")
    #expect(queryItems.first(where: { $0.name == "code_challenge_method" })?.value == "S256")
    #expect(queryItems.first(where: { $0.name == "state" })?.value == response.state)

    let pendingURL = workspaceRootURL.appendingPathComponent("auth/openai-oauth-pending.json")
    #expect(FileManager.default.fileExists(atPath: pendingURL.path))
}

@Test
func openAIOAuthCompleteLoginStoresTokensAndStatus() async throws {
    let workspaceRootURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("openai-oauth-complete-\(UUID().uuidString)", isDirectory: true)
    let accessToken = try makeJWT(
        claims: [
            "exp": NSNumber(value: 2_000_000_000),
            "https://api.openai.com/auth": [
                "chatgpt_account_id": "acct_test_123",
                "chatgpt_plan_type": "plus"
            ]
        ]
    )
    let service = OpenAIOAuthService(
        workspaceRootURL: workspaceRootURL,
        transport: { request in
            let body =
                """
                {
                  "access_token": "\(accessToken)",
                  "refresh_token": "refresh_test",
                  "id_token": "id_test"
                }
                """
            return (Data(body.utf8), makeOAuthHTTPResponse(url: request.url ?? URL(string: "https://auth.openai.com/oauth/token")!))
        }
    )

    let start = try service.startLogin(redirectURI: "http://127.0.0.1:4173/config")
    let completion = try await service.completeLogin(
        request: OpenAIOAuthCompleteRequest(
            callbackURL: "http://127.0.0.1:4173/config?code=test-code&state=\(start.state)"
        )
    )

    #expect(completion.ok == true)
    #expect(completion.accountId == "acct_test_123")
    #expect(completion.planType == "plus")

    let status = service.status()
    #expect(status.hasCredentials == true)
    #expect(status.accountId == "acct_test_123")
    #expect(status.planType == "plus")

    let authURL = workspaceRootURL.appendingPathComponent("auth/openai-oauth-auth.json")
    #expect(FileManager.default.fileExists(atPath: authURL.path))
}

@Test
func openAIOAuthFetchModelsAcceptsModelsArrayPayload() async throws {
    let workspaceRootURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("openai-oauth-models-\(UUID().uuidString)", isDirectory: true)
    let accessToken = try makeJWT(
        claims: [
            "exp": NSNumber(value: 2_000_000_000),
            "https://api.openai.com/auth": [
                "chatgpt_account_id": "acct_test_123",
                "chatgpt_plan_type": "plus"
            ]
        ]
    )

    let service = OpenAIOAuthService(
        workspaceRootURL: workspaceRootURL,
        transport: { request in
            let url = request.url?.absoluteString ?? ""
            if url.contains("/oauth/token") {
                let body =
                    """
                    {
                      "access_token": "\(accessToken)",
                      "refresh_token": "refresh_test",
                      "id_token": "id_test"
                    }
                    """
                return (Data(body.utf8), makeOAuthHTTPResponse(url: request.url ?? URL(string: "https://auth.openai.com/oauth/token")!))
            }

            let modelsBody =
                """
                {
                  "models": [
                    {
                      "id": "gpt-5.3-codex",
                      "display_name": "GPT-5.3 Codex",
                      "supported_reasoning_efforts": ["low", "medium", "high"]
                    }
                  ]
                }
                """
            return (Data(modelsBody.utf8), makeOAuthHTTPResponse(url: request.url ?? URL(string: "https://chatgpt.com/backend-api/codex/models")!))
        }
    )

    let start = try service.startLogin(redirectURI: "http://127.0.0.1:4173/config")
    _ = try await service.completeLogin(
        request: OpenAIOAuthCompleteRequest(
            callbackURL: "http://127.0.0.1:4173/config?code=test-code&state=\(start.state)"
        )
    )

    let models = try await service.fetchModels()
    #expect(models.contains(where: { $0.id == "gpt-5.3-codex" }))
}

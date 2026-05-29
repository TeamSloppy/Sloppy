import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import Protocols
@testable import sloppy

private final class GeminiOAuthTokenBodyBox: @unchecked Sendable {
    var token: String = ""
}

private func makeGeminiOAuthHTTPResponse(url: URL, statusCode: Int = 200) -> HTTPURLResponse {
    HTTPURLResponse(
        url: url,
        statusCode: statusCode,
        httpVersion: nil,
        headerFields: ["Content-Type": "application/json"]
    )!
}

@Test
func geminiOAuthStartLoginPersistsPendingSessionWithPKCE() throws {
    let workspaceRootURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("gemini-oauth-start-\(UUID().uuidString)", isDirectory: true)
    let service = GeminiOAuthService(workspaceRootURL: workspaceRootURL)

    let response = try service.startLogin(redirectURI: "http://127.0.0.1:8085/oauth2callback")
    let authorizationURL = try #require(URL(string: response.authorizationURL))
    let components = try #require(URLComponents(url: authorizationURL, resolvingAgainstBaseURL: false))
    let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
        item.value.map { (item.name, $0) }
    })

    #expect(authorizationURL.host == "accounts.google.com")
    #expect(items["response_type"] == "code")
    #expect(items["redirect_uri"] == "http://127.0.0.1:8085/oauth2callback")
    #expect(items["code_challenge_method"] == "S256")
    #expect(items["access_type"] == "offline")
    #expect(items["prompt"] == "consent")
    #expect(items["scope"]?.contains("https://www.googleapis.com/auth/cloud-platform") == true)
    #expect(items["scope"]?.contains("https://www.googleapis.com/auth/userinfo.email") == true)
    #expect(items["state"] == response.state)
    #expect(items["code_challenge"]?.isEmpty == false)
    #expect(FileManager.default.fileExists(atPath: workspaceRootURL.appendingPathComponent("auth/gemini-oauth-pending.json").path))
}

@Test
func geminiOAuthCompleteLoginExchangesCodeAndStoresSloppyCredentials() async throws {
    let workspaceRootURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("gemini-oauth-complete-\(UUID().uuidString)", isDirectory: true)
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let tokenRequestBody = GeminiOAuthTokenBodyBox()
    let service = GeminiOAuthService(
        workspaceRootURL: workspaceRootURL,
        transport: { request in
            if request.url?.host == "oauth2.googleapis.com" {
                tokenRequestBody.token = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
                return (
                    Data(
                        """
                        {
                          "access_token": "access-token",
                          "refresh_token": "refresh-token",
                          "expires_in": 3600,
                          "token_type": "Bearer",
                          "scope": "https://www.googleapis.com/auth/cloud-platform https://www.googleapis.com/auth/userinfo.email"
                        }
                        """.utf8
                    ),
                    makeGeminiOAuthHTTPResponse(url: request.url!)
                )
            }
            if request.url?.host == "www.googleapis.com" {
                #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer access-token")
                return (
                    Data(#"{"email":"user@example.com"}"#.utf8),
                    makeGeminiOAuthHTTPResponse(url: request.url!)
                )
            }
            throw URLError(.badURL)
        },
        now: { now }
    )
    let start = try service.startLogin(redirectURI: "http://127.0.0.1:8085/oauth2callback")

    let response = try await service.completeLogin(
        request: GeminiOAuthCompleteRequest(
            callbackURL: "http://127.0.0.1:8085/oauth2callback?code=auth-code&state=\(start.state)"
        )
    )

    #expect(response.ok == true)
    #expect(response.email == "user@example.com")
    #expect(tokenRequestBody.token.contains("grant_type=authorization_code"))
    #expect(tokenRequestBody.token.contains("code=auth-code"))
    #expect(tokenRequestBody.token.contains("code_verifier="))
    let stored = try #require(GeminiOAuthCredentials.load(workspaceRootURL: workspaceRootURL))
    #expect(stored.accessToken == "access-token")
    #expect(stored.refreshToken == "refresh-token")
    #expect(stored.email == "user@example.com")
    #expect(stored.expiryDate == now.addingTimeInterval(3600))
}

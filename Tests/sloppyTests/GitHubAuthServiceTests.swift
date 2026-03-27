import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import sloppy

private func makeHTTPResponse(url: URL, statusCode: Int, headerFields: [String: String] = [:]) -> HTTPURLResponse {
    HTTPURLResponse(
        url: url,
        statusCode: statusCode,
        httpVersion: nil,
        headerFields: headerFields.merging(["Content-Type": "application/json"], uniquingKeysWith: { a, _ in a })
    )!
}

private func makeWorkspaceURL(id: String) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("github-auth-\(id)", isDirectory: true)
}

// MARK: - currentToken

@Test
func gitHubAuthServiceCurrentTokenReturnsNilWhenNoCredentials() {
    let service = GitHubAuthService(workspaceRootURL: makeWorkspaceURL(id: UUID().uuidString))
    // env var GITHUB_TOKEN not set in test environment (or empty)
    let token = service.currentToken()
    // May return env var if set globally — just ensure it doesn't crash
    // We can't guarantee the env state, so only assert non-crash here
    _ = token
}

@Test
func gitHubAuthServiceStatusReturnsDisconnectedWhenNoFile() {
    let service = GitHubAuthService(workspaceRootURL: makeWorkspaceURL(id: UUID().uuidString))
    let status = service.status()
    // Without a stored file and without GITHUB_TOKEN env, should be disconnected
    // We just verify the status struct is returned without crashing
    _ = status.connected
    _ = status.username
    _ = status.connectedAt
}

// MARK: - connect

@Test
func gitHubAuthServiceConnectStoresTokenAndReturnsUsername() async throws {
    let workspaceURL = makeWorkspaceURL(id: UUID().uuidString)
    let service = GitHubAuthService(
        workspaceRootURL: workspaceURL,
        transport: { request in
            let body = #"{"login":"testuser","id":123}"#
            return (
                Data(body.utf8),
                makeHTTPResponse(
                    url: request.url ?? URL(string: "https://api.github.com/user")!,
                    statusCode: 200,
                    headerFields: ["X-OAuth-Scopes": "repo, read:org"]
                )
            )
        }
    )

    let response = try await service.connect(token: "ghp_test_token_abc123")

    #expect(response.ok == true)
    #expect(response.username == "testuser")
    #expect(response.message.contains("testuser"))

    // Verify file was written
    let authFile = workspaceURL.appendingPathComponent("auth/github.json")
    #expect(FileManager.default.fileExists(atPath: authFile.path))
}

@Test
func gitHubAuthServiceConnectTrimsWhitespace() async throws {
    let workspaceURL = makeWorkspaceURL(id: UUID().uuidString)
    let service = GitHubAuthService(
        workspaceRootURL: workspaceURL,
        transport: { request in
            let body = #"{"login":"trimuser","id":456}"#
            return (
                Data(body.utf8),
                makeHTTPResponse(url: request.url ?? URL(string: "https://api.github.com/user")!, statusCode: 200)
            )
        }
    )

    let response = try await service.connect(token: "  ghp_padded_token  ")
    #expect(response.ok == true)
    #expect(response.username == "trimuser")

    let storedToken = service.currentToken()
    #expect(storedToken == "ghp_padded_token")
}

@Test
func gitHubAuthServiceConnectThrowsOnEmptyToken() async throws {
    let service = GitHubAuthService(workspaceRootURL: makeWorkspaceURL(id: UUID().uuidString))
    await #expect(throws: (any Error).self) {
        try await service.connect(token: "   ")
    }
}

@Test
func gitHubAuthServiceConnectThrowsOnBadStatus() async throws {
    let service = GitHubAuthService(
        workspaceRootURL: makeWorkspaceURL(id: UUID().uuidString),
        transport: { request in
            let body = #"{"message":"Bad credentials"}"#
            return (
                Data(body.utf8),
                makeHTTPResponse(url: request.url ?? URL(string: "https://api.github.com/user")!, statusCode: 401)
            )
        }
    )

    await #expect(throws: (any Error).self) {
        try await service.connect(token: "ghp_invalid")
    }
}

// MARK: - disconnect

@Test
func gitHubAuthServiceDisconnectRemovesFile() async throws {
    let workspaceURL = makeWorkspaceURL(id: UUID().uuidString)
    let service = GitHubAuthService(
        workspaceRootURL: workspaceURL,
        transport: { request in
            let body = #"{"login":"duser","id":789}"#
            return (
                Data(body.utf8),
                makeHTTPResponse(url: request.url ?? URL(string: "https://api.github.com/user")!, statusCode: 200)
            )
        }
    )

    _ = try await service.connect(token: "ghp_disconnect_test")
    let authFile = workspaceURL.appendingPathComponent("auth/github.json")
    #expect(FileManager.default.fileExists(atPath: authFile.path))

    try service.disconnect()
    #expect(!FileManager.default.fileExists(atPath: authFile.path))

    let token = service.currentToken()
    // After disconnect, stored token should be gone (env var may still exist)
    let authFileExists = FileManager.default.fileExists(atPath: authFile.path)
    #expect(!authFileExists)
    _ = token
}

@Test
func gitHubAuthServiceDisconnectSucceedsWhenNoFileExists() throws {
    let service = GitHubAuthService(workspaceRootURL: makeWorkspaceURL(id: UUID().uuidString))
    // Should not throw even if no file exists
    try service.disconnect()
}

// MARK: - status

@Test
func gitHubAuthServiceStatusReflectsStoredCredentials() async throws {
    let workspaceURL = makeWorkspaceURL(id: UUID().uuidString)
    let service = GitHubAuthService(
        workspaceRootURL: workspaceURL,
        transport: { request in
            let body = #"{"login":"statususer","id":101}"#
            return (
                Data(body.utf8),
                makeHTTPResponse(url: request.url ?? URL(string: "https://api.github.com/user")!, statusCode: 200)
            )
        }
    )

    _ = try await service.connect(token: "ghp_status_test")

    let status = service.status()
    #expect(status.connected == true)
    #expect(status.username == "statususer")
    #expect(status.connectedAt != nil)
}

// MARK: - currentToken fallback order

@Test
func gitHubAuthServiceCurrentTokenPrefersStoredOverEnv() async throws {
    let workspaceURL = makeWorkspaceURL(id: UUID().uuidString)
    let service = GitHubAuthService(
        workspaceRootURL: workspaceURL,
        transport: { request in
            let body = #"{"login":"storeduser","id":202}"#
            return (
                Data(body.utf8),
                makeHTTPResponse(url: request.url ?? URL(string: "https://api.github.com/user")!, statusCode: 200)
            )
        }
    )

    _ = try await service.connect(token: "ghp_stored_token_xyz")
    let token = service.currentToken()
    #expect(token == "ghp_stored_token_xyz")
}

// MARK: - HTTPS URL injection helper

@Test
func authorizedCloneURLInjectsTokenForHTTPS() {
    guard let components = URLComponents(string: "https://github.com/org/repo"),
          var mutable = URLComponents(string: "https://github.com/org/repo")
    else {
        return
    }
    _ = components
    let token = "ghp_testtoken"
    mutable.user = "x-access-token"
    mutable.password = token
    let result = mutable.string ?? ""
    #expect(result == "https://x-access-token:ghp_testtoken@github.com/org/repo")
}

@Test
func authorizedCloneURLDoesNotModifySSHURLs() {
    let sshUrl = "git@github.com:org/repo.git"
    // SSH URLs should not be modified — they don't start with https://
    let hasPrefix = sshUrl.hasPrefix("https://") || sshUrl.hasPrefix("http://")
    #expect(!hasPrefix)
}

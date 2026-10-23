import Foundation
import Testing
@testable import sloppy
@testable import Protocols

@Test
func cliLocalAuthStorePersistsSessionForMatchingBaseURL() throws {
    let rootURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("sloppy-cli-auth-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: rootURL) }

    let session = SloppyCLILocalAuthSession(
        baseURL: "http://127.0.0.1:25101",
        accessToken: "access-token",
        refreshToken: "refresh-token",
        accessTokenExpiresAt: Date(timeIntervalSince1970: 1_000),
        refreshTokenExpiresAt: Date(timeIntervalSince1970: 2_000),
        user: AuthUserProfile(
            id: "user-1",
            login: "admin",
            name: "Admin",
            role: .admin
        )
    )

    try SloppyCLILocalAuthStore.save(session, rootURL: rootURL)

    let loaded = SloppyCLILocalAuthStore.load(baseURL: "http://127.0.0.1:25101/", rootURL: rootURL)
    #expect(loaded == session)
    #expect(SloppyCLILocalAuthStore.load(baseURL: "http://127.0.0.1:25102", rootURL: rootURL) == nil)

    try SloppyCLILocalAuthStore.clear(rootURL: rootURL)
    #expect(try SloppyCLILocalAuthStore.load(rootURL: rootURL) == nil)
}

@Test
func cliSessionTakesPrecedenceOverLegacyConfigButNotExplicitCredentials() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let session = SloppyCLILocalAuthSession(
        baseURL: "http://127.0.0.1:25101", accessToken: "signed-in-token", refreshToken: "refresh",
        accessTokenExpiresAt: .distantFuture, refreshTokenExpiresAt: .distantFuture,
        user: .init(id: "user", login: "user", name: "User", role: .admin))
    try SloppyCLILocalAuthStore.save(session, rootURL: root)
    try Data(#"{"auth":{"token":"legacy-token"}}"#.utf8).write(to: root.appendingPathComponent("sloppy.json"))
    let client = SloppyCLIClient.resolve(url: session.baseURL, token: nil, verbose: false,
        environment: [:], currentDirectoryURL: root, homeDirectoryURL: root)
    #expect(client.token == session.accessToken)
    #expect(client.localAuthSession == session)
    #expect(client.localOwnerCredential == nil)
    for override in ["explicit-token", ""] {
        let explicit = SloppyCLIClient.resolve(url: session.baseURL, token: override, verbose: false,
            environment: [:], currentDirectoryURL: root, homeDirectoryURL: root)
        #expect(explicit.token == override && explicit.localAuthSession == nil && explicit.localOwnerCredential == nil)
    }
    let environment = SloppyCLIClient.resolve(url: session.baseURL, token: nil, verbose: false,
        environment: ["SLOPPY_TOKEN": "env-token"], currentDirectoryURL: root, homeDirectoryURL: root)
    #expect(environment.token == "env-token" && environment.localAuthSession == nil)
    let otherServer = SloppyCLIClient.resolve(url: "http://127.0.0.1:25102", token: nil, verbose: false,
        environment: [:], currentDirectoryURL: root, homeDirectoryURL: root)
    #expect(otherServer.token == "legacy-token" && otherServer.localAuthSession == nil)
}

#if !os(Windows)
@Test
func cliOwnerCredentialRequiresPrivateFileAndMatchingLoopbackEndpoint() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("local-client.json")
    let baseURL = try #require(URL(string: "http://127.0.0.1:25101"))
    let credential = CoreLocalClientCredential(baseURL: baseURL, token: "slp_local_" + String(repeating: "x", count: 40))
    try JSONEncoder().encode(credential).write(to: file)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    #expect(SloppyCLILocalOwnerAuth.load(file, for: baseURL) != nil)
    for address in ["http://example.com:25101", "http://127.0.0.1:25102", "http://127.0.0.1:25101/proxy",
                    "http://user@127.0.0.1:25101", "http://127.0.0.1:25101?proxy=1", "https://127.0.0.1:25101"] {
        #expect(SloppyCLILocalOwnerAuth.load(file, for: try #require(URL(string: address))) == nil)
    }
    let link = root.appendingPathComponent("link.json")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
    #expect(SloppyCLILocalOwnerAuth.load(link, for: baseURL) == nil)
    try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
    #expect(SloppyCLILocalOwnerAuth.load(file, for: baseURL) == nil)
}
#endif

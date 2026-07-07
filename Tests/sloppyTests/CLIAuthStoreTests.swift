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

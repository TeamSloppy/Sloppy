import Foundation
import Testing

@Suite("Auth API client source")
struct AuthAPIClientSourceTests {
    private func source(named name: String) throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fileURL = packageRoot
            .appendingPathComponent("Sources")
            .appendingPathComponent("SloppyClientCore")
            .appendingPathComponent(name)
        return try String(contentsOf: fileURL, encoding: .utf8)
    }

    @Test("client exposes login/password auth challenge and login helpers")
    func clientExposesIdentityAuthHelpers() throws {
        let apiClient = try source(named: "SloppyAPIClient.swift")
        let services = try source(named: "BackendServices.swift")

        #expect(apiClient.contains("fetchAuthChallenge() async throws -> AuthChallenge"))
        #expect(apiClient.contains("loginIdentityUser(login: String, password: String) async throws -> AuthSession"))
        #expect(services.contains("public struct AuthChallenge"))
        #expect(services.contains("public struct AuthSession"))
        #expect(services.contains("\"/v1/auth/challenge\""))
        #expect(services.contains("\"/v1/auth/login\""))
    }
}

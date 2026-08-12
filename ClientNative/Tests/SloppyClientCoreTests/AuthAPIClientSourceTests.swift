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
        #expect(apiClient.contains("hasStoredAuthSession() async -> Bool"))
        #expect(apiClient.contains("public func logout() async"))
        #expect(services.contains("public struct AuthChallenge"))
        #expect(services.contains("public struct AuthSession"))
        #expect(services.contains("\"/v1/auth/challenge\""))
        #expect(services.contains("\"/v1/auth/login\""))
    }

    @Test("root app exposes logout and reacts to invalidated authentication")
    func rootAppWiresAuthenticationRecovery() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let app = try String(
            contentsOf: packageRoot.appendingPathComponent("Sources/SloppyClient/App/SloppyClientApp.swift"),
            encoding: .utf8
        )
        let root = try String(
            contentsOf: packageRoot.appendingPathComponent("Sources/SloppyClient/Root/RootShellViewModel.swift"),
            encoding: .utf8
        )

        #expect(app.contains("Button(\"Log Out\")"))
        #expect(app.contains("AuthenticationCommands(viewModel: viewModel)"))
        #expect(root.contains("observeAuthenticationRequirements() async"))
        #expect(root.contains("AuthSessionNotifications.authenticationRequired"))
        #expect(root.contains("func logout()"))
    }
}

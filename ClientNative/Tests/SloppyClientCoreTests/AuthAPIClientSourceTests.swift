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
        #expect(apiClient.contains("bootstrapIdentityAdmin(login: String, password: String, name: String) async throws -> AuthSession"))
        #expect(apiClient.contains("registerIdentityUser("))
        #expect(apiClient.contains("updateCurrentAuthUser("))
        #expect(apiClient.contains("changeIdentityPassword(currentPassword: String, newPassword: String) async throws -> AuthSession"))
        #expect(apiClient.contains("generateIdentityRecoveryCodes() async throws -> AuthRecoveryCodes"))
        #expect(apiClient.contains("fetchIdentityApplicationTokens() async throws -> [AuthApplicationToken]"))
        #expect(apiClient.contains("redeemDevicePairing(token: String) async throws -> AuthSession"))
        #expect(apiClient.contains("hasStoredAuthSession() async -> Bool"))
        #expect(apiClient.contains("public func logout() async"))
        #expect(services.contains("public struct AuthChallenge"))
        #expect(services.contains("public struct AuthSession"))
        #expect(services.contains("\"/v1/auth/challenge\""))
        #expect(services.contains("\"/v1/auth/login\""))
        #expect(services.contains("\"/v1/auth/bootstrap\""))
        #expect(services.contains("\"/v1/auth/register\""))
        #expect(services.contains("\"/v1/auth/password\""))
        #expect(services.contains("\"/v1/auth/recovery-codes\""))
        #expect(services.contains("\"/v1/auth/application-tokens\""))
        #expect(services.contains("\"/v1/auth/device-pairing/redeem\""))
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

import Foundation
import Protocols
import Testing
@testable import sloppy

@Suite("Identity session revocation")
struct IdentitySessionRevocationTests {
    @Test("password reset revokes every old session, including after restart", arguments: [false, true])
    func passwordResetRevokesSessions(useRecoveryCode: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("auth-reset-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let stateURL = root.appendingPathComponent("auth.json")
        let auth = CoreIdentityAuthService(passwordHashIterations: 1, stateURL: stateURL)
        await auth.setEnabled(true)
        let first = try await auth.bootstrapAdmin(.init(login: "owner", password: "before", name: "Owner"))
        let second = try await auth.login(.init(login: "owner", password: "before"))
        let actor = AuthenticatedUserContext(user: first.user)
        let request: AuthPasswordResetRequest
        if useRecoveryCode {
            let codes = try await auth.generateRecoveryCodes(actor: actor)
            request = .init(login: "owner", recoveryCode: try #require(codes.codes.first), newPassword: "after")
        } else {
            let reset = try await auth.createPasswordResetToken(login: "owner", actor: actor)
            request = .init(login: "owner", resetToken: reset.resetToken, newPassword: "after")
        }
        let replacement = try await auth.resetPassword(request)
        for previous in [first, second] {
            #expect(await auth.authenticateAccessToken(previous.accessToken) == nil)
            await #expect(throws: CoreIdentityAuthError.invalidCredentials) {
                try await auth.refresh(.init(refreshToken: previous.refreshToken))
            }
        }
        #expect(await auth.authenticateAccessToken(replacement.accessToken) != nil)
        _ = try await auth.login(.init(login: "owner", password: "after"))
        let restarted = CoreIdentityAuthService(passwordHashIterations: 1, stateURL: stateURL)
        for previous in [first, second] {
            await #expect(throws: CoreIdentityAuthError.invalidCredentials) {
                try await restarted.refresh(.init(refreshToken: previous.refreshToken))
            }
        }
        _ = try await restarted.refresh(.init(refreshToken: replacement.refreshToken))
    }
}

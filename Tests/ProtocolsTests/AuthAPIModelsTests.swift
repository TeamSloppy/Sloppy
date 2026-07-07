import Foundation
import Testing
@testable import Protocols

@Test
func authChallengeAndSessionModelsRoundTrip() throws {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    let challenge = AuthChallengeResponse(
        mode: .loginPassword,
        bootstrapRequired: true,
        passkeySupported: true,
        accessTokenExpiresInSeconds: 900,
        refreshTokenExpiresInSeconds: 604_800
    )

    let challengeData = try encoder.encode(challenge)
    let decodedChallenge = try decoder.decode(AuthChallengeResponse.self, from: challengeData)

    #expect(decodedChallenge.mode == .loginPassword)
    #expect(decodedChallenge.bootstrapRequired == true)
    #expect(decodedChallenge.passkeySupported == true)
    #expect(decodedChallenge.refreshTokenExpiresInSeconds == 604_800)

    let now = Date(timeIntervalSince1970: 100)
    let session = AuthSessionResponse(
        accessToken: "access-token",
        refreshToken: "refresh-token",
        accessTokenExpiresAt: now.addingTimeInterval(900),
        refreshTokenExpiresAt: now.addingTimeInterval(604_800),
        user: AuthUserProfile(
            id: "user_admin",
            login: "admin",
            name: "Admin",
            avatar: "",
            description: "First account",
            role: .admin,
            status: .active
        )
    )

    let sessionData = try encoder.encode(session)
    let decodedSession = try decoder.decode(AuthSessionResponse.self, from: sessionData)

    #expect(decodedSession.accessToken == "access-token")
    #expect(decodedSession.refreshToken == "refresh-token")
    #expect(decodedSession.user.role == .admin)
    #expect(decodedSession.user.status == .active)
}

@Test
func authRecoveryModelsKeepCodesExplicit() throws {
    let response = AuthRecoveryCodesResponse(codes: ["sloppy-a", "sloppy-b"])
    let data = try JSONEncoder().encode(response)
    let decoded = try JSONDecoder().decode(AuthRecoveryCodesResponse.self, from: data)

    #expect(decoded.codes == ["sloppy-a", "sloppy-b"])
}

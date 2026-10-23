import Foundation
import Protocols
import SloppyNodeCore
import SloppyNodeCore
import Testing
import Logging
@testable import sloppy

@Suite("Local owner auth")
struct LocalOwnerAuthTests {
    #if !os(Windows)
    @Test("CLI recovers a legacy-token 401 through the local owner exchange")
    func cliLocalOwnerRecovery() async throws {
        try await withFixture { service, router, _, fileURL in
            let server = CoreHTTPServer(host: "127.0.0.1", port: 0, router: router,
                                       logger: .sloppy(label: "sloppy.cli.auth.tests"))
            try server.start()
            defer { try? server.shutdown() }
            let port = try #require(server.boundPort)
            try await service.publishLocalClientCredential(port: port, fileURL: fileURL)
            let root = fileURL.deletingLastPathComponent()
            let client = SloppyCLIClient.resolve(url: "http://127.0.0.1:\(port)", token: nil, verbose: false,
                environment: [:], currentDirectoryURL: root, homeDirectoryURL: root)
            #expect(client.localOwnerCredential != nil)
            let data = try await client.get("/v1/projects")
            #expect((try JSONSerialization.jsonObject(with: data)) is [Any])
            #expect(!FileManager.default.fileExists(atPath: SloppyCLILocalAuthStore.authURL(rootURL: root).path))

            let explicit = SloppyCLIClient.resolve(url: client.baseURL, token: "wrong-token", verbose: false,
                environment: [:], currentDirectoryURL: root, homeDirectoryURL: root)
            #expect(explicit.localOwnerCredential == nil)
            do {
                _ = try await explicit.get("/v1/projects")
                Issue.record("Explicit invalid credentials must not gain owner access")
            } catch CLIClientError.httpError(let code, _) {
                #expect(code == 401)
            }
        }
    }
    #endif

    @Test("A private filesystem credential opens an ordinary owner session")
    func localExchangeAndRotation() async throws {
        try await withFixture { service, router, owner, fileURL in
            let credential = try JSONDecoder().decode(CoreLocalClientCredential.self, from: Data(contentsOf: fileURL))
            #if !os(Windows)
            let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
            #endif
            #expect(credential.baseURL.port == 25101)
            let response = await router.handle(method: "POST", path: "/v1/auth/local-session", body: nil,
                headers: ["authorization": "Bearer " + credential.token], remoteAddress: "127.0.0.1")
            #expect(response.status == 200)
            #expect(response.headers["cache-control"] == "no-store")
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let session = try decoder.decode(AuthSessionResponse.self, from: response.body)
            #expect(session.user.id == owner.user.id)
            #expect(session.user.role == .admin)
            let projects = await router.handle(method: "GET", path: "/v1/projects", body: nil,
                headers: ["authorization": "Bearer " + session.accessToken], remoteAddress: "127.0.0.1")
            #expect(projects.status == 200)
            try await service.publishLocalClientCredential(port: 25101, fileURL: fileURL)
            let stale = await router.handle(method: "POST", path: "/v1/auth/local-session", body: nil,
                headers: ["authorization": "Bearer " + credential.token], remoteAddress: "127.0.0.1")
            #expect(stale.status == 401)
        }
    }

    @Test("Remote and browser/proxy requests cannot exchange a local secret")
    func rejectsUntrustedTransports() async throws {
        try await withFixture { _, router, _, fileURL in
            let credential = try JSONDecoder().decode(CoreLocalClientCredential.self, from: Data(contentsOf: fileURL))
            for address: String? in [nil, "192.168.3.4", "localhost", "8.8.8.8"] {
                let response = await router.handle(method: "POST", path: "/v1/auth/local-session", body: nil,
                    headers: ["authorization": "Bearer " + credential.token, "x-forwarded-for": "127.0.0.1"], remoteAddress: address)
                #expect(response.status == 403)
            }
            for header in ["origin", "forwarded", "x-forwarded-for"] {
                let response = await router.handle(method: "POST", path: "/v1/auth/local-session", body: nil,
                    headers: ["authorization": "Bearer " + credential.token, header: "untrusted"], remoteAddress: "::1")
                #expect(response.status == 403)
            }
            for token in ["", "legacy-token", "wrong-secret"] {
                let response = await router.handle(method: "POST", path: "/v1/auth/local-session", body: nil,
                    headers: ["authorization": "Bearer " + token], remoteAddress: "127.0.0.1")
                #expect(response.status == 401)
            }
        }
    }

    @Test("Disabling the owner does not silently switch to another admin")
    func disabledOwnerCannotReconnect() async throws {
        try await withFixture { service, router, owner, fileURL in
            let actor = AuthenticatedUserContext(user: owner.user)
            let invite = try await service.createIdentityInvite(.init(role: .admin, ttlSeconds: 600), actor: actor)
            _ = try await service.registerIdentityUser(.init(inviteToken: try #require(invite.token), login: "other", password: "other-password", name: "Other"))
            _ = try await service.updateIdentityUser(login: owner.user.login, request: .init(status: .disabled), actor: actor)
            let credential = try JSONDecoder().decode(CoreLocalClientCredential.self, from: Data(contentsOf: fileURL))
            let response = await router.handle(method: "POST", path: "/v1/auth/local-session", body: nil,
                headers: ["authorization": "Bearer " + credential.token], remoteAddress: "127.0.0.1")
            #expect(response.status == 403)
        }
    }

    @Test("Old state resolves only an unambiguous owner", arguments: [false, true])
    func legacyOwnerResolution(hasSecondAdmin: Bool) async throws {
        try await withFixture { service, _, owner, _ in
            if hasSecondAdmin {
                let invite = try await service.createIdentityInvite(.init(role: .admin, ttlSeconds: 600),
                    actor: AuthenticatedUserContext(user: owner.user))
                _ = try await service.registerIdentityUser(.init(inviteToken: try #require(invite.token),
                    login: "second", password: "second-password", name: "Second"))
            }
            let stateURL = await service.workspaceRootURL.appendingPathComponent(".sloppy/auth-state.json")
            var state = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: stateURL)) as? [String: Any])
            state.removeValue(forKey: "localOwnerUserID")
            try JSONSerialization.data(withJSONObject: state).write(to: stateURL, options: .atomic)
            let reloaded = CoreIdentityAuthService(passwordHashIterations: 1, stateURL: stateURL)
            if hasSecondAdmin {
                await #expect(throws: CoreIdentityAuthError.self) { try await reloaded.makeLocalOwnerSession() }
            } else {
                let session = try await reloaded.makeLocalOwnerSession()
                #expect(session.user.id == owner.user.id)
            }
        }
    }

    private func withFixture(
        _ body: (CoreService, CoreRouter, AuthSessionResponse, URL) async throws -> Void
    ) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let service = CoreService(config: .test, currentDirectory: root.path,
            persistenceBuilder: InMemoryCorePersistenceBuilder(),
            nodeConfigStore: NodeConfigStore(configURL: root.appendingPathComponent("node.json")),
            sharedSkillsRootURLs: [], identityPasswordHashIterations: 1)
        await service.setIdentityAuthEnabled(true)
        let owner = try await service.bootstrapIdentityAdmin(.init(login: "owner", password: "test-password", name: "Owner"))
        let fileURL = root.appendingPathComponent("local-client.json")
        try await service.publishLocalClientCredential(port: 25101, fileURL: fileURL)
        try await body(service, CoreRouter(service: service), owner, fileURL)
    }
}

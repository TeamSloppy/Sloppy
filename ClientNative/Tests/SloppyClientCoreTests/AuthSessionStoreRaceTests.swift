import Foundation
import Testing
@testable import SloppyClientCore

@Suite("Authentication recovery races")
struct AuthSessionStoreRaceTests {
    @Test("an old refresh cannot replace or delete a new login", arguments: [false, true])
    func newLoginSupersedesRefresh(refreshSucceeds: Bool) async throws {
        let store = AuthSessionStore(persistence: .memory)
        let url = try #require(URL(string: "https://auth-race.invalid"))
        await store.save(.init(accessToken: "old", refreshToken: "old-refresh"), for: url)
        let gate = AuthRefreshGate()
        let recovery = Task { await store.recoverSession(for: url, rejectedAccessToken: "old") { _ in await gate.wait() } }
        await gate.waitUntilStarted()
        let replacement = AuthSession(accessToken: "new-login", refreshToken: "new-refresh")
        await store.save(replacement, for: url)
        await gate.release(refreshSucceeds ? .init(accessToken: "stale", refreshToken: "stale-refresh") : nil)
        #expect(await recovery.value == .superseded)
        #expect(await store.session(for: url) == replacement)
    }

    @Test("logging out cannot be undone by a completed refresh")
    func logoutSupersedesRefresh() async throws {
        let store = AuthSessionStore(persistence: .memory)
        let url = try #require(URL(string: "https://logout-race.invalid"))
        await store.save(.init(accessToken: "old", refreshToken: "refresh"), for: url)
        let gate = AuthRefreshGate()
        let recovery = Task { await store.recoverSession(for: url, rejectedAccessToken: "old") { _ in await gate.wait() } }
        await gate.waitUntilStarted()
        await store.clear(for: url)
        await gate.release(.init(accessToken: "stale", refreshToken: "rotated"))
        #expect(await recovery.value == .superseded)
        #expect(await store.session(for: url) == nil)
    }

    @Test("finishing an old refresh leaves the new login's refresh in place")
    func oldRecoveryCannotRemoveNewRecovery() async throws {
        let store = AuthSessionStore(persistence: .memory)
        let url = try #require(URL(string: "https://new-recovery.invalid"))
        await store.save(.init(accessToken: "old", refreshToken: "old-refresh"), for: url)
        let oldGate = AuthRefreshGate()
        let old = Task { await store.recoverSession(for: url, rejectedAccessToken: "old") { _ in await oldGate.wait() } }
        await oldGate.waitUntilStarted()
        await store.save(.init(accessToken: "new", refreshToken: "new-refresh"), for: url)
        let newGate = AuthRefreshGate()
        let current = Task { await store.recoverSession(for: url, rejectedAccessToken: "new") { _ in await newGate.wait() } }
        await newGate.waitUntilStarted()
        await oldGate.release(nil)
        #expect(await old.value == .superseded)
        let refreshed = AuthSession(accessToken: "fresh-new", refreshToken: "rotated-new")
        await newGate.release(refreshed)
        #expect(await current.value == .recovered(refreshed))
        #expect(await store.session(for: url) == refreshed)
    }
}

private actor AuthRefreshGate {
    private var continuation: CheckedContinuation<AuthSession?, Never>?
    private var started: CheckedContinuation<Void, Never>?
    private var hasStarted = false

    func wait() async -> AuthSession? {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            hasStarted = true
            started?.resume()
            started = nil
        }
    }

    func waitUntilStarted() async {
        if !hasStarted { await withCheckedContinuation { started = $0 } }
    }

    func release(_ session: AuthSession?) {
        continuation?.resume(returning: session)
        continuation = nil
    }
}

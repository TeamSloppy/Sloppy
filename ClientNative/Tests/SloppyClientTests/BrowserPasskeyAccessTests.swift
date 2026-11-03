#if os(macOS)
import Testing
@testable import SloppyClient

@Suite("Browser passkey access")
@MainActor
struct BrowserPasskeyAccessTests {
    @Test func unentitledBuildNeverRequestsSystemAccess() async {
        var reads = 0
        var requests = 0
        let access = BrowserPasskeyAccess(hasEntitlement: { false }, readAuthorization: {
            reads += 1
            return .notDetermined
        }, requestAuthorization: {
            requests += 1
            return .authorized
        })
        access.refresh()
        await access.requestAccess()
        #expect(access.authorization == .unavailable)
        #expect(reads == 0)
        #expect(requests == 0)
    }

    @Test func requestsConsentOnceAndRefreshesExternalChanges() async {
        var systemState: BrowserPasskeyAuthorization = .notDetermined
        var requests = 0
        let access = BrowserPasskeyAccess(hasEntitlement: { true }, readAuthorization: { systemState }, requestAuthorization: {
            requests += 1
            systemState = .authorized
            return systemState
        })
        access.refresh()
        #expect(access.authorization == .notDetermined)
        await access.requestAccess()
        await access.requestAccess()
        #expect(access.authorization == .authorized)
        #expect(requests == 1)
        systemState = .denied
        access.refresh()
        await access.requestAccess()
        #expect(access.authorization == .denied)
        #expect(requests == 1)
        #expect(!access.isRequesting)
    }

    @Test func concurrentRequestsShareThePendingConsent() async {
        var requests = 0
        var completion: CheckedContinuation<BrowserPasskeyAuthorization, Never>?
        let access = BrowserPasskeyAccess(hasEntitlement: { true }, readAuthorization: { .notDetermined }, requestAuthorization: {
            requests += 1
            return await withCheckedContinuation { completion = $0 }
        })
        let first = Task { await access.requestAccess() }
        while !access.isRequesting { await Task.yield() }
        await access.requestAccess()
        completion?.resume(returning: .denied)
        await first.value
        #expect(requests == 1)
        #expect(access.authorization == .denied)
        #expect(!access.isRequesting)
    }
}
#endif

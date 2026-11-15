import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Protocols
import Testing
@testable import sloppy

struct KimiOAuthServiceTests {
    private final class Recorder: @unchecked Sendable {
        var requests: [URLRequest] = []
    }

    private func makeService(
        responses: [(Int, String)],
        recorder: Recorder = Recorder(),
        now: @escaping @Sendable () -> Date = Date.init
    ) -> (KimiOAuthService, URL, Recorder) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("kimi-oauth-\(UUID().uuidString)")
        let queue = ResponseQueue(responses)
        let service = KimiOAuthService(workspaceRootURL: root, transport: { request in
            recorder.requests.append(request)
            let (status, body) = queue.next()
            let http = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (Data(body.utf8), http)
        }, now: now)
        return (service, root, recorder)
    }

    private final class ResponseQueue: @unchecked Sendable {
        var items: [(Int, String)]
        init(_ items: [(Int, String)]) { self.items = items }
        func next() -> (Int, String) { items.isEmpty ? (500, "{}") : items.removeFirst() }
    }

    @Test
    func deviceFlowStoresTokenAfterApproval() async throws {
        let (service, root, recorder) = makeService(responses: [
            (200, #"{"device_code":"dc","user_code":"ABCD-1234","verification_uri_complete":"https://www.kimi.com/code/authorize_device?user_code=ABCD-1234","expires_in":600,"interval":5}"#),
            (400, #"{"error":"authorization_pending"}"#),
            (200, #"{"access_token":"at","refresh_token":"rt","expires_in":900}"#),
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        let start = try await service.startDeviceCode()
        #expect(start.userCode == "ABCD-1234")
        #expect(start.deviceCode == "dc")

        let pending = try await service.pollDeviceToken(deviceCode: "dc")
        #expect(pending.status == "pending")
        #expect(service.currentAccessToken() == nil)

        let done = try await service.pollDeviceToken(deviceCode: "dc")
        #expect(done.ok)
        #expect(service.currentAccessToken() == "at")
        #expect(service.status().refreshable)
        let body = String(data: recorder.requests[2].httpBody ?? Data(), encoding: .utf8) ?? ""
        #expect(body.contains("grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Adevice_code"))
    }

    @Test
    func expiringTokenIsRefreshedAndDisconnectClearsIt() async throws {
        let clock = Date(timeIntervalSince1970: 1_000_000)
        let (service, root, _) = makeService(responses: [
            (200, #"{"access_token":"old","refresh_token":"rt","expires_in":30}"#),
            (200, #"{"access_token":"new","expires_in":900}"#),
        ], now: { clock })
        defer { try? FileManager.default.removeItem(at: root) }

        _ = try await service.pollDeviceToken(deviceCode: "dc")
        try await service.ensureValidToken()
        #expect(service.currentAccessToken() == "new")
        #expect(service.status().refreshable) // refresh token is kept when the server omits it

        try service.disconnect()
        #expect(service.currentAccessToken() == nil)
    }
}

import Foundation
import Testing
@testable import SloppyClientCore

@Suite("Console HTTP/2 fallback")
struct ConsoleHTTPTransportTests {
    @Test func fallbackKeepsConsoleAuthorityAndTLSValidation() {
        let configuration = ConsoleHTTP2Transport.makeConfiguration()
        #expect(configuration.dnsOverride.isEmpty)
        #expect(configuration.tlsConfiguration?.minimumTLSVersion == .tlsv12)
        #expect(configuration.tlsConfiguration?.certificateVerification == .fullVerification)
    }

    @Test func relayGatewayUsesTheReachableConsoleEdge() {
        #expect(ConsoleAccountClient.relayGatewayURL.absoluteString == "https://console.sloppy.team/relay")
    }

    @Test("Live Console HTTP/2 smoke", .enabled(if: ProcessInfo.processInfo.environment["SLOPPY_LIVE_CONSOLE_HTTP2"] == "1"))
    func liveConsoleHTTP2Smoke() async throws {
        let client = ConsoleHTTPTransport(primary: { _ in throw URLError(.timedOut) })
        var request = URLRequest(url: URL(string: "https://console.sloppy.team/readyz")!)
        request.timeoutInterval = 10
        let response = try await client.send(request)
        #expect(response.1.statusCode == 200)
        #expect(!response.0.isEmpty)
    }

    private func request(method: String = "GET") -> URLRequest {
        var request = URLRequest(url: URL(string: "https://console.sloppy.team/v1/me")!)
        request.httpMethod = method
        request.timeoutInterval = 20
        request.setValue("Bearer test-token", forHTTPHeaderField: "Authorization")
        return request
    }

    @Test func networkFailureFallsBackAndSubsequentRequestsStayOnTCP() async throws {
        let primary = ConsoleTransportRecorder(error: .timedOut)
        let tcp = ConsoleTransportRecorder()
        let client = ConsoleHTTPTransport(primary: { try await primary.send($0) }, http2: { try await tcp.send($0) })
        let first = try await client.send(request())
        let second = try await client.send(request())
        #expect(first.1.statusCode == 200 && second.1.statusCode == 200)
        let probes = await primary.requests
        let fallbacks = await tcp.requests
        #expect(probes.count == 1)
        #expect(probes.first?.timeoutInterval == 2)
        #expect(fallbacks.count == 2)
        #expect(fallbacks.first?.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
        #expect((fallbacks.first?.timeoutInterval ?? 0) <= 20)
    }

    @Test func postUsesTCPOnceAndPreservesItsBody() async throws {
        let primary = ConsoleTransportRecorder()
        let tcp = ConsoleTransportRecorder(error: .networkConnectionLost)
        let client = ConsoleHTTPTransport(primary: { try await primary.send($0) }, http2: { try await tcp.send($0) })
        var request = request(method: "POST")
        request.httpBody = Data("{\"code\":\"one-time-code\"}".utf8)
        await #expect(throws: URLError.self) { try await client.send(request) }
        #expect(await primary.requests.isEmpty)
        let sent = await tcp.requests
        #expect(sent.count == 1)
        #expect(sent.first?.httpBody == request.httpBody)
        #expect(sent.first?.httpMethod == "POST")
    }

    @Test(arguments: [URLError.Code.cancelled, .serverCertificateUntrusted, .userAuthenticationRequired])
    func securityAndCancellationErrorsDoNotTriggerRetry(_ code: URLError.Code) async throws {
        let primary = ConsoleTransportRecorder(error: code)
        let tcp = ConsoleTransportRecorder()
        let client = ConsoleHTTPTransport(primary: { try await primary.send($0) }, http2: { try await tcp.send($0) })
        await #expect(throws: URLError.self) { try await client.send(request()) }
        #expect(await tcp.requests.isEmpty)
    }

    @Test(arguments: [302, 401, 403, 503])
    func httpResponsesAreReturnedWithoutReplay(_ status: Int) async throws {
        let primary = ConsoleTransportRecorder(status: status)
        let tcp = ConsoleTransportRecorder()
        let client = ConsoleHTTPTransport(primary: { try await primary.send($0) }, http2: { try await tcp.send($0) })
        let result = try await client.send(request())
        #expect(result.1.statusCode == status)
        #expect(await tcp.requests.isEmpty)
    }

    @Test func exhaustedRequestBudgetDoesNotStartAnotherAttempt() async throws {
        let tcp = ConsoleTransportRecorder()
        let client = ConsoleHTTPTransport(primary: { _ in
            try await Task.sleep(for: .milliseconds(20))
            throw URLError(.timedOut)
        }, http2: { try await tcp.send($0) })
        var request = request()
        request.timeoutInterval = 0.001
        await #expect(throws: URLError.self) { try await client.send(request) }
        #expect(await tcp.requests.isEmpty)
    }
}

private actor ConsoleTransportRecorder {
    private(set) var requests: [URLRequest] = []
    let error: URLError.Code?
    let status: Int

    init(error: URLError.Code? = nil, status: Int = 200) {
        self.error = error
        self.status = status
    }

    func send(_ request: URLRequest) throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        if let error { throw URLError(error) }
        return (Data("{}".utf8), HTTPURLResponse(url: request.url!, statusCode: status,
            httpVersion: "HTTP/2.0", headerFields: nil)!)
    }
}

import Testing
@testable import sloppy

struct CoreHTTPAccessPolicyTests {
    @Test
    func rejectsCrossSiteOriginWithoutCredentials() {
        let headers = ["origin": "https://evil.example", "host": "localhost:25101"]
        #expect(!CoreHTTPAccessPolicy.allows(uri: "/v1/config", headers: headers, remoteAddress: "127.0.0.1"))
        #expect(CoreHTTPAccessPolicy.corsOrigin(headers: headers) == nil)
    }

    @Test
    func allowsLoopbackAndSameHostOrigins() {
        let local = ["origin": "http://localhost:25102", "host": "localhost:25101"]
        #expect(CoreHTTPAccessPolicy.allows(uri: "/v1/config", headers: local, remoteAddress: "127.0.0.1"))
        #expect(CoreHTTPAccessPolicy.corsOrigin(headers: local) == "http://localhost:25102")

        let lan = ["origin": "http://192.168.1.10:25102", "host": "192.168.1.10:25101"]
        #expect(CoreHTTPAccessPolicy.allows(uri: "/v1/config", headers: lan, remoteAddress: "192.168.1.20"))
    }

    @Test
    func allowsCrossOriginRequestsThatCarryTheirOwnCredentials() {
        let headers = ["origin": "https://dashboard.example", "host": "core.example", "authorization": "Bearer t"]
        #expect(CoreHTTPAccessPolicy.allows(uri: "/v1/config", headers: headers, remoteAddress: "10.0.0.5"))
        let socket = ["origin": "https://dashboard.example", "host": "core.example"]
        #expect(CoreHTTPAccessPolicy.allows(uri: "/v1/ws?token=abc", headers: socket, remoteAddress: "10.0.0.5"))
    }

    @Test
    func blocksDNSRebindingButNotProxiesOrNativeClients() {
        let rebound = ["host": "attacker.example:25101"]
        #expect(!CoreHTTPAccessPolicy.allows(uri: "/v1/config", headers: rebound, remoteAddress: "127.0.0.1"))

        let proxied = ["host": "sloppy.example", "x-forwarded-for": "203.0.113.9"]
        #expect(CoreHTTPAccessPolicy.allows(uri: "/v1/config", headers: proxied, remoteAddress: "127.0.0.1"))

        let native = ["host": "192.168.1.10:25101"]
        #expect(CoreHTTPAccessPolicy.allows(uri: "/v1/config", headers: native, remoteAddress: "192.168.1.20"))
        #expect(CoreHTTPAccessPolicy.allows(uri: "/v1/config", headers: ["host": "127.0.0.1:25101"], remoteAddress: "127.0.0.1"))
    }
}

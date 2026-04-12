import Testing
@testable import sloppy

@Suite("WebFetchService host policy")
struct WebFetchServiceTests {
    @Test("blocks localhost and private IPv4 when enabled")
    func blocksPrivateWhenEnabled() {
        #expect(WebFetchService.policyBlocksHost(host: "localhost", blockPrivateNetworks: true))
        #expect(WebFetchService.policyBlocksHost(host: "127.0.0.1", blockPrivateNetworks: true))
        #expect(WebFetchService.policyBlocksHost(host: "10.0.0.1", blockPrivateNetworks: true))
        #expect(WebFetchService.policyBlocksHost(host: "192.168.1.1", blockPrivateNetworks: true))
        #expect(WebFetchService.policyBlocksHost(host: "172.20.0.1", blockPrivateNetworks: true))
    }

    @Test("allows public hosts when blocking enabled")
    func allowsPublicWhenBlocking() {
        #expect(!WebFetchService.policyBlocksHost(host: "example.com", blockPrivateNetworks: true))
        #expect(!WebFetchService.policyBlocksHost(host: "docs.sloppy.team", blockPrivateNetworks: true))
    }

    @Test("allows private hosts when blocking disabled")
    func allowsPrivateWhenDisabled() {
        #expect(!WebFetchService.policyBlocksHost(host: "127.0.0.1", blockPrivateNetworks: false))
    }

    @Test("blocks bracket IPv6 loopback")
    func blocksIPv6Loopback() {
        #expect(WebFetchService.policyBlocksHost(host: "[::1]", blockPrivateNetworks: true))
    }
}

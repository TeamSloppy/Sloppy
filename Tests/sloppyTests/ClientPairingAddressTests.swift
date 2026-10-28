import Foundation
import Testing
@testable import sloppy

@Suite struct ClientPairingAddressTests {
    private let candidates: [NetworkIPv4Candidate] = [
        .init(interfaceName: "lo0", address: "127.0.0.1"),
        .init(interfaceName: "bridge0", address: "192.168.64.1"),
        .init(interfaceName: "en0", address: "192.168.1.10")
    ]

    @Test func wildcardListenerAdvertisesLANInsteadOfDashboardLocalhost() {
        #expect(NetworkAddressResolver.clientPairingURL(bindHost: "0.0.0.0", apiPort: 25101, candidates: candidates) == "http://192.168.1.10:25101")
        #expect(NetworkAddressResolver.clientPairingURL(bindHost: "::", apiPort: 28001, candidates: candidates) == "http://192.168.1.10:28001")
    }

    @Test func explicitLANBindingWinsOverAnotherInterface() {
        #expect(NetworkAddressResolver.clientPairingURL(bindHost: "192.168.3.10", apiPort: 28001, candidates: candidates) == "http://192.168.3.10:28001")
    }

    @Test func localOnlyListenerCannotAdvertiseAnUnreachableLANAddress() {
        for host in ["localhost", "127.0.0.1", "127.0.0.2", "::1"] {
            #expect(NetworkAddressResolver.clientPairingURL(bindHost: host, apiPort: 25101, candidates: candidates) == nil)
        }
    }

    @Test func missingLANAndPublicOnlyInterfacesDoNotFallBackToLoopbackOrHTTPPublicIP() {
        #expect(NetworkAddressResolver.clientPairingURL(bindHost: "0.0.0.0", apiPort: 25101, candidates: []) == nil)
        #expect(NetworkAddressResolver.clientPairingURL(bindHost: "0.0.0.0", apiPort: 25101, candidates: [.init(interfaceName: "en0", address: "203.0.113.10")]) == nil)
    }

    @Test func loopbackAliasesAndWildcardsAreNotDeviceAddresses() {
        for host in ["localhost", "LOCALHOST.", "a.localhost", "127.0.0.1", "127.0.0.2", "[::1]", "::", "0.0.0.0"] {
            #expect(NetworkAddressResolver.isDeviceLocalHost(host))
        }
        #expect(!NetworkAddressResolver.isDeviceLocalHost("192.168.1.10"))
        #expect(!NetworkAddressResolver.isDeviceLocalHost("core.example.com"))
    }
}

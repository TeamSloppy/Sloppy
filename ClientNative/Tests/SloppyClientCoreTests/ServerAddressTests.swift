import Testing
@testable import SloppyClientCore

@Suite("ServerAddress")
struct ServerAddressTests {

    @Test("parses host with separate port")
    func parsesHostWithSeparatePort() {
        let address = ServerAddress.parse(host: "192.168.3.199", port: "25101")

        #expect(address?.host == "192.168.3.199")
        #expect(address?.port == 25101)
        #expect(address?.baseURL.absoluteString == "http://192.168.3.199:25101")
    }

    @Test("parses pasted host and port")
    func parsesPastedHostAndPort() {
        let address = ServerAddress.parse(host: "192.168.3.199:25101", port: "9999")

        #expect(address?.host == "192.168.3.199")
        #expect(address?.port == 25101)
        #expect(address?.baseURL.absoluteString == "http://192.168.3.199:25101")
    }

    @Test("parses pasted URL")
    func parsesPastedURL() {
        let address = ServerAddress.parse(host: "http://192.168.3.199:25101")

        #expect(address?.host == "192.168.3.199")
        #expect(address?.port == 25101)
        #expect(address?.baseURL.absoluteString == "http://192.168.3.199:25101")
    }

    @Test("rejects empty host")
    func rejectsEmptyHost() {
        #expect(ServerAddress.parse(host: "   ") == nil)
    }
}

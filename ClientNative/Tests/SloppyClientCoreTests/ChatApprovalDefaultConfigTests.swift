import Foundation
import Testing
@testable import SloppyClientCore

struct ChatApprovalDefaultConfigTests {
    @Test func configDefaultIsBackwardCompatibleAndRoundTrips() throws {
        var config = SloppyConfig()
        config.defaultChatApprovalMode = .approveForMe
        let encoded = try JSONEncoder().encode(config)
        #expect(try JSONDecoder().decode(SloppyConfig.self, from: encoded).defaultChatApprovalMode == .approveForMe)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["defaultChatApprovalMode"] = nil
        let legacy = try JSONSerialization.data(withJSONObject: object)
        #expect(try JSONDecoder().decode(SloppyConfig.self, from: legacy).defaultChatApprovalMode == nil)
    }
}

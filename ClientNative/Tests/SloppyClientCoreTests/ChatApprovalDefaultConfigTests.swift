import Foundation
import Testing
@testable import SloppyClientCore

struct ChatApprovalDefaultConfigTests {
    @Test(arguments: ChatApprovalMode.allCases)
    func configDefaultIsBackwardCompatibleAndRoundTrips(mode: ChatApprovalMode) throws {
        var config = SloppyConfig()
        config.defaultChatApprovalMode = mode
        let encoded = try JSONEncoder().encode(config)
        #expect(try JSONDecoder().decode(SloppyConfig.self, from: encoded).defaultChatApprovalMode == mode)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["defaultChatApprovalMode"] = nil
        let legacy = try JSONSerialization.data(withJSONObject: object)
        #expect(try JSONDecoder().decode(SloppyConfig.self, from: legacy).defaultChatApprovalMode == nil)
    }
}

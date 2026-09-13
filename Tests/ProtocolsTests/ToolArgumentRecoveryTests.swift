import Foundation
import Testing
@testable import Protocols

@Test
func toolErrorsDecodeLegacyPayloadsAndRoundTripRecoveryFields() throws {
    let old = Data(#"{"code":"invalid_arguments","message":"Invalid","retryable":false}"#.utf8)
    #expect(try JSONDecoder().decode(ToolErrorPayload.self, from: old).argumentRecovery == nil)
    let error = ToolErrorPayload(code: "memory_not_found", message: "Missing ID", retryable: false,
        hint: "Find an existing ID", argumentRecovery: .init(invalidFields: ["memory_id"], contextFields: ["scope"]))
    let encoded = try JSONEncoder().encode(error)
    #expect(try JSONDecoder().decode(ToolErrorPayload.self, from: encoded) == error)
}

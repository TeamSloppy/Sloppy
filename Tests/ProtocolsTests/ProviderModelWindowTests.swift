import Foundation
import Testing
@testable import Protocols

@Test func modelWindowRetainsExactTokensAndDecodesLegacyCatalogEntries() throws {
    let legacy = Data(#"{"id":"model","title":"Model","contextWindow":"1.0M","capabilities":[]}"#.utf8)
    #expect(try JSONDecoder().decode(ProviderModelOption.self, from: legacy).contextWindowTokens == nil)
    let exact = ProviderModelOption(id: "model", title: "Model", contextWindow: "1.0M", contextWindowTokens: 1_048_576)
    #expect(try JSONDecoder().decode(ProviderModelOption.self, from: JSONEncoder().encode(exact)) == exact)
}

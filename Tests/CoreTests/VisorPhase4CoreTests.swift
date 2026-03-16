import Foundation
import Testing
@testable import Core

@Test func visorConfigDecodesWebhookURLs() throws {
    let json = """
    {
      "scheduler": { "enabled": false, "intervalSeconds": 60, "jitterSeconds": 0 },
      "webhookURLs": ["https://example.com/hook1", "https://example.com/hook2"]
    }
    """
    let data = json.data(using: .utf8)!
    let decoder = JSONDecoder()
    let config = try decoder.decode(CoreConfig.Visor.self, from: data)
    #expect(config.webhookURLs == ["https://example.com/hook1", "https://example.com/hook2"])
}

@Test func visorConfigDefaultsWebhookURLsToEmpty() throws {
    let json = """
    { "scheduler": { "enabled": false, "intervalSeconds": 60, "jitterSeconds": 0 } }
    """
    let data = json.data(using: .utf8)!
    let decoder = JSONDecoder()
    let config = try decoder.decode(CoreConfig.Visor.self, from: data)
    #expect(config.webhookURLs.isEmpty)
}

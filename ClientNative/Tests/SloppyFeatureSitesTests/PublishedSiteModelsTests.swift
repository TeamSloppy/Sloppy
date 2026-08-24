import Foundation
import Testing
@testable import SloppyClientCore

@Test("client decodes published site list fields")
func clientPublishedSiteDecoding() throws {
    let json = """
    {
      "id":"site-1",
      "slug":"demo",
      "title":"Demo",
      "visibility":"public",
      "ownerId":"local",
      "projectId":null,
      "entryFile":"index.html",
      "revision":1,
      "path":"/sites/demo/",
      "createdAt":"2026-08-21T10:00:00Z",
      "updatedAt":"2026-08-21T10:00:00Z"
    }
    """
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let site = try decoder.decode(PublishedSiteRecord.self, from: Data(json.utf8))
    #expect(site.visibility == .public)
    #expect(site.path == "/sites/demo/")
}

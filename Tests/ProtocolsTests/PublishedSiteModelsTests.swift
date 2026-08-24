import Foundation
import Testing
@testable import Protocols

@Test("published site records encode and decode")
func publishedSiteRecordCodable() throws {
    let record = PublishedSiteRecord(
        id: "site-1",
        slug: "hello-world",
        title: "Hello World",
        visibility: .private,
        ownerId: "user-1",
        projectId: "project-1",
        entryFile: "index.html",
        revision: 2,
        path: "/sites/hello-world/"
    )
    let data = try JSONEncoder().encode(record)
    let decoded = try JSONDecoder().decode(PublishedSiteRecord.self, from: data)
    #expect(decoded == record)
}

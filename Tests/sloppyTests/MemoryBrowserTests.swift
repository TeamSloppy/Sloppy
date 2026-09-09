import Foundation
import Testing
@testable import Protocols
@testable import sloppy

@Suite
struct MemoryBrowserTests {
    @Test
    func listsAllScopesAndSupportsSharedSearchAndPaging() async throws {
        let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
        let store = await service.memoryStore
        for scope in [MemoryScope.agent("a"), .project("p"), MemoryScope(type: .global, id: "shared")] {
            _ = await store.save(entry: .init(note: "Memory for \(scope.type.rawValue)", kind: .fact, memoryClass: .semantic, scope: scope))
        }
        let router = CoreRouter(service: service)
        let response = await router.handle(method: "GET", path: "/v1/memories?limit=2&offset=1", body: nil)
        #expect(response.status == 200)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let page = try decoder.decode(MemoryListResponse.self, from: response.body)
        #expect(page.total == 3)
        #expect(page.items.count == 2)
        #expect(page.offset == 1)
        let shared = await service.listMemories(search: "global", filter: .all, sharedOnly: true, limit: 10, offset: 0)
        #expect(shared.total == 1)
        #expect(shared.items.first?.scope.type == .global)
        let missing = await service.listMemories(search: "missing", filter: .all, sharedOnly: false, limit: 10, offset: 0)
        #expect(missing.total == 0)
        let invalid = await router.handle(method: "GET", path: "/v1/memories?scope=unknown", body: nil)
        #expect(invalid.status == 400)
    }
}

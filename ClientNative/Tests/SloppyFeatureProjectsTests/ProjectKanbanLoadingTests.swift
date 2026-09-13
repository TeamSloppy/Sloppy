import Foundation
import Testing
import SloppyClientCore
@testable import SloppyFeatureProjects

@Suite("Kanban loading")
struct ProjectKanbanLoadingTests {
    @Test @MainActor func loadingFilteringAndFailedRefresh() async throws {
        let suite = "kanban-loading-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [KanbanFixtureURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let client = SloppyAPIClient(baseURL: URL(string: "https://kanban.test")!, session: session,
                                     authSessionStore: AuthSessionStore(persistence: .memory))
        let model = ProjectKanbanViewModel(apiClient: client, filterStore: ProjectKanbanFilterStore(defaults: defaults))
        let loading = Task { await model.load(projectId: "large") }
        // Observe UI state while networking is suspended; MainActor is available.
        for _ in 0..<100 where !model.isLoading { await Task.yield() }
        #expect(model.isLoading)
        await loading.value
        #expect(!model.isLoading)
        #expect(model.columns.flatMap(\.items).count == 3_000)
        #expect(model.filteredColumns.flatMap(\.items).count == 3_000)

        model.filters.searchText = "Task 2999"
        await model.updateFilteredColumns()
        #expect(model.filteredColumns.flatMap(\.items).map(\.id) == ["T-2999"])
        let previous = model.filteredColumns
        await model.load(projectId: "failure")
        #expect(model.errorMessage != nil)
        #expect(model.filteredColumns == previous)
        #expect(!model.isLoading)
    }

    @Test @MainActor func newerProjectWinsOverSlowResponse() async throws {
        let suite = "kanban-loading-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [KanbanFixtureURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let model = ProjectKanbanViewModel(apiClient: SloppyAPIClient(baseURL: URL(string: "https://kanban.test")!, session: session,
            authSessionStore: AuthSessionStore(persistence: .memory)), filterStore: ProjectKanbanFilterStore(defaults: defaults))
        let old = Task { await model.load(projectId: "slow") }
        for _ in 0..<100 where !model.isLoading { await Task.yield() }
        await model.load(projectId: "new")
        await old.value
        #expect(model.projectName == "new")
        #expect(!model.isLoading)
    }
}

private final class KanbanFixtureURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let id = request.url!.lastPathComponent
        DispatchQueue.global().asyncAfter(deadline: .now() + (id == "slow" ? 0.25 : 0.05)) { [self] in
            do {
                let data: Data
                if id == "agents" {
                    data = Data("[]".utf8)
                } else {
                    let tasks = (0..<(id == "large" ? 3_000 : 1)).map {
                        APIProjectTask(id: "T-\($0)", title: "Task \($0)", status: "backlog", tags: ["test"])
                    }
                    data = try JSONEncoder().encode(APIProjectRecord(id: id, name: id, tasks: tasks))
                }
                let response = HTTPURLResponse(url: request.url!, statusCode: id == "failure" ? 500 : 200, httpVersion: nil, headerFields: nil)!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch { client?.urlProtocol(self, didFailWithError: error) }
        }
    }
    override func stopLoading() {}
}

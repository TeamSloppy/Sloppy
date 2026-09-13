import Foundation
import Testing
import SloppyClientCore
@testable import SloppyFeatureProjects

@Suite("Kanban filter persistence")
struct ProjectKanbanFilterPersistenceTests {
    @Test @MainActor func restoresAllFieldsIntoNewModel() throws {
        let suite = "kanban-filters-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let endpoint = SloppyInstanceEndpoint.direct(baseURL: URL(string: "https://one.test")!)
        let first = ProjectKanbanViewModel(apiClient: SloppyAPIClient(endpoint: endpoint), filterStore: ProjectKanbanFilterStore(defaults: defaults))
        first.restoreFilters(projectId: "project")
        let expected = ProjectKanbanFilters(searchText: "Mail", priority: .high, status: .column(.needsReview), assignee: .actor("agent:qa"))
        first.filters = expected
        let reopened = ProjectKanbanViewModel(apiClient: SloppyAPIClient(endpoint: endpoint), filterStore: ProjectKanbanFilterStore(defaults: try #require(UserDefaults(suiteName: suite))))
        reopened.restoreFilters(projectId: "project")
        #expect(reopened.filters == expected)
        reopened.filters = ProjectKanbanFilters()
        let cleared = ProjectKanbanFilterStore(defaults: defaults).load(endpoint: endpoint, projectId: "project")
        #expect(cleared == ProjectKanbanFilters())
    }

    @Test @MainActor func projectsServersAndRelayNodesAreIndependent() throws {
        let suite = "kanban-filters-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ProjectKanbanFilterStore(defaults: defaults)
        let url = URL(string: "https://one.test")!
        let direct = SloppyInstanceEndpoint.direct(baseURL: url)
        let relay = SloppyInstanceEndpoint.relay(coordinatorBaseURL: url, targetNodeID: "node:1")
        let filters = ProjectKanbanFilters(priority: .none, assignee: .unassigned)
        store.save(filters, endpoint: direct, projectId: "project:1")
        #expect(store.load(endpoint: direct, projectId: "project:1") == filters)
        #expect(!store.load(endpoint: direct, projectId: "project:2").isActive)
        #expect(!store.load(endpoint: .direct(baseURL: URL(string: "https://two.test")!), projectId: "project:1").isActive)
        #expect(!store.load(endpoint: relay, projectId: "project:1").isActive)
        store.save(filters, endpoint: relay, projectId: "project:1")
        #expect(!store.load(endpoint: .relay(coordinatorBaseURL: url, targetNodeID: "node:2"), projectId: "project:1").isActive)
        let model = ProjectKanbanViewModel(apiClient: SloppyAPIClient(endpoint: direct), filterStore: store)
        model.restoreFilters(projectId: "project:1")
        model.restoreFilters(projectId: "project:2")
        model.restoreFilters(projectId: "project:1")
        #expect(model.filters == filters)
    }

    @Test @MainActor func corruptStoredDataFallsBackToEmptyFilter() throws {
        let suite = "kanban-filters-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ProjectKanbanFilterStore(defaults: defaults)
        let endpoint = SloppyInstanceEndpoint.direct(baseURL: URL(string: "https://one.test")!)
        store.save(ProjectKanbanFilters(searchText: "query"), endpoint: endpoint, projectId: "p")
        let key = try #require(defaults.persistentDomain(forName: suite)?.keys.first)
        defaults.set(Data("broken".utf8), forKey: key)
        #expect(!store.load(endpoint: endpoint, projectId: "p").isActive)
    }
}

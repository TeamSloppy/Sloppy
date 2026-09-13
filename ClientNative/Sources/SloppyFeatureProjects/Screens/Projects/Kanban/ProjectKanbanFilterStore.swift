import Foundation
import SloppyClientCore

@MainActor
public final class ProjectKanbanFilterStore {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public func load(endpoint: SloppyInstanceEndpoint, projectId: String) -> ProjectKanbanFilters {
        guard let data = defaults.data(forKey: key(endpoint, projectId)),
              let saved = try? JSONDecoder().decode(Snapshot.self, from: data), saved.version == 1 else {
            return ProjectKanbanFilters()
        }
        let assignee: ProjectKanbanAssigneeFilter
        if saved.assigneeMode == "unassigned" {
            assignee = .unassigned
        } else if saved.assigneeMode == "actor", let actorId = saved.actorId, !actorId.isEmpty {
            assignee = .actor(actorId)
        } else {
            assignee = .all
        }
        return ProjectKanbanFilters(
            searchText: saved.searchText,
            priority: ProjectKanbanPriorityFilter(rawValue: saved.priority) ?? .all,
            status: saved.status.flatMap(ProjectKanbanColumnID.init(rawValue:)).map(ProjectKanbanStatusFilter.column) ?? .all,
            assignee: assignee
        )
    }

    public func save(_ filters: ProjectKanbanFilters, endpoint: SloppyInstanceEndpoint, projectId: String) {
        let storageKey = key(endpoint, projectId)
        guard filters != ProjectKanbanFilters() else {
            defaults.removeObject(forKey: storageKey)
            return
        }
        var saved = Snapshot(searchText: filters.searchText, priority: filters.priority.rawValue)
        if case .column(let status) = filters.status { saved.status = status.rawValue }
        switch filters.assignee {
        case .all: break
        case .unassigned: saved.assigneeMode = "unassigned"
        case .actor(let id): saved.assigneeMode = "actor"; saved.actorId = id
        }
        if let data = try? JSONEncoder().encode(saved) { defaults.set(data, forKey: storageKey) }
    }

    private func key(_ endpoint: SloppyInstanceEndpoint, _ projectId: String) -> String {
        // JSON preserves boundaries even when IDs contain delimiters.
        let scope = (try? JSONEncoder().encode([endpoint.cacheNamespace, projectId])) ?? Data()
        return "client_kanban_filter_v1." + scope.base64EncodedString()
    }

    private struct Snapshot: Codable {
        var version = 1
        var searchText: String
        var priority: String
        var status: String?
        var assigneeMode = "all"
        var actorId: String?
    }
}

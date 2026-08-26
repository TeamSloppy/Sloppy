import Foundation
import Observation
import SloppyClientCore

public struct ProjectKanbanCard: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let status: String
    public let priority: String?
    public let actorID: String?
    public let executionNodeID: String?
    public let description: String?
    public let tags: [String]

    public init(
        id: String,
        title: String,
        status: String,
        priority: String?,
        actorID: String?,
        executionNodeID: String? = nil,
        description: String? = nil,
        tags: [String] = []
    ) {
        self.id = id
        self.title = title
        self.status = status
        self.priority = priority
        self.actorID = actorID
        self.executionNodeID = executionNodeID
        self.description = description
        self.tags = tags
    }
}

public enum ProjectKanbanPriorityFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case high
    case medium
    case low
    case none

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .all: "All priorities"
        case .high: "High"
        case .medium: "Medium"
        case .low: "Low"
        case .none: "No priority"
        }
    }
}

public enum ProjectKanbanStatusFilter: Hashable, Sendable {
    case all
    case column(ProjectKanbanColumnID)

    public var title: String {
        switch self {
        case .all: "All statuses"
        case .column(let columnID): columnID.title
        }
    }
}

public enum ProjectKanbanAssigneeFilter: Hashable, Sendable {
    case all
    case unassigned
    case actor(String)

    public var title: String {
        switch self {
        case .all: "All assignees"
        case .unassigned: "Unassigned"
        case .actor(let actorID): actorID
        }
    }
}

public struct ProjectKanbanFilters: Equatable, Sendable {
    public var searchText: String
    public var priority: ProjectKanbanPriorityFilter
    public var status: ProjectKanbanStatusFilter
    public var assignee: ProjectKanbanAssigneeFilter

    public init(
        searchText: String = "",
        priority: ProjectKanbanPriorityFilter = .all,
        status: ProjectKanbanStatusFilter = .all,
        assignee: ProjectKanbanAssigneeFilter = .all
    ) {
        self.searchText = searchText
        self.priority = priority
        self.status = status
        self.assignee = assignee
    }

    public var isActive: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || priority != .all
            || status != .all
            || assignee != .all
    }
}

public struct ProjectKanbanActorOption: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String

    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}

public struct ProjectKanbanColumn: Identifiable, Equatable, Sendable {
    public let id: ProjectKanbanColumnID
    public let title: String
    public let items: [ProjectKanbanCard]

    public init(id: ProjectKanbanColumnID, title: String, items: [ProjectKanbanCard]) {
        self.id = id
        self.title = title
        self.items = items
    }
}

@Observable
@MainActor
public final class ProjectKanbanViewModel {
    public private(set) var projectName: String = ""
    public private(set) var columns: [ProjectKanbanColumn] = []
    public private(set) var availableActors: [ProjectKanbanActorOption] = []
    public let availableInstances: [SloppyInstance]
    public let preferredExecutionNodeID: String
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?

    @ObservationIgnored private let apiClient: SloppyAPIClient
    @ObservationIgnored private var tasks: [APIProjectTask] = []

    public init(
        apiClient: SloppyAPIClient,
        availableInstances: [SloppyInstance] = [],
        preferredExecutionNodeID: String? = nil
    ) {
        self.apiClient = apiClient
        self.availableInstances = availableInstances
        self.preferredExecutionNodeID = preferredExecutionNodeID
            ?? availableInstances.first(where: \.isLocal)?.id
            ?? availableInstances.first?.id
            ?? ""
    }

    public func load(projectId: String) async {
        isLoading = true
        defer { isLoading = false }

        do {
            let project = try await apiClient.fetchProject(id: projectId)
            let agents = (try? await apiClient.fetchAgents()) ?? []
            apply(project: project, agents: agents)
        } catch {
            projectName = ""
            tasks = []
            columns = []
            availableActors = []
            errorMessage = "Could not load project board."
        }
    }

    public func createTask(
        projectId: String,
        request: APIProjectTaskCreateRequest
    ) async throws {
        let project = try await apiClient.createProjectTask(projectId: projectId, request: request)
        apply(project: project)
    }

    public func moveTask(
        id taskID: String,
        to columnID: ProjectKanbanColumnID,
        projectId: String
    ) async {
        guard let task = tasks.first(where: { $0.id == taskID }),
              task.normalizedKanbanColumnID != columnID else {
            return
        }

        do {
            let project = try await apiClient.updateProjectTask(
                projectId: projectId,
                taskId: taskID,
                request: APIProjectTaskUpdateRequest(status: columnID.taskStatus)
            )
            apply(project: project)
        } catch {
            errorMessage = "Could not update task status."
        }
    }

    public func assignTask(
        id taskID: String,
        to executionNodeID: String,
        projectId: String
    ) async {
        do {
            let project = try await apiClient.updateProjectTask(
                projectId: projectId,
                taskId: taskID,
                request: APIProjectTaskUpdateRequest(executionNodeId: executionNodeID)
            )
            apply(project: project)
        } catch {
            errorMessage = "Could not change the task instance."
        }
    }

    public func columns(matching filters: ProjectKanbanFilters) -> [ProjectKanbanColumn] {
        Self.buildColumns(from: tasks, filters: filters)
    }

    public func assigneeTitle(for filter: ProjectKanbanAssigneeFilter) -> String {
        guard case .actor(let actorID) = filter else {
            return filter.title
        }
        return availableActors.first(where: { $0.id == actorID })?.title ?? actorID
    }

    public func instanceTitle(for nodeID: String) -> String {
        availableInstances.first(where: { $0.id == nodeID })?.displayName ?? nodeID
    }

    nonisolated static func buildColumns(
        from tasks: [APIProjectTask],
        filters: ProjectKanbanFilters = ProjectKanbanFilters()
    ) -> [ProjectKanbanColumn] {
        let filteredTasks = tasks.filter { task in
            matches(task: task, filters: filters)
        }
        let grouped = Dictionary(grouping: filteredTasks) { $0.normalizedKanbanColumnID }
        let visibleColumnIDs: [ProjectKanbanColumnID]
        switch filters.status {
        case .all:
            visibleColumnIDs = ProjectKanbanColumnID.allCases
        case .column(let columnID):
            visibleColumnIDs = [columnID]
        }

        return visibleColumnIDs.map { columnID in
            let cards = (grouped[columnID] ?? []).map {
                ProjectKanbanCard(
                    id: $0.id,
                    title: $0.title,
                    status: $0.status,
                    priority: $0.priority,
                    actorID: $0.actorId,
                    executionNodeID: $0.executionNodeId,
                    description: $0.description,
                    tags: $0.tags ?? []
                )
            }
            return ProjectKanbanColumn(id: columnID, title: columnID.title, items: cards)
        }
    }

    private func apply(project: APIProjectRecord, agents: [APIAgentRecord]? = nil) {
        projectName = project.name
        tasks = project.tasks ?? []
        columns = Self.buildColumns(from: tasks)
        errorMessage = nil

        let actorIDs = Set((project.actors ?? []) + tasks.compactMap(\.actorId))
        let knownAgents = agents ?? availableActors.map {
            APIAgentRecord(id: $0.id, displayName: $0.title)
        }
        let namesByID = Dictionary(uniqueKeysWithValues: knownAgents.map { ($0.id, $0.displayName) })
        availableActors = actorIDs
            .map { ProjectKanbanActorOption(id: $0, title: namesByID[$0] ?? $0) }
            .sorted {
                $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
    }

    nonisolated private static func matches(
        task: APIProjectTask,
        filters: ProjectKanbanFilters
    ) -> Bool {
        if filters.priority != .all {
            let normalizedPriority = task.priority?.lowercased()
            switch filters.priority {
            case .all:
                break
            case .none:
                guard normalizedPriority?.isEmpty != false else { return false }
            default:
                guard normalizedPriority == filters.priority.rawValue else { return false }
            }
        }

        switch filters.assignee {
        case .all:
            break
        case .unassigned:
            guard task.actorId?.isEmpty != false else { return false }
        case .actor(let actorID):
            guard task.actorId == actorID else { return false }
        }

        let query = filters.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        let searchableValues = [
            task.title,
            task.description ?? "",
            task.actorId ?? "",
            task.priority ?? "",
            (task.tags ?? []).joined(separator: " "),
        ]
        return searchableValues.contains {
            $0.localizedCaseInsensitiveContains(query)
        }
    }
}

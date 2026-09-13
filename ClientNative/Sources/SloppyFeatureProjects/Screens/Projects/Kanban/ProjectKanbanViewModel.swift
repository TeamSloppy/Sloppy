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
    public let externalMetadata: APIProjectTaskExternalMetadata?
    public let tags: [String]
    public let assigneeID: String?
    public let isClaimed: Bool
    public let kanbanColumnEnteredAt: Date?

    public init(
        id: String,
        title: String,
        status: String,
        priority: String?,
        actorID: String?,
        executionNodeID: String? = nil,
        description: String? = nil,
        tags: [String] = [],
        externalMetadata: APIProjectTaskExternalMetadata? = nil,
        assigneeID: String? = nil,
        isClaimed: Bool = false,
        kanbanColumnEnteredAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.status = status
        self.priority = priority
        self.actorID = actorID
        self.executionNodeID = executionNodeID
        self.description = description
        self.tags = tags
        self.externalMetadata = externalMetadata
        self.assigneeID = [assigneeID, actorID].compactMap { $0 }.first { !$0.isEmpty }
        self.isClaimed = isClaimed
        self.kanbanColumnEnteredAt = kanbanColumnEnteredAt
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
    public private(set) var filteredColumns: [ProjectKanbanColumn] = []
    public private(set) var filterRevision = 0
    public var filters = ProjectKanbanFilters() {
        didSet {
            guard filters != oldValue else { return }
            filterRevision &+= 1
            if let filterProjectID {
                filterStore.save(filters, endpoint: apiClient.endpoint, projectId: filterProjectID)
            }
        }
    }
    @ObservationIgnored private let filterStore: ProjectKanbanFilterStore
    @ObservationIgnored private var filterProjectID: String?
    @ObservationIgnored private var loadID = UUID()
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
        preferredExecutionNodeID: String? = nil,
        filterStore: ProjectKanbanFilterStore = ProjectKanbanFilterStore()
    ) {
        self.apiClient = apiClient
        self.filterStore = filterStore
        self.availableInstances = availableInstances
        self.preferredExecutionNodeID = preferredExecutionNodeID
            ?? availableInstances.first(where: \.isLocal)?.id
            ?? availableInstances.first?.id
            ?? ""
    }

    public func makeTaskDetailViewModel() -> TaskDetailViewModel {
        TaskDetailViewModel(apiClient: apiClient)
    }

    public func restoreFilters(projectId: String) {
        guard filterProjectID != projectId else { return }
        filterProjectID = nil
        filters = filterStore.load(endpoint: apiClient.endpoint, projectId: projectId)
        filterProjectID = projectId
    }

    public func load(projectId: String) async {
        restoreFilters(projectId: projectId)
        let requestID = UUID()
        loadID = requestID
        isLoading = true
        defer { if loadID == requestID { isLoading = false } }

        do {
            async let projectRequest = apiClient.fetchProject(id: projectId)
            async let agentsRequest = apiClient.fetchAgents()
            let project = try await projectRequest
            let agents = (try? await agentsRequest) ?? []
            guard loadID == requestID, !Task.isCancelled else { return }
            try await apply(project: project, agents: agents, requestID: requestID)
            guard loadID == requestID, !Task.isCancelled else { return }
        } catch {
            guard loadID == requestID, !Task.isCancelled else { return }
            errorMessage = "Could not load project board."
        }
    }

    public func createTask(
        projectId: String,
        request: APIProjectTaskCreateRequest
    ) async throws {
        let project = try await apiClient.createProjectTask(projectId: projectId, request: request)
        try await apply(project: project)
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
            try await apply(project: project)
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
            try await apply(project: project)
        } catch {
            errorMessage = "Could not change the task instance."
        }
    }

    public func updateFilteredColumns() async {
        let revision = filterRevision
        let tasks = tasks
        let filters = filters
        do {
            let result = try await ClientBackgroundWork.run {
                Self.buildColumns(from: tasks, filters: filters)
            }
            guard revision == filterRevision, !Task.isCancelled else { return }
            filteredColumns = result
        } catch { /* Superseded filters keep the last rendered board. */ }
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
                    tags: $0.tags ?? [],
                    externalMetadata: $0.externalMetadata,
                    assigneeID: $0.kanbanAssigneeID,
                    isClaimed: $0.claimedActorId?.isEmpty == false || $0.claimedAgentId?.isEmpty == false,
                    kanbanColumnEnteredAt: $0.kanbanColumnEnteredAt
                )
            }
            return ProjectKanbanColumn(id: columnID, title: columnID.title, items: cards)
        }
    }

    private func apply(project: APIProjectRecord, agents: [APIAgentRecord]? = nil, requestID: UUID? = nil) async throws {
        let knownAgents = agents ?? availableActors.map {
            APIAgentRecord(id: $0.id, displayName: $0.title)
        }
        let currentFilters = filters
        let snapshot = try await ClientBackgroundWork.run {
            let tasks = project.tasks ?? []
            let actorIDs = Set((project.actors ?? []) + tasks.compactMap(\.kanbanAssigneeID))
            let namesByID = knownAgents.reduce(into: [String: String]()) { $0[$1.id] = $1.displayName }
            let actors = actorIDs.map { id in
                ProjectKanbanActorOption(id: id, title: namesByID[id]
                    ?? (id.hasPrefix("agent:") ? namesByID[String(id.dropFirst(6))] : nil) ?? id)
            }.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            return (Self.buildColumns(from: tasks), Self.buildColumns(from: tasks, filters: currentFilters), actors)
        }
        try Task.checkCancellation()
        if let requestID, loadID != requestID { throw CancellationError() }
        projectName = project.name
        tasks = project.tasks ?? []
        columns = snapshot.0
        filteredColumns = snapshot.1
        availableActors = snapshot.2
        filterRevision &+= 1
        errorMessage = nil
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
            guard task.kanbanAssigneeID == nil else { return false }
        case .actor(let actorID):
            guard task.kanbanAssigneeID == actorID else { return false }
        }

        let query = filters.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        let searchableValues = [
            task.title,
            task.description ?? "",
            task.kanbanAssigneeID ?? "",
            task.priority ?? "",
            (task.tags ?? []).joined(separator: " "),
        ]
        return searchableValues.contains {
            $0.localizedCaseInsensitiveContains(query)
        }
    }
}

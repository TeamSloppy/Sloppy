import Foundation
import Observation
import SloppyClientCore

public struct ProjectKanbanCard: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let priority: String?
    public let actorID: String?

    public init(id: String, title: String, priority: String?, actorID: String?) {
        self.id = id
        self.title = title
        self.priority = priority
        self.actorID = actorID
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
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?

    @ObservationIgnored private let apiClient: SloppyAPIClient

    public init(apiClient: SloppyAPIClient) {
        self.apiClient = apiClient
    }

    public func load(projectId: String) async {
        isLoading = true
        defer { isLoading = false }

        do {
            let project = try await apiClient.fetchProject(id: projectId)
            projectName = project.name
            errorMessage = nil
            columns = Self.buildColumns(from: project.tasks ?? [])
        } catch {
            projectName = ""
            columns = []
            errorMessage = "Could not load project board."
        }
    }

    static func buildColumns(from tasks: [APIProjectTask]) -> [ProjectKanbanColumn] {
        let grouped = Dictionary(grouping: tasks) { $0.normalizedKanbanColumnID }
        return ProjectKanbanColumnID.allCases.map { columnID in
            let cards = (grouped[columnID] ?? []).map {
                ProjectKanbanCard(
                    id: $0.id,
                    title: $0.title,
                    priority: $0.priority,
                    actorID: $0.actorId
                )
            }
            return ProjectKanbanColumn(id: columnID, title: columnID.title, items: cards)
        }
    }
}

import Foundation
import Observation

public enum ProjectTaskInboxStatus: String, Sendable, Hashable, Identifiable {
    case working = "in_progress"
    case attention = "blocked"
    case review = "needs_review"

    public var id: Self { self }
    public var title: String {
        switch self {
        case .working: "Working"
        case .attention: "Needs Attention"
        case .review: "In Review"
        }
    }

    public func matches(_ task: APIProjectTask) -> Bool { task.status == rawValue }

    public func count(in project: APIProjectRecord) -> Int? {
        if let tasks = project.tasks { return tasks.count(where: matches) }
        switch self {
        case .working: return project.taskCounts?.inProgress
        case .attention: return project.taskCounts?.blocked
        case .review: return project.taskCounts?.needsReview
        }
    }
}

@Observable
@MainActor
public final class ProjectTaskInbox {
    public private(set) var projects: [APIProjectRecord] = []
    public private(set) var errors: [String] = []
    public private(set) var isLoading = false
    public private(set) var hasLoaded = false
    private let status: ProjectTaskInboxStatus
    private let fetchProject: @Sendable (APIProjectRecord) async throws -> APIProjectRecord
    private var loadedProjects: [String: APIProjectRecord] = [:]

    public init(status: ProjectTaskInboxStatus,
                fetchProject: @escaping @Sendable (APIProjectRecord) async throws -> APIProjectRecord) {
        self.status = status
        self.fetchProject = fetchProject
    }

    public func refresh(projects summaries: [APIProjectRecord]) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        // Unknown counts must be checked; known empty projects need no detail request.
        let candidates = summaries.filter { status.count(in: $0) != 0 }
        let results = await withTaskGroup(of: LoadResult.self) { group in
            for summary in candidates {
                group.addTask { [fetchProject] in
                    do {
                        var project: APIProjectRecord
                        if summary.tasks != nil { project = summary }
                        else { project = try await fetchProject(summary) }
                        project.sourceInstanceID = summary.sourceInstanceID
                        return LoadResult(summary: summary, project: project, error: nil)
                    } catch {
                        return LoadResult(summary: summary, project: nil, error: error.localizedDescription)
                    }
                }
            }
            var results: [LoadResult] = []
            for await result in group { results.append(result) }
            return results
        }
        guard !Task.isCancelled else { return }
        let candidateIDs = Set(candidates.map(\.storageID))
        loadedProjects = loadedProjects.filter { candidateIDs.contains($0.key) }
        for result in results {
            if let project = result.project { loadedProjects[result.summary.storageID] = project }
        }
        projects = candidates.compactMap { loadedProjects[$0.storageID] }
            .filter { ($0.tasks ?? []).contains(where: status.matches) }
        errors = results.compactMap { result in
            result.error.map { "\(result.summary.name): \($0)" }
        }.sorted()
        hasLoaded = true
    }

    private struct LoadResult: Sendable {
        var summary: APIProjectRecord
        var project: APIProjectRecord?
        var error: String?
    }
}

import Foundation
import Observation
import SloppyClientCore

enum MainContentMode: String {
    case coding
    case workspace
}

private struct CanvasWorkspaceTarget: Equatable {
    var workspaceID: String?
    var projectID: String?
    var projectName: String?
}

@Observable
@MainActor
final class CanvasWorkspaceViewModel {
    private static let defaultAPIBaseURL = URL(string: "http://localhost:25101")!
    private static let defaultDashboardBaseURL = URL(string: "http://localhost:25102")!

    private let apiClient: SloppyAPIClient
    private let apiBaseURL: URL
    private let dashboardBaseURL: URL
    private var target: CanvasWorkspaceTarget?
    private var resolutionID = UUID()

    private(set) var workspaces: [CanvasWorkspaceSummary] = []
    private(set) var selectedWorkspaceID: String?
    private(set) var suggestedWorkspaceID: String?
    private(set) var projectID: String?
    private(set) var projectName: String?
    private(set) var url: URL?
    private(set) var title = "Workspaces"
    private(set) var isResolving = false
    private(set) var libraryError: String?
    private(set) var pageReloadToken = 0
    var isLoadingPage = false
    var pageError: String?

    var isShowingLibrary: Bool {
        selectedWorkspaceID == nil
    }

    var libraryTitle: String {
        projectID == nil ? "Workspaces" : "Project Workspaces"
    }

    var librarySubtitle: String {
        if let projectName {
            return "Canvases linked to \(projectName)"
        }
        if projectID != nil {
            return "Canvases linked to the current project"
        }
        return "Shared canvases for you and your agents"
    }

    init(
        baseURL: URL? = nil,
        dashboardBaseURL: URL? = nil,
        apiClient: SloppyAPIClient? = nil
    ) {
        let resolvedAPIBaseURL = baseURL ?? apiClient?.baseURL ?? Self.defaultAPIBaseURL
        self.apiClient = apiClient ?? SloppyAPIClient(baseURL: resolvedAPIBaseURL)
        self.apiBaseURL = resolvedAPIBaseURL
        self.dashboardBaseURL = dashboardBaseURL ?? Self.defaultDashboardBaseURL
    }

    func resolve(
        workspaceID: String?,
        projectID: String?,
        projectName: String? = nil,
        force: Bool = false
    ) async {
        let nextTarget = CanvasWorkspaceTarget(
            workspaceID: Self.normalized(workspaceID),
            projectID: Self.normalized(projectID),
            projectName: Self.normalized(projectName)
        )
        guard force || target != nextTarget else {
            return
        }

        target = nextTarget
        self.projectID = nextTarget.projectID
        self.projectName = nextTarget.projectName
        suggestedWorkspaceID = nextTarget.workspaceID
        showLibrary()
        await refreshLibrary()
    }

    func refreshLibrary() async {
        let requestID = UUID()
        resolutionID = requestID
        isResolving = true
        libraryError = nil
        defer {
            if resolutionID == requestID {
                isResolving = false
            }
        }

        do {
            let records = try await apiClient.fetchCanvasWorkspaces(projectId: projectID)
                .filter { !$0.isArchived }
                .sorted { $0.updatedAt > $1.updatedAt }
            guard resolutionID == requestID else {
                return
            }
            workspaces = records
        } catch {
            guard resolutionID == requestID else {
                return
            }
            libraryError = error.localizedDescription
        }
    }

    @discardableResult
    func createWorkspace(title: String, description: String?) async throws -> CanvasWorkspaceSummary {
        let workspace = try await apiClient.createCanvasWorkspace(
            title: title,
            description: Self.normalized(description),
            projectId: projectID
        )
        workspaces = ([workspace] + workspaces.filter { $0.id != workspace.id })
            .sorted { $0.updatedAt > $1.updatedAt }
        openWorkspace(workspace)
        return workspace
    }

    func openWorkspace(_ workspace: CanvasWorkspaceSummary) {
        selectedWorkspaceID = workspace.id
        title = workspace.title
        pageError = nil
        isLoadingPage = false
        url = Self.workspaceURL(
            baseURL: dashboardBaseURL,
            apiBaseURL: apiBaseURL,
            workspaceID: workspace.id
        )
    }

    func showLibrary() {
        selectedWorkspaceID = nil
        url = nil
        title = libraryTitle
        pageError = nil
        isLoadingPage = false
    }

    func retry() async {
        pageError = nil
        if selectedWorkspaceID != nil {
            pageReloadToken += 1
        } else {
            await refreshLibrary()
        }
    }

    private static func workspaceURL(
        baseURL: URL,
        apiBaseURL: URL,
        workspaceID: String
    ) -> URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.path = "/workspaces/\(workspaceID)"
        components?.queryItems = [
            URLQueryItem(name: "embed", value: "workspace"),
            URLQueryItem(name: "apiBase", value: apiBaseURL.absoluteString),
        ]
        return components?.url ?? baseURL
    }

    private static func normalized(_ value: String?) -> String? {
        guard let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !normalized.isEmpty else {
            return nil
        }
        return normalized
    }
}

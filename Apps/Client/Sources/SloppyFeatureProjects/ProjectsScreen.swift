import AdaEngine
import SloppyClientCore
import SloppyClientUI

public struct ProjectsScreen: View {
    @State private var projects: [APIProjectRecord] = []
    @State private var isLoading = false

    private let apiClient: SloppyAPIClient

    public init(apiClient: SloppyAPIClient = SloppyAPIClient()) {
        self.apiClient = apiClient
    }

    public var body: some View {
        NavigationStack {
            ProjectListView(
                projects: projects,
                isLoading: isLoading,
                onRefresh: { loadProjects() }
            )
            .onAppear { loadProjects() }
            .navigate(for: String.self) { projectId in
                if let project = projects.first(where: { $0.id == projectId }) {
                    ProjectDetailView(project: project)
                }
            }
        }
    }

    private func loadProjects() {
        Task { @MainActor in
            isLoading = true
            let fetched = (try? await apiClient.fetchProjects()) ?? []
            projects = fetched
            isLoading = false
        }
    }
}

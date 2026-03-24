import AdaEngine
import SloppyClientCore
import SloppyClientUI

public struct ProjectsScreen: View {
    @State private var projects: [APIProjectRecord] = []
    @State private var selectedProjectId: String?
    @State private var isLoading = false

    private let apiClient: SloppyAPIClient

    public init(apiClient: SloppyAPIClient = SloppyAPIClient()) {
        self.apiClient = apiClient
    }

    public var body: some View {
        if let projectId = selectedProjectId,
           let project = projects.first(where: { $0.id == projectId }) {
            ProjectDetailView(
                project: project,
                onBack: { selectedProjectId = nil }
            )
        } else {
            ProjectListView(
                projects: projects,
                isLoading: isLoading,
                onSelect: { selectedProjectId = $0.id },
                onRefresh: { loadProjects() }
            )
            .onAppear { loadProjects() }
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

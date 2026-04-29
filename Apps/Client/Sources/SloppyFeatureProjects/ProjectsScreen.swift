import AdaEngine
import SloppyClientCore
import SloppyClientUI

@MainActor
public struct ProjectsScreen: View {
    @State private var projects: [APIProjectRecord] = []
    @State private var isLoading = false
    @State private var didLoadProjects = false

    private let apiClient: SloppyAPIClient

    public init(apiClient: SloppyAPIClient = SloppyAPIClient()) {
        self.apiClient = apiClient
    }

    public var body: some View {
        NavigationStack {
            ProjectListView(
                projects: projects,
                isLoading: isLoading,
                onRefresh: { loadProjects(force: true) }
            )
            .onAppear { loadProjects() }
            .navigate(for: String.self) { projectId in
                if let project = projects.first(where: { $0.id == projectId }) {
                    ProjectDetailView(project: project)
                }
            }
        }
    }

    private func loadProjects(force: Bool = false) {
        guard force || !didLoadProjects else { return }
        guard !isLoading else { return }

        isLoading = true
        Task { @MainActor in
            defer {
                didLoadProjects = true
                isLoading = false
            }
            let fetched = (try? await apiClient.fetchProjects()) ?? []
            projects = fetched
        }
    }
}

import AdaEngine
import SloppyClientCore
import SloppyClientUI

struct ProjectListView: View {
    let projects: [APIProjectRecord]
    let isLoading: Bool
    let onSelect: (APIProjectRecord) -> Void
    let onRefresh: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacingL) {
                HStack {
                    SectionHeader("Projects")
                    Spacer()
                    Button("REFRESH") { onRefresh() }
                        .foregroundColor(Theme.accent)
                }

                if projects.isEmpty {
                    EmptyStateView(isLoading ? "Loading..." : "No projects found")
                } else {
                    VStack(spacing: Theme.spacingS) {
                        ForEach(projects) { project in
                            EntityCard(
                                title: project.name,
                                subtitle: project.description.isEmpty ? "No description" : project.description,
                                trailing: taskSummary(project),
                                accentColor: Theme.accent,
                                onTap: { onSelect(project) }
                            )
                        }
                    }
                }
            }
            .padding(Theme.spacingL)
        }
    }

    private func taskSummary(_ project: APIProjectRecord) -> String {
        let total = project.tasks?.count ?? 0
        let active = project.tasks?.filter {
            ["in_progress", "ready", "needs_review"].contains($0.status)
        }.count ?? 0
        return "\(active)/\(total)"
    }
}

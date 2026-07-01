import SwiftUI
import SloppyClientCore
import SloppyClientUI

@MainActor
public struct ProjectKanbanView: View {
    let viewModel: ProjectKanbanViewModel
    let projectId: String
    let projectName: String

    @Environment(\.theme) private var theme

    public init(viewModel: ProjectKanbanViewModel, projectId: String, projectName: String) {
        self.viewModel = viewModel
        self.projectId = projectId
        self.projectName = projectName
    }

    public var body: some View {
        Group {
            if viewModel.isLoading && viewModel.columns.isEmpty {
                ProgressView("Loading board…")
            } else if let errorMessage = viewModel.errorMessage {
                VStack(spacing: theme.spacing.m) {
                    Text(projectName)
                        .font(.system(size: theme.typography.title))
                        .foregroundColor(theme.colors.textPrimary)
                    Text(errorMessage)
                        .font(.system(size: theme.typography.body))
                        .foregroundColor(theme.colors.statusBlocked)
                }
            } else if viewModel.columns.allSatisfy({ $0.items.isEmpty }) {
                VStack(spacing: theme.spacing.m) {
                    Text(projectName)
                        .font(.system(size: theme.typography.title))
                        .foregroundColor(theme.colors.textPrimary)
                    Text("No tasks yet.")
                        .font(.system(size: theme.typography.body))
                        .foregroundColor(theme.colors.textSecondary)
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: theme.spacing.m) {
                        ForEach(viewModel.columns) { column in
                            kanbanColumn(column)
                        }
                    }
                    .padding(theme.spacing.l)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: projectId) {
            await viewModel.load(projectId: projectId)
        }
    }

    private func kanbanColumn(_ column: ProjectKanbanColumn) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing.s) {
            HStack {
                Text(column.title)
                    .font(.system(size: theme.typography.body))
                    .foregroundColor(theme.colors.textPrimary)
                Spacer(minLength: 0)
                Text("\(column.items.count)")
                    .font(.system(size: theme.typography.caption))
                    .foregroundColor(theme.colors.textMuted)
            }

            ForEach(column.items) { card in
                VStack(alignment: .leading, spacing: theme.spacing.xs) {
                    Text(card.title)
                        .font(.system(size: theme.typography.body))
                        .foregroundColor(theme.colors.textPrimary)

                    if let priority = card.priority, !priority.isEmpty {
                        Text(priority.uppercased())
                            .font(.system(size: theme.typography.micro))
                            .foregroundColor(theme.colors.textMuted)
                    }

                    if let actorID = card.actorID, !actorID.isEmpty {
                        Text(actorID)
                            .font(.system(size: theme.typography.caption))
                            .foregroundColor(theme.colors.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(theme.spacing.m)
                .background(theme.colors.surface)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }

            Spacer(minLength: 0)
        }
        .frame(width: 280, alignment: .topLeading)
        .padding(theme.spacing.m)
        .background(theme.colors.surfaceRaised.opacity(0.82 as CGFloat))
        .clipShape(RoundedRectangle(cornerRadius: 22))
    }
}

import Foundation
import Observation
import SwiftUI
import SloppyClientCore
import SloppyClientUI

@Observable
@MainActor
public final class TaskDetailViewModel {
    public private(set) var projectName: String = ""
    public private(set) var task: APIProjectTask?
    public private(set) var comments: [TaskComment] = []
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?

    @ObservationIgnored private let apiClient: SloppyAPIClient

    public init(apiClient: SloppyAPIClient) {
        self.apiClient = apiClient
    }

    public func load(projectId: String, taskId: String) async {
        isLoading = true
        defer { isLoading = false }

        do {
            async let projectRequest = apiClient.fetchProject(id: projectId)
            async let commentsRequest = apiClient.fetchTaskComments(projectId: projectId, taskId: taskId)

            let project = try await projectRequest
            let fetchedComments = try await commentsRequest

            projectName = project.name
            comments = fetchedComments
            task = project.tasks?.first(where: { $0.id == taskId })

            if task == nil {
                errorMessage = "Could not find this task in the project."
            } else {
                errorMessage = nil
            }
        } catch {
            projectName = ""
            task = nil
            comments = []
            errorMessage = "Could not load task details."
        }
    }
}

@MainActor
public struct TaskDetailView: View {
    let viewModel: TaskDetailViewModel
    let projectId: String
    let taskId: String
    let onOpenChat: @MainActor (APIProjectTask) -> Void

    @Environment(\.theme) private var theme

    public init(
        viewModel: TaskDetailViewModel,
        projectId: String,
        taskId: String,
        onOpenChat: @escaping @MainActor (APIProjectTask) -> Void = { _ in }
    ) {
        self.viewModel = viewModel
        self.projectId = projectId
        self.taskId = taskId
        self.onOpenChat = onOpenChat
    }

    public var body: some View {
        Group {
            if viewModel.isLoading && viewModel.task == nil {
                ProgressView("Loading task…")
            } else if let errorMessage = viewModel.errorMessage, viewModel.task == nil {
                contentState(title: "Task Detail", message: errorMessage)
            } else if let task = viewModel.task {
                ScrollView {
                    VStack(alignment: .leading, spacing: theme.spacing.l) {
                        header(task: task)
                        metadata(task: task)
                        description(task: task)
                        commentsSection
                    }
                    .padding(theme.spacing.xl)
                    .frame(maxWidth: 920, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            } else {
                contentState(title: "Task Detail", message: "No task data available.")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: "\(projectId):\(taskId)") {
            await viewModel.load(projectId: projectId, taskId: taskId)
        }
    }

    private func header(task: APIProjectTask) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing.s) {
            Text(viewModel.projectName)
                .font(.system(size: theme.typography.caption))
                .foregroundColor(theme.colors.textMuted)

            Text(task.title)
                .font(.system(size: theme.typography.title))
                .foregroundColor(theme.colors.textPrimary)

            HStack(spacing: theme.spacing.s) {
                taskChip(task.status.replacingOccurrences(of: "_", with: " ").capitalized)

                if let priority = task.priority, !priority.isEmpty {
                    taskChip(priority.uppercased())
                }

                Spacer(minLength: 0)

                Button("Open Chat") {
                    onOpenChat(task)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, theme.spacing.m)
                .padding(.vertical, theme.spacing.s)
                .background(theme.colors.surfaceRaised)
                .clipShape(Capsule())
                .foregroundColor(theme.colors.textPrimary)
            }
        }
    }

    private func metadata(task: APIProjectTask) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing.s) {
            detailRow(label: "Task ID", value: task.id)
            detailRow(label: "Actor", value: task.actorId)
            detailRow(label: "Claimed By", value: task.claimedActorId ?? task.claimedAgentId)
            detailRow(label: "Created By", value: task.createdBy)
            detailRow(label: "Updated", value: task.updatedAt.map(Self.dateFormatter.string(from:)))

            if let tags = task.tags, !tags.isEmpty {
                detailRow(label: "Tags", value: tags.joined(separator: ", "))
            }
        }
        .padding(theme.spacing.l)
        .background(theme.colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    @ViewBuilder
    private func description(task: APIProjectTask) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing.s) {
            Text("Description")
                .font(.system(size: theme.typography.body))
                .foregroundColor(theme.colors.textPrimary)

            Text(task.description?.isEmpty == false ? task.description! : "No description")
                .font(.system(size: theme.typography.body))
                .foregroundColor(theme.colors.textSecondary)
                .textSelection(.enabled)
        }
        .padding(theme.spacing.l)
        .background(theme.colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private var commentsSection: some View {
        VStack(alignment: .leading, spacing: theme.spacing.m) {
            Text("Comments")
                .font(.system(size: theme.typography.body))
                .foregroundColor(theme.colors.textPrimary)

            if viewModel.comments.isEmpty {
                Text("No comments yet")
                    .font(.system(size: theme.typography.body))
                    .foregroundColor(theme.colors.textMuted)
                    .padding(theme.spacing.l)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(theme.colors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
            } else {
                VStack(alignment: .leading, spacing: theme.spacing.s) {
                    ForEach(viewModel.comments) { comment in
                        VStack(alignment: .leading, spacing: theme.spacing.xs) {
                            HStack {
                                Text(comment.sourceAuthor ?? comment.authorActorId)
                                    .font(.system(size: theme.typography.caption))
                                    .foregroundColor(theme.colors.textPrimary)
                                Spacer(minLength: 0)
                                Text(Self.dateFormatter.string(from: comment.createdAt))
                                    .font(.system(size: theme.typography.micro))
                                    .foregroundColor(theme.colors.textMuted)
                            }

                            Text(comment.content)
                                .font(.system(size: theme.typography.body))
                                .foregroundColor(theme.colors.textSecondary)
                                .textSelection(.enabled)
                        }
                        .padding(theme.spacing.l)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(theme.colors.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                    }
                }
            }
        }
    }

    private func detailRow(label: String, value: String?) -> some View {
        HStack(alignment: .top, spacing: theme.spacing.s) {
            Text(label)
                .font(.system(size: theme.typography.caption))
                .foregroundColor(theme.colors.textMuted)
                .frame(width: 86, alignment: .leading)

            Text(value?.isEmpty == false ? value! : "—")
                .font(.system(size: theme.typography.body))
                .foregroundColor(theme.colors.textSecondary)
                .textSelection(.enabled)

            Spacer(minLength: 0)
        }
    }

    private func taskChip(_ title: String) -> some View {
        Text(title)
            .font(.system(size: theme.typography.micro))
            .foregroundColor(theme.colors.textPrimary)
            .padding(.horizontal, theme.spacing.s)
            .padding(.vertical, theme.spacing.xs)
            .background(theme.colors.surface)
            .clipShape(Capsule())
    }

    private func contentState(title: String, message: String) -> some View {
        VStack(spacing: theme.spacing.m) {
            Text(title)
                .font(.system(size: theme.typography.title))
                .foregroundColor(theme.colors.textPrimary)
            Text(message)
                .font(.system(size: theme.typography.body))
                .foregroundColor(theme.colors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

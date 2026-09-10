import SwiftUI
import SloppyClientCore
import SloppyClientUI

@MainActor
public struct ProjectKanbanView: View {
    let viewModel: ProjectKanbanViewModel
    let projectId: String
    let projectName: String
    let onOpenTask: @MainActor (ProjectKanbanCard) -> Void

    @Environment(\.theme) private var theme
    @State private var filters = ProjectKanbanFilters()
    @State private var isCreateTaskPresented = false

    public init(
        viewModel: ProjectKanbanViewModel,
        projectId: String,
        projectName: String,
        onOpenTask: @escaping @MainActor (ProjectKanbanCard) -> Void = { _ in }
    ) {
        self.viewModel = viewModel
        self.projectId = projectId
        self.projectName = projectName
        self.onOpenTask = onOpenTask
    }

    public var body: some View {
        VStack(spacing: 0) {
            boardToolbar

            Rectangle()
                .fill(theme.colors.border)
                .frame(height: theme.borders.thin)

            if viewModel.isLoading && viewModel.columns.isEmpty {
                ProgressView("Loading board…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage = viewModel.errorMessage {
                boardMessage(
                    title: projectName,
                    message: errorMessage,
                    icon: "exclamationmark.triangle"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.columns.allSatisfy({ $0.items.isEmpty }) {
                emptyProjectState
            } else if filteredColumns.allSatisfy({ $0.items.isEmpty }) {
                noFilterResultsState
            } else {
                GeometryReader { geometry in
                    let contentInset = theme.spacing.l
                    let availableWidth = max(0, geometry.size.width - (contentInset * 2))
                    let availableHeight = max(0, geometry.size.height - (contentInset * 2))

                    ScrollView([.horizontal, .vertical], showsIndicators: false) {
                        HStack(alignment: .top, spacing: theme.spacing.m) {
                            ForEach(filteredColumns) { column in
                                kanbanColumn(column, minHeight: availableHeight)
                            }
                        }
                        .frame(
                            minWidth: availableWidth,
                            minHeight: availableHeight,
                            alignment: .topLeading
                        )
                        .padding(contentInset)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: projectId) {
            await viewModel.load(projectId: projectId)
        }
        .sheet(isPresented: $isCreateTaskPresented) {
            ProjectTaskCreateSheet(
                viewModel: viewModel,
                projectId: projectId,
                projectName: projectName
            )
        }
    }

    private var filteredColumns: [ProjectKanbanColumn] {
        viewModel.columns(matching: filters)
    }

    private var boardToolbar: some View {
        HStack(spacing: theme.spacing.s) {
            HStack(spacing: theme.spacing.s) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(theme.colors.textMuted)

                TextField("Filter tasks", text: $filters.searchText)
                    .textFieldStyle(.plain)
                    .foregroundColor(theme.colors.textPrimary)

                if !filters.searchText.isEmpty {
                    Button {
                        filters.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(theme.colors.textMuted)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear task search")
                }
            }
            .padding(.horizontal, 12)
            .frame(minWidth: 180, idealWidth: 250, maxWidth: 320, minHeight: 38)
            .background(
                theme.colors.surfaceRaised,
                in: RoundedRectangle(cornerRadius: 11, style: .continuous)
            )

            statusMenu
            priorityMenu
            assigneeMenu

            if filters.isActive {
                Button {
                    filters = ProjectKanbanFilters()
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundColor(theme.colors.accentCyan)
                .accessibilityLabel("Reset task filters")
            }

            Spacer(minLength: theme.spacing.s)

            Button {
                isCreateTaskPresented = true
            } label: {
                Label("New Task", systemImage: "plus")
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .tint(Color.accentColor)
            .accessibilityHint("Creates a task in \(projectName)")
        }
        .controlSize(.regular)
        .padding(.horizontal, theme.spacing.l)
        .padding(.vertical, 12)
        .background(theme.colors.surface)
    }

    private var statusMenu: some View {
        Menu {
            Button {
                filters.status = .all
            } label: {
                filterMenuLabel("All statuses", selected: filters.status == .all)
            }

            Divider()

            ForEach(ProjectKanbanColumnID.allCases, id: \.self) { columnID in
                Button {
                    filters.status = .column(columnID)
                } label: {
                    filterMenuLabel(
                        columnID.title,
                        selected: filters.status == .column(columnID)
                    )
                }
            }
        } label: {
            filterChip(
                icon: "circle.grid.2x2",
                title: filters.status.title,
                isActive: filters.status != .all
            )
        }
        .menuStyle(.borderlessButton)
        .accessibilityLabel("Filter tasks by status")
    }

    private var priorityMenu: some View {
        Menu {
            ForEach(ProjectKanbanPriorityFilter.allCases) { priority in
                Button {
                    filters.priority = priority
                } label: {
                    filterMenuLabel(
                        priority.title,
                        selected: filters.priority == priority
                    )
                }
            }
        } label: {
            filterChip(
                icon: "exclamationmark.circle",
                title: filters.priority.title,
                isActive: filters.priority != .all
            )
        }
        .menuStyle(.borderlessButton)
        .accessibilityLabel("Filter tasks by priority")
    }

    private var assigneeMenu: some View {
        Menu {
            Button {
                filters.assignee = .all
            } label: {
                filterMenuLabel("All assignees", selected: filters.assignee == .all)
            }

            Button {
                filters.assignee = .unassigned
            } label: {
                filterMenuLabel("Unassigned", selected: filters.assignee == .unassigned)
            }

            if !viewModel.availableActors.isEmpty {
                Divider()
            }

            ForEach(viewModel.availableActors) { actor in
                Button {
                    filters.assignee = .actor(actor.id)
                } label: {
                    filterMenuLabel(
                        actor.title,
                        selected: filters.assignee == .actor(actor.id)
                    )
                }
            }
        } label: {
            filterChip(
                icon: "person",
                title: viewModel.assigneeTitle(for: filters.assignee),
                isActive: filters.assignee != .all
            )
        }
        .menuStyle(.borderlessButton)
        .accessibilityLabel("Filter tasks by assignee")
    }

    private func filterChip(icon: String, title: String, isActive: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(title)
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .semibold))
        }
        .font(.system(size: theme.typography.caption, weight: .medium))
        .foregroundColor(isActive ? theme.colors.accentCyan : theme.colors.textSecondary)
        .padding(.horizontal, 11)
        .frame(minHeight: 36)
        .background(
            isActive ? theme.colors.accentCyan.opacity(0.10) : theme.colors.surfaceRaised,
            in: Capsule()
        )
        .overlay {
            Capsule()
                .stroke(
                    isActive ? theme.colors.accentCyan.opacity(0.45) : theme.colors.border,
                    lineWidth: theme.borders.thin
                )
        }
    }

    @ViewBuilder
    private func filterMenuLabel(_ title: String, selected: Bool) -> some View {
        if selected {
            Label(title, systemImage: "checkmark")
        } else {
            Text(title)
        }
    }

    private var emptyProjectState: some View {
        VStack(spacing: theme.spacing.m) {
            boardMessage(
                title: "No tasks yet",
                message: "Create the first task for \(projectName).",
                icon: "checklist"
            )

            Button {
                isCreateTaskPresented = true
            } label: {
                Label("Create Task", systemImage: "plus")
            }
            .buttonStyle(.glassProminent)
            .tint(Color.accentColor)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noFilterResultsState: some View {
        VStack(spacing: theme.spacing.m) {
            boardMessage(
                title: "No matching tasks",
                message: "Try changing or clearing the filters.",
                icon: "line.3.horizontal.decrease.circle"
            )

            Button("Clear Filters") {
                filters = ProjectKanbanFilters()
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func boardMessage(title: String, message: String, icon: String) -> some View {
        VStack(spacing: theme.spacing.s) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundColor(theme.colors.textMuted)
            Text(title)
                .font(.system(size: theme.typography.heading, weight: .semibold))
                .foregroundColor(theme.colors.textPrimary)
            Text(message)
                .font(.system(size: theme.typography.body))
                .foregroundColor(theme.colors.textSecondary)
                .multilineTextAlignment(.center)
        }
    }

    private func kanbanColumn(
        _ column: ProjectKanbanColumn,
        minHeight: CGFloat
    ) -> some View {
        let contentMinHeight = max(0, minHeight - (theme.spacing.m * 2))

        return VStack(alignment: .leading, spacing: theme.spacing.s) {
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
                Button {
                    onOpenTask(card)
                } label: {
                    ProjectKanbanCardContent(
                        card: card,
                        columnTitle: column.title,
                        assigneeTitle: card.assigneeID.map { viewModel.assigneeTitle(for: .actor($0)) },
                        instanceTitle: card.executionNodeID.map { viewModel.instanceTitle(for: $0) }
                    )
                }
                .buttonStyle(.plain)
                .contextMenu {
                    if !viewModel.availableInstances.isEmpty {
                        Menu("Run on") {
                            ForEach(viewModel.availableInstances) { instance in
                                Button {
                                    Task {
                                        await viewModel.assignTask(
                                            id: card.id,
                                            to: instance.id,
                                            projectId: projectId
                                        )
                                    }
                                } label: {
                                    if card.executionNodeID == instance.id {
                                        Label(instance.displayName, systemImage: "checkmark")
                                    } else {
                                        Text(instance.displayName)
                                    }
                                }
                            }
                        }
                    }
                }
                .draggable(card.id)
            }

            Spacer(minLength: 0)
        }
        .frame(width: 280, alignment: .topLeading)
        .frame(minHeight: contentMinHeight, alignment: .topLeading)
        .padding(theme.spacing.m)
        .background(theme.colors.surfaceRaised.opacity(0.82 as CGFloat))
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .dropDestination(for: String.self) { taskIDs, _ in
            guard let taskID = taskIDs.first else { return false }
            Task {
                await viewModel.moveTask(id: taskID, to: column.id, projectId: projectId)
            }
            return true
        }
    }
}

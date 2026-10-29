import AdaEngine
import SloppyClientCore
import SloppyClientUI
import SloppyFeatureProjects

struct WorkspaceScreens: View {
    let viewModel: MainViewModel
    @Environment(\.theme) private var theme
    private var model: WorkspaceSurfaceModel { viewModel.surface }

    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 0) {
                if viewModel.navigation.section == .project {
                    HStack(spacing: 8) {
                        ForEach(ProjectWorkspaceSection.allCases, id: \.self) { section in
                            WorkspaceAction(title: section.title, primary: model.projectSection == section) { viewModel.selectProjectSection(section) }
                        }
                    }.padding(.horizontal, 12).frame(height: 44)
                }
                if model.isLoading { Text("Loading…").font(.system(size: 12)).padding(12) }
                if !model.errors.isEmpty {
                    HStack {
                        Text(model.errors.joined(separator: "\n")).font(.system(size: 12)).foregroundColor(theme.colors.statusBlocked).lineLimit(4)
                        Spacer()
                        WorkspaceAction(title: "Retry", icon: .refresh, action: reload)
                    }.padding(12)
                }
                switch viewModel.navigation.section {
                case .scheduled: scheduled
                case .pullRequests: pullRequests
                case .attention: attention
                case .sites: sites
                case .project: project
                default: EmptyView()
                }
            }.foregroundColor(theme.colors.textPrimary)
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
                .accessibilityIdentifier("workspace.screen.\(viewModel.navigation.section.rawValue)")
        }
    }

    private func reload() { Task { await model.load(viewModel.navigation.section, project: viewModel.activeProject) } }
    private var search: some View {
        WorkspaceSearch(placeholder: "Search", value: Binding(get: { model.query }, set: { model.query = $0 }))
    }
    private func heading(_ title: String, subtitle: String, creation: WorkspaceCreation? = nil) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 17, weight: .semibold))
                Text(subtitle).font(.system(size: 12)).foregroundColor(theme.colors.textMuted)
            }
            Spacer()
            if let creation { WorkspaceAction(title: creation == .automation ? "New Automation" : "Create", icon: .add, primary: true) { viewModel.beginCreation(creation) } }
            WorkspaceIconButton(icon: .refresh, action: reload)
        }.padding(18).frame(height: 70).background(theme.colors.surface)
    }

    private var scheduled: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                if geometry.size.width >= 680 || model.selectedScheduled == nil {
                    scheduledList.frame(width: geometry.size.width >= 680 ? 350 : geometry.size.width)
                }
                if geometry.size.width >= 680 { theme.colors.border.frame(width: 1) }
                if geometry.size.width >= 680 || model.selectedScheduled != nil {
                    VStack(alignment: .leading, spacing: 0) {
                        if geometry.size.width < 680 {
                            WorkspaceAction(title: "All scheduled tasks") { model.selectedScheduledID = nil }.padding(16)
                        }
                        scheduledDetail
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    private var scheduledList: some View {
        VStack(alignment: .leading, spacing: 14) {
            heading("Scheduled tasks", subtitle: "\(model.scheduled.filter(\.enabled).count) active · \(model.scheduled.filter { !$0.enabled }.count) paused", creation: .scheduled)
            search.padding(.horizontal, 18)
            WorkspaceFilters(options: ["All", "Active", "Paused"], selection: Binding(get: { model.scheduleFilter.rawValue }, set: { if let filter = ScheduledTaskFilter(rawValue: $0) { model.scheduleFilter = filter } })).padding(.horizontal, 18)
            ScrollView(respectsSafeArea: false) {
                VStack(spacing: 8) {
                    ForEach(model.visibleScheduled) { task in
                        Button { model.selectedScheduledID = task.id } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Icons.symbol(.schedule, size: 22).foregroundColor(theme.colors.statusDone)
                                VStack(alignment: .leading, spacing: 7) {
                                    Text(task.command).font(.system(size: 14, weight: .semibold)).lineLimit(2)
                                    Text(task.schedule).font(.system(size: 12)).foregroundColor(theme.colors.textMuted)
                                    Text("\(task.agentId) · \(task.enabled ? "Active" : "Paused")").font(.system(size: 11)).foregroundColor(theme.colors.textMuted).lineLimit(1)
                                }
                                Spacer(minLength: 0)
                            }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                                .background { RoundedRectangle(cornerRadius: 11).fill(model.selectedScheduledID == task.id ? theme.colors.surfaceRaised : theme.colors.surface) }
                        }.accessibilityIdentifier("workspace.scheduled.\(task.id)")
                    }
                    if !model.isLoading && model.visibleScheduled.isEmpty { Text("No matching scheduled tasks").font(.system(size: 12)).padding(20) }
                }.padding(12)
            }
        }
    }

    @ViewBuilder private var scheduledDetail: some View {
        if let task = model.selectedScheduled {
            ScrollView(respectsSafeArea: false) {
                VStack(alignment: .leading, spacing: 20) {
                    Icons.symbol(.schedule, size: 36).foregroundColor(theme.colors.statusDone)
                    Text("SCHEDULED TASK").font(.system(size: 10, weight: .semibold)).foregroundColor(theme.colors.textMuted)
                    Text(task.command).font(.system(size: 28, weight: .semibold))
                    WorkspacePanel(title: "Schedule") {
                        Text(task.schedule).font(.system(size: 14))
                        Text("Agent: \(task.agentId)\nChannel: \(task.channelId)").font(.system(size: 12)).foregroundColor(theme.colors.textMuted)
                    }
                    WorkspaceAction(title: task.enabled ? "Pause task" : "Resume task", icon: .schedule) { Task { await model.toggleScheduled(task) } }.disabled(model.isSaving)
                }.padding(32).frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            WorkspaceEmpty(icon: .schedule, title: "Select a scheduled task", message: "Its prompt and schedule will appear here.")
        }
    }

    private var pullRequests: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                if geometry.size.width >= 680 || model.selectedReviewID == nil {
                    reviewList.frame(width: geometry.size.width >= 680 ? 330 : geometry.size.width)
                }
                if geometry.size.width >= 680 { theme.colors.border.frame(width: 1) }
                if geometry.size.width >= 680 || model.selectedReviewID != nil {
                    VStack(alignment: .leading, spacing: 0) {
                        if geometry.size.width < 680 {
                            WorkspaceAction(title: "All pull requests") { model.selectedReviewID = nil; model.selectedReview = nil }.padding(16)
                        }
                        reviewDetail
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    private var reviewList: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Pull Requests").font(.system(size: 17, weight: .semibold)).padding(.top, 18)
            WorkspaceFilters(options: ["All", "Reviewing", "Authored"], selection: Binding(get: { model.reviewFilter.rawValue }, set: { if let filter = WorkspaceReviewFilter(rawValue: $0) { model.reviewFilter = filter } }))
            HStack { search; WorkspaceIconButton(icon: .refresh, action: reload) }
            Text("\(model.visibleReviews.count) pull requests").font(.system(size: 11)).foregroundColor(theme.colors.textMuted)
            ScrollView(respectsSafeArea: false) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(model.visibleReviews) { item in
                        Button { Task { await model.openReview(item) } } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Icons.symbol(.branch, size: 17).foregroundColor(theme.colors.statusDone)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(item.title).font(.system(size: 13, weight: .semibold)).lineLimit(3)
                                    Text("\(item.repository) · \(item.providerName) · \(item.author ?? "")").font(.system(size: 10)).foregroundColor(theme.colors.textMuted).lineLimit(2)
                                    if item.isDraft { Text("Draft").font(.system(size: 10)).padding(4).background(theme.colors.surfaceRaised) }
                                }
                                Spacer(minLength: 0)
                            }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                                .background { RoundedRectangle(cornerRadius: 8).fill(model.selectedReviewID == item.id ? theme.colors.surfaceRaised : .clear) }
                        }.accessibilityIdentifier("workspace.review.\(item.id)")
                    }
                }
            }
        }.padding(.horizontal, 14)
    }

    @ViewBuilder private var reviewDetail: some View {
        if model.isLoadingReview {
            WorkspaceEmpty(icon: .branch, title: "Loading review…", message: "Fetching comments and code changes.")
        } else if let review = model.selectedReview {
            ScrollView(respectsSafeArea: false) {
                VStack(alignment: .leading, spacing: 20) {
                    Text(review.item.title).font(.system(size: 25, weight: .semibold))
                    Text("\(review.sourceBranch ?? "") → \(review.targetBranch ?? "")").font(.system(size: 12)).foregroundColor(theme.colors.textMuted)
                    if let description = review.description { Text(description).font(.system(size: 14)) }
                    if let error = review.commentsError { Text(error).font(.system(size: 12)).foregroundColor(theme.colors.statusBlocked) }
                    ForEach(review.comments) { comment in
                        WorkspacePanel(title: comment.author ?? "Comment") { Text(comment.body).font(.system(size: 13)) }
                    }
                    Text("Code changes").font(.system(size: 17, weight: .semibold))
                    if let error = review.diffError { Text(error).font(.system(size: 12)).foregroundColor(theme.colors.statusBlocked) }
                    Text(review.diff).font(.system(size: 12))
                    if review.diffTruncated { Text("The server truncated this diff.").font(.system(size: 12)).foregroundColor(theme.colors.textMuted) }
                }.padding(28).frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            WorkspaceEmpty(icon: .branch, title: "Select a Pull Request", message: "Review comments and code changes will appear here.")
        }
    }

    private var attention: some View {
        VStack(spacing: 0) {
            heading("Attention", subtitle: "\(model.unreadCount) unread")
            search.padding(18)
            if model.visibleFindings.isEmpty && !model.isLoading && model.errors.isEmpty {
                WorkspaceEmpty(icon: .notification, title: "All caught up", message: "Updates that need your attention will appear here.")
            } else {
                ScrollView(respectsSafeArea: false) {
                    VStack(spacing: 12) {
                        ForEach(model.visibleFindings) { finding in
                            WorkspacePanel(title: finding.source.title) {
                                Text(finding.reason).font(.system(size: 16, weight: .semibold))
                                Text(finding.evidence).font(.system(size: 13)).foregroundColor(theme.colors.textSecondary)
                                Text(finding.nextStep).font(.system(size: 13))
                                HStack {
                                    if let session = viewModel.catalogSessions.first(where: { $0.id == finding.sessionId && $0.agentId == finding.agentId }) {
                                        WorkspaceAction(title: "Open chat", icon: .chatAddOn) { viewModel.selectChatSession(session) }
                                    }
                                    if finding.readAt == nil { WorkspaceAction(title: "Mark read") { Task { await model.act(finding, action: .read) } } }
                                    WorkspaceAction(title: "Snooze") { Task { await model.act(finding, action: .snooze) } }
                                    WorkspaceAction(title: "Dismiss") { Task { await model.act(finding, action: .dismiss) } }
                                }.disabled(model.isSaving)
                            }
                        }
                    }.padding(18)
                }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var sites: some View {
        VStack(spacing: 0) {
            heading("Sites", subtitle: "\(model.sites.count) published sites")
            search.padding(18)
            if model.sites.isEmpty && !model.isLoading && model.errors.isEmpty {
                WorkspaceEmpty(icon: .language, title: "No sites yet", message: "Sites published by your agents will appear here.")
            } else {
                ScrollView(respectsSafeArea: false) {
                    VStack(spacing: 12) {
                        ForEach(model.sites.filter { model.matches($0.title) }) { site in
                            WorkspacePanel(title: site.title) {
                                Text(site.path).font(.system(size: 13))
                                Text("\(site.visibility.rawValue) · revision \(site.revision)").font(.system(size: 12)).foregroundColor(theme.colors.textMuted)
                                WorkspaceAction(title: "Copy site URL", icon: .language) {
                                    if let url = URL(string: site.path, relativeTo: viewModel.baseURL) { UIClipboard.setString(url.absoluteURL.absoluteString) }
                                }
                            }
                        }
                    }.padding(18)
                }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder private var project: some View {
        if let project = viewModel.workspaceProject {
            switch model.projectSection {
            case .kanban: ProjectKanban(viewModel: viewModel, project: project)
            case .chats:
                VStack(spacing: 0) {
                    HStack {
                        Text("Chats in \(project.name)").font(.system(size: 17, weight: .semibold))
                        Spacer()
                        WorkspaceAction(title: "New chat", icon: .add, primary: true) { viewModel.newProjectChat(project) }
                    }.padding(20)
                    ScrollView(respectsSafeArea: false) {
                        VStack(spacing: 8) {
                            ForEach(viewModel.sidebarContent.sessions(in: project.id)) { session in
                                Button { viewModel.selectChatSession(session) } label: {
                                    Text(session.title).font(.system(size: 14)).padding(16).frame(maxWidth: .infinity, alignment: .leading).background(theme.colors.surfaceRaised)
                                }
                            }
                        }.padding(20)
                    }
                }
            case .workspaces:
                if model.canvas.workspace != nil {
                    WorkspaceCanvasEditor(model: model.canvas) { viewModel.openCanvasChat() }
                }
                else { projectWorkspaces(project) }
            case .automation: projectAutomations(project)
            }
        } else {
            WorkspaceEmpty(icon: .folder, title: "Select a project", message: "Choose a project in the sidebar.")
        }
    }

    private func projectWorkspaces(_ project: APIProjectRecord) -> some View {
        VStack(spacing: 0) {
            heading("Canvases in \(project.name)", subtitle: "\(model.canvases.count) workspaces", creation: .canvas)
            search.padding(18)
            if model.canvases.isEmpty && !model.isLoading && model.errors.isEmpty {
                VStack(spacing: 0) {
                    Spacer()
                    WorkspaceEmpty(icon: .grid, title: "No Canvases", message: "Create a native canvas for notes, sketches, and agent-built artifacts.").frame(maxHeight: 200)
                    WorkspaceAction(title: "Create Workspace", primary: true) { viewModel.beginCreation(.canvas) }
                    Spacer()
                }
            } else {
                ScrollView(respectsSafeArea: false) {
                    VStack(spacing: 12) {
                        ForEach(model.canvases.filter { model.matches($0.title) }) { canvas in
                            WorkspacePanel(title: canvas.title) {
                                Text(canvas.description).font(.system(size: 13))
                                Text("Revision \(canvas.revision)").font(.system(size: 11)).foregroundColor(theme.colors.textMuted)
                                WorkspaceAction(title: "Open canvas", icon: .grid, primary: true) { Task { await model.canvas.open(canvas) } }
                            }
                        }
                    }.padding(18)
                }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    private func projectAutomations(_ project: APIProjectRecord) -> some View {
        VStack(spacing: 0) {
            heading("Automations", subtitle: "\(model.automations.count) in \(project.name)", creation: .automation)
            if model.automations.isEmpty && !model.isLoading && model.errors.isEmpty {
                VStack(spacing: 0) {
                    Spacer()
                    WorkspaceEmpty(icon: .settings, title: "No automations yet", message: "Create the first automation for \(project.name).").frame(maxHeight: 200)
                    WorkspaceAction(title: "New Automation", icon: .add, primary: true) { viewModel.beginCreation(.automation) }
                    Spacer()
                }
            } else {
                ScrollView(respectsSafeArea: false) {
                    VStack(spacing: 12) {
                        ForEach(model.automations) { automation in
                            WorkspacePanel(title: automation.name) {
                                Text("\(automation.trigger.type.title) · \(automation.enabled ? "Active" : "Paused")").font(.system(size: 13))
                                Text(automation.repositoryFullName).font(.system(size: 12)).foregroundColor(theme.colors.textMuted)
                                WorkspaceAction(title: model.runningAutomationIDs.contains(automation.id) ? "Starting…" : "Run now", icon: .arrowForward, primary: true) {
                                    Task { await model.runAutomation(automation) }
                                }.disabled(!automation.enabled || model.runningAutomationIDs.contains(automation.id))
                                    .accessibilityIdentifier("workspace.automation.run.\(automation.id)")
                                ForEach(model.automationRuns.filter { $0.automationId == automation.id }) { run in
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack {
                                            Text(run.status.title).font(.system(size: 13, weight: .semibold))
                                                .foregroundColor(run.status == .failed ? theme.colors.statusBlocked : theme.colors.statusDone)
                                            Spacer()
                                            Text(run.startedAt.formatted()).font(.system(size: 11))
                                        }
                                        if let summary = run.summary { Text(markdown: summary).textSelection(.enabled).font(.system(size: 12)) }
                                        if let task = run.taskId { Text("Task: \(task)").textSelection(.enabled).font(.system(size: 11)) }
                                        Text(run.id).textSelection(.enabled).font(.system(size: 10)).foregroundColor(theme.colors.textMuted)
                                    }.padding(10).background(theme.colors.surfaceRaised)
                                }
                            }
                        }
                    }.padding(18)
                }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct ProjectKanban: View {
    let viewModel: MainViewModel
    let project: APIProjectRecord
    @Environment(\.theme) private var theme
    @State private var selectedTask: APIProjectTask?
    private let columns = ["backlog", "ready", "in_progress", "needs_review", "done", "other"]
    private func title(_ column: String) -> String {
        switch column { case "in_progress": "In Progress"; case "needs_review": "Needs Review"; default: column.capitalized }
    }
    private func tasks(_ column: String) -> [APIProjectTask] {
        (project.tasks ?? []).filter { column == "other" ? !columns.dropLast().contains($0.status) : $0.status == column }
    }
    var body: some View {
        if let task = selectedTask {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    WorkspaceAction(title: "Back to Kanban", icon: .close) { selectedTask = nil }
                    Spacer()
                    WorkspaceAction(title: "Open chat", icon: .chatAddOn) {
                        viewModel.selectTask(projectId: project.id, projectName: project.name, task: task, fallbackAgentId: project.actors?.first)
                    }
                }.padding(16)
                ProjectTaskDetailView(projectId: project.id, task: task, apiClient: SloppyAPIClient(baseURL: viewModel.baseURL)) { updated in
                    viewModel.workspaceProject = updated
                    if let index = viewModel.projects.firstIndex(where: { $0.id == updated.id }) { viewModel.projects[index] = updated }
                    selectedTask = updated.tasks?.first { $0.id == task.id }
                }
                    .id(task.id)
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            board
        }
    }
    private var board: some View {
        ScrollView(.horizontal, respectsSafeArea: false) {
            HStack(alignment: .top, spacing: 16) {
                ForEach(columns, id: \.self) { column in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(title(column)).font(.system(size: 14, weight: .semibold))
                            Spacer()
                            Text("\(tasks(column).count)").font(.system(size: 12)).foregroundColor(theme.colors.textMuted)
                        }.frame(height: 24)
                        ScrollView(respectsSafeArea: false) {
                            VStack(spacing: 10) {
                                ForEach(tasks(column)) { task in
                                    Button {
                                        selectedTask = task
                                    } label: {
                                        VStack(alignment: .leading, spacing: 10) {
                                            Text("# \(task.id)").font(.system(size: 11)).foregroundColor(theme.colors.textMuted).lineLimit(1)
                                            Text(task.title).font(.system(size: 14, weight: .semibold))
                                            if let priority = task.priority { Text(priority.capitalized).font(.system(size: 11)).foregroundColor(theme.colors.statusWarning) }
                                            if let actor = task.actorId { Text(actor).font(.system(size: 11)).foregroundColor(theme.colors.textMuted) }
                                            if let tags = task.tags, !tags.isEmpty { Text(tags.joined(separator: " · ")).font(.system(size: 11)).foregroundColor(theme.colors.accentCyan) }
                                        }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                                            .background { RoundedRectangle(cornerRadius: 12).fill(theme.colors.background) }
                                    }.accessibilityIdentifier("workspace.task.\(task.id)")
                                }
                            }
                        }
                    }.padding(14).frame(width: 280).frame(maxHeight: .infinity, alignment: .top)
                        .background { RoundedRectangle(cornerRadius: 20).fill(theme.colors.surfaceRaised) }
                }
            }.padding(20)
        }
    }
}

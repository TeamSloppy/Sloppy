import AdaEngine
import SloppyClientCore
import SloppyClientUI

struct WorkspaceInspector: View {
    let viewModel: MainViewModel
    @Environment(\.theme) private var theme
    @State private var showsTools = false
    private var model: WorkspaceSurfaceModel { viewModel.surface }
    var body: some View {
        ScrollView(respectsSafeArea: false) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Button { showsTools.toggle() } label: {
                        HStack(spacing: 4) {
                            Icons.symbol(.add, size: 15)
                            Text("Tools").font(.system(size: 13))
                            Icons.symbol(.expandMore, size: 12)
                        }.foregroundColor(theme.colors.textPrimary)
                    }
                    Spacer()
                    Text("Workspace").font(.system(size: 10)).foregroundColor(theme.colors.textMuted)
                }.frame(height: 28)
                if showsTools {
                    WorkspaceAction(title: "Browser", icon: .language) { model.tool = .browser; showsTools = false }
                    WorkspaceAction(title: "Terminal", icon: .terminal) { model.tool = .terminal; showsTools = false }
                    WorkspaceAction(title: "Review", icon: .code) { model.tool = .review; showsTools = false }
                    if let project = viewModel.activeProject {
                        WorkspaceAction(title: "Files", icon: .folder) {
                            showsTools = false
                            Task { await model.openFiles(project: project) }
                        }
                    }
                }
                if let project = viewModel.activeProject {
                    WorkspacePanel(title: project.name) {
                        ForEach(ProjectWorkspaceSection.allCases, id: \.self) { section in
                            Button { viewModel.selectProjectSection(section) } label: {
                                HStack(spacing: 10) {
                                    Icons.symbol(icon(section), size: 16)
                                    Text(section.title).font(.system(size: 12))
                                    Spacer()
                                    if viewModel.navigation.section == .project && model.projectSection == section {
                                        Icons.symbol(.check, size: 14)
                                    }
                                }.foregroundColor(theme.colors.textSecondary).padding(.horizontal, 8).frame(height: 29)
                                    .background { RoundedRectangle(cornerRadius: 7).fill(viewModel.navigation.section == .project && model.projectSection == section ? theme.colors.surfaceRaised : .clear) }
                            }.accessibilityIdentifier("workspace.project.\(section.rawValue)")
                        }
                    }
                }
                WorkspacePanel(title: "Environment") {
                    detail(.computer, viewModel.baseURL.host ?? "Local", viewModel.baseURL.absoluteString)
                    if let project = viewModel.activeProject {
                        detail(.folder, project.name, project.projectRootPath ?? "Workspace path unavailable")
                        detail(.branch, model.sourceControl?.branch ?? "Unknown branch", model.sourceControl?.providerId ?? "Source control")
                        WorkspaceAction(title: "Browse project files", icon: .folder) {
                            Task { await model.openFiles(project: project) }
                        }
                    } else {
                        Text("Personal workspace").font(.system(size: 12)).foregroundColor(theme.colors.textMuted)
                    }
                }
                WorkspacePanel(title: "Context") {
                    Text(viewModel.chatViewModel.activeContextTitle ?? "Current context unknown")
                        .font(.system(size: 11)).foregroundColor(theme.colors.textMuted)
                    Text(viewModel.chatViewModel.selectedAgent?.displayName ?? "No agent selected")
                        .font(.system(size: 11)).foregroundColor(theme.colors.textMuted)
                }
                if viewModel.activeProject != nil { changes }
            }.padding(.horizontal, 12).padding(.bottom, 16)
        }
        .accessibilityIdentifier("workspace.inspector")
    }

    private var changes: some View {
        WorkspacePanel(title: "Changes") {
            if let source = model.sourceControl {
                HStack {
                    Text("+\(source.linesAdded)").foregroundColor(theme.colors.statusDone)
                    Text("−\(source.linesDeleted)").foregroundColor(theme.colors.statusBlocked)
                    Spacer()
                    WorkspaceIconButton(icon: .refresh) { Task { await model.loadSourceControl(project: viewModel.activeProject) } }
                }.font(.system(size: 12, weight: .semibold))
                if !source.hasChanges {
                    Text(source.message ?? "No uncommitted changes").font(.system(size: 11)).foregroundColor(theme.colors.textMuted)
                }
                ForEach(source.fileChanges) { file in
                    Button { model.tool = .review } label: {
                        HStack(spacing: 6) {
                            Text(file.path).font(.system(size: 10)).lineLimit(1).foregroundColor(theme.colors.textSecondary)
                            Spacer(minLength: 0)
                            Text("+\(file.linesAdded)").foregroundColor(theme.colors.statusDone)
                            Text("−\(file.linesDeleted)").foregroundColor(theme.colors.statusBlocked)
                        }.font(.system(size: 10)).frame(height: 22)
                    }
                }
            } else {
                Text(model.sourceControlError ?? "Loading source control…").font(.system(size: 11)).foregroundColor(theme.colors.textMuted)
                WorkspaceAction(title: "Refresh", icon: .refresh) { Task { await model.loadSourceControl(project: viewModel.activeProject) } }
            }
        }
    }

    private func detail(_ icon: MaterialSymbol, _ title: String, _ subtitle: String) -> some View {
        HStack(spacing: 10) {
            Icons.symbol(icon, size: 18).foregroundColor(theme.colors.textMuted)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 14)).foregroundColor(theme.colors.textPrimary).lineLimit(1)
                Text(subtitle).font(.system(size: 10)).foregroundColor(theme.colors.textMuted).lineLimit(2)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func icon(_ section: ProjectWorkspaceSection) -> MaterialSymbol {
        switch section { case .kanban: .dashboard; case .workspaces: .grid; case .automation: .settings; case .chats: .chatAddOn }
    }
}

struct WorkspaceToolPanel: View {
    let viewModel: MainViewModel
    @Environment(\.theme) private var theme
    private var model: WorkspaceSurfaceModel { viewModel.surface }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(model.tool?.title ?? "Tools").font(.system(size: 14, weight: .semibold))
                Spacer()
                WorkspaceIconButton(icon: .close) { model.tool = nil }
            }.padding(.horizontal, 14).frame(height: 44)
            if let error = model.toolError { Text(error).font(.system(size: 12)).foregroundColor(theme.colors.statusBlocked).padding(14) }
            if model.tool == .review {
                ScrollView(respectsSafeArea: false) {
                    Text(model.sourceControl?.diff.isEmpty == false ? model.sourceControl?.diff ?? "" : "No working-tree diff available.")
                        .textSelection(.enabled)
                        .font(.system(size: 12)).padding(14).frame(maxWidth: .infinity, alignment: .leading)
                }
            } else if model.tool == .terminal {
                WorkspaceTerminalPanel(session: viewModel.terminal, projectPath: viewModel.activeProject?.projectRootPath).padding(.horizontal, 10)
            } else if model.tool == .browser {
                WorkspaceBrowserPanel(model: viewModel.browser)
                    .id(viewModel.navigation.selectedTabID)
                    .onAppear {
                        let browser = viewModel.browser
                        browser.bind(service: model.api.workspace, agentID: viewModel.chatViewModel.selectedAgent?.id,
                                     sessionID: viewModel.chatViewModel.selectedSessionId)
                        Task { if let config = try? await model.api.fetchConfig() { browser.executable = config.browser.executablePath } }
                    }
            } else if let project = viewModel.activeProject {
                WorkspaceAction(title: "Project root", icon: .folder) { Task { await model.openFiles(project: project) } }.padding(.horizontal, 14)
                WorkspaceSearch(placeholder: "Search project files", value: Binding(get: { model.fileSearchQuery }, set: {
                    model.fileSearchQuery = $0
                    model.searchFiles(project: project)
                })).padding(.horizontal, 14).accessibilityIdentifier("workspace.files.search")
                Text(model.fileContent?.path ?? model.filePath).font(.system(size: 11)).padding(.horizontal, 14).lineLimit(2)
                if model.isSearchingFiles { Text("Searching…").font(.system(size: 12)).padding(.horizontal, 14) }
                ScrollView(respectsSafeArea: false) {
                    if let file = model.fileContent {
                        Text(file.content).textSelection(.enabled).font(.system(size: 12)).padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    } else if !model.fileSearchQuery.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(model.fileSearchResults, id: \.path) { entry in
                                Button { Task { await model.openFile(ProjectFileEntry(name: entry.path, path: entry.path, type: entry.type), project: project) } } label: {
                                    Text(entry.path).font(.system(size: 12)).padding(12).frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            if !model.isSearchingFiles && model.fileSearchResults.isEmpty { Text("No matching files").font(.system(size: 12)).padding(14) }
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(model.files, id: \.name) { entry in
                                Button { Task { await model.openFile(entry, project: project) } } label: {
                                    HStack(spacing: 10) {
                                        Icons.symbol(entry.type == .directory ? .folder : .description, size: 16)
                                        Text(entry.name).font(.system(size: 12)).lineLimit(1)
                                        Spacer()
                                    }.padding(.horizontal, 14).frame(height: 32)
                                }
                            }
                        }
                    }
                }
            }
        }.foregroundColor(theme.colors.textPrimary).frame(maxHeight: .infinity, alignment: .topLeading)
            .background(theme.colors.surface).accessibilityIdentifier("workspace.tool")
    }
}

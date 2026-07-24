import Foundation
import Testing

@Suite("Main sidebar project sessions")
struct MainSidebarProjectSessionsTests {
    private var source: String {
        get throws {
            try sourceFile("Sources/SloppyClient/Navigation/Shared/SidebarRecentsList.swift")
        }
    }

    private func sourceFile(_ relativePath: String) throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: packageRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    @Test("project groups are built from chat sessions with messages")
    func projectGroupsAreBuiltFromChatSessionsWithMessages() throws {
        let source = try source
        let mainViewModelSource = try sourceFile("Sources/SloppyClient/Navigation/Main/MainViewModel.swift")

        #expect(source.contains("ChatSidebarSections.build("))
        #expect(source.contains("sessions: viewModel.chatViewModel.sessionCatalog"))
        #expect(mainViewModelSource.contains("loadsGlobalSessionCatalog: true"))
        #expect(source.contains("ForEach(sections.projectGroups.prefix(viewModel.visibleProjectCount))"))
        #expect(source.contains("ForEach(sessions)"))
    }

    @Test("project list reveals additional projects in pages")
    func projectListRevealsAdditionalProjectsInPages() throws {
        let source = try source

        #expect(source.contains("sections.projectGroups.prefix(viewModel.visibleProjectCount)"))
        #expect(source.contains("Button(\"Show more project\")"))
        #expect(source.contains("viewModel.showMoreProjects()"))
    }

    @Test("project and recents session rows open session-backed tabs")
    func projectAndRecentsSessionRowsOpenSessionBackedTabs() throws {
        let source = try source

        #expect(source.contains("viewModel.openSessionChatTab(session)"))
        #expect(!source.contains("viewModel.selectChatSession(session)"))
    }

    @Test("project row reveals a project-scoped new chat action on hover")
    func projectRowRevealsProjectScopedNewChatActionOnHover() throws {
        let sidebarSource = try source
        let mainViewModelSource = try sourceFile("Sources/SloppyClient/Navigation/Main/MainViewModel.swift")

        #expect(sidebarSource.contains("viewModel.showNewProjectChat(project: group.project)"))
        #expect(sidebarSource.contains("Icons.symbol(.chatAddOn"))
        #expect(sidebarSource.contains(".opacity(Double(isHovered ? 1 : 0))"))
        #expect(sidebarSource.contains(".help(\"New chat\")"))

        let methodStart = try #require(mainViewModelSource.range(of: "func showNewProjectChat(project: APIProjectRecord)"))
        let nextMethod = try #require(
            mainViewModelSource.range(
                of: "func selectTask(",
                range: methodStart.upperBound..<mainViewModelSource.endIndex
            )
        )
        let methodSource = mainViewModelSource[methodStart.lowerBound..<nextMethod.lowerBound]

        #expect(methodSource.contains("context: .project("))
        #expect(methodSource.contains("opensPreferredSession: false"))
        #expect(methodSource.contains("loadInitialData: true"))
        #expect(methodSource.contains("showInSelectedTab("))
        #expect(!methodSource.contains("tabs.append(tab)"))
    }

    @Test("project navigation reuses the current tab while explicit tab creation appends")
    func projectNavigationReusesCurrentTabWhileExplicitCreationAppends() throws {
        let mainViewModelSource = try sourceFile("Sources/SloppyClient/Navigation/Main/MainViewModel.swift")

        let projectStart = try #require(mainViewModelSource.range(of: "func openProjectKanbanTab(project: APIProjectRecord)"))
        let projectEnd = try #require(
            mainViewModelSource.range(
                of: "func showNewProjectChat(",
                range: projectStart.upperBound..<mainViewModelSource.endIndex
            )
        )
        let projectMethod = mainViewModelSource[projectStart.lowerBound..<projectEnd.lowerBound]

        #expect(projectMethod.contains("showInSelectedTab("))
        #expect(!projectMethod.contains("tabs.append(tab)"))

        let createStart = try #require(mainViewModelSource.range(of: "func createBlankChatTab(select: Bool = true)"))
        let createEnd = try #require(
            mainViewModelSource.range(
                of: "func showBlankChatInSelectedTab()",
                range: createStart.upperBound..<mainViewModelSource.endIndex
            )
        )
        let createMethod = mainViewModelSource[createStart.lowerBound..<createEnd.lowerBound]

        #expect(createMethod.contains("tabs.append(tab)"))
        #expect(createMethod.contains("selectedTabID = tab.id"))

        #expect(mainViewModelSource.contains("private func showInSelectedTab(_ tab: WorkspaceTab, state: WorkspaceTabState)"))
        #expect(mainViewModelSource.contains("id: selectedTabID"))
        #expect(mainViewModelSource.contains("tabStates[selectedTabID] = state"))
    }

    @Test("new projects open a scoped chat and project rows support drag reordering")
    func newProjectsOpenAScopedChatAndProjectRowsSupportDragReordering() throws {
        let sidebarSource = try source
        let mainViewModelSource = try sourceFile("Sources/SloppyClient/Navigation/Main/MainViewModel.swift")

        #expect(sidebarSource.contains(".draggable(group.id)"))
        #expect(sidebarSource.contains(".dropDestination(for: String.self)"))
        #expect(sidebarSource.contains("viewModel.moveProject(projectID, relativeTo: group.id)"))

        let saveStart = try #require(mainViewModelSource.range(of: "func didSaveProject(_ project: APIProjectRecord)"))
        let saveEnd = try #require(
            mainViewModelSource.range(
                of: "func showNewProjectChat(",
                range: saveStart.upperBound..<mainViewModelSource.endIndex
            )
        )
        let saveMethod = mainViewModelSource[saveStart.lowerBound..<saveEnd.lowerBound]

        #expect(saveMethod.contains("projects.insert(project, at: 0)"))
        #expect(saveMethod.contains("showNewProjectChat(project: project)"))
        #expect(saveMethod.contains("persistProjectOrder()"))
    }
}

import Foundation
import Testing

@Suite("Main tabs source")
struct MainTabsSourceTests {
    private func source(_ relativePath: String) throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: packageRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    @Test("main tabs domain defines kinds payloads and semantic keys")
    func mainTabsDomainDefinesKindsPayloadsAndSemanticKeys() throws {
        let tabs = try source("Sources/SloppyClient/Navigation/Main/MainTabs.swift")

        #expect(tabs.contains("enum WorkspaceTabKind: String, Hashable"))
        #expect(tabs.contains("case chat"))
        #expect(tabs.contains("case projectKanban"))
        #expect(tabs.contains("case taskDetail"))
        #expect(tabs.contains("case workspaceFiles"))
        #expect(tabs.contains("enum WorkspaceTabKey: Hashable"))
        #expect(tabs.contains("case chatSession(String)"))
        #expect(tabs.contains("case chatTask(projectId: String, taskId: String)"))
        #expect(tabs.contains("case chatTask(projectId: String, projectName: String, projectRootPath: String?"))
        #expect(tabs.contains("case projectKanban(String)"))
        #expect(tabs.contains("case taskDetail(projectId: String, taskId: String)"))
        #expect(tabs.contains("case workspaceFiles(String)"))
    }

    @Test("main view model owns tabs and open close selection helpers")
    func mainViewModelOwnsTabsAndOpenCloseSelectionHelpers() throws {
        let mainView = try source("Sources/SloppyClient/Navigation/Main/MainView.swift")

        #expect(mainView.contains("var tabs: [WorkspaceTab] = []"))
        #expect(mainView.contains("var selectedTabID: WorkspaceTab.ID?"))
        #expect(mainView.contains("var desktopSplitState: DesktopTabSplitState?"))
        #expect(mainView.contains("func openProjectKanbanTab(project: APIProjectRecord)"))
        #expect(mainView.contains("func openTaskChatTab("))
        #expect(mainView.contains("func openTaskDetailTab(project: APIProjectRecord, task: APIProjectTask, fallbackAgentId: String?)"))
        #expect(mainView.contains("func openSessionChatTab(_ session: ChatSessionSummary)"))
        #expect(mainView.contains("func closeTab(_ tabID: WorkspaceTab.ID)"))
        #expect(mainView.contains("func selectTab(_ tabID: WorkspaceTab.ID)"))
    }

    @Test("main view model exposes blank tab and adjacent navigation helpers")
    func mainViewModelExposesBlankTabAndAdjacentNavigationHelpers() throws {
        let mainView = try source("Sources/SloppyClient/Navigation/Main/MainView.swift")

        #expect(mainView.contains("var isMobileTabsOverviewPresented = false"))
        #expect(mainView.contains("var isVisionTabsOverviewPresented = false"))
        #expect(mainView.contains("func createBlankChatTab(select: Bool = true)"))
        #expect(mainView.contains("func selectAdjacentTab(offset: Int)"))
        #expect(mainView.contains("func nextTabID(from tabID: WorkspaceTab.ID, offset: Int) -> WorkspaceTab.ID?"))
        #expect(mainView.contains("func presentMobileTabsOverview()"))
        #expect(mainView.contains("func dismissMobileTabsOverview()"))
        #expect(mainView.contains("func presentVisionTabsOverview()"))
        #expect(mainView.contains("func dismissVisionTabsOverview()"))
    }

    @Test("new chat sidebar action opens a selected blank chat tab")
    func newChatSidebarActionOpensASelectedBlankChatTab() throws {
        let mainViewModel = try source("Sources/SloppyClient/Navigation/Main/MainViewModel.swift")
        let start = try #require(mainViewModel.range(of: "func selectNewChat()"))
        let end = try #require(
            mainViewModel.range(
                of: "func selectChatSession",
                range: start.upperBound..<mainViewModel.endIndex
            )
        )
        let method = mainViewModel[start.lowerBound..<end.lowerBound]

        #expect(method.contains("createBlankChatTab(select: true)"))
        #expect(!method.contains("routePrimaryChat(.blank)"))
    }

    @Test("main view uses extracted desktop workspace tab strip")
    func mainViewUsesExtractedDesktopWorkspaceTabStrip() throws {
        let mainView = try source("Sources/SloppyClient/Navigation/Main/MainView.swift")
        let strip = try source("Sources/SloppyClient/Navigation/Tabs/DesktopWorkspaceTabStrip.swift")

        #expect(mainView.contains("private func tabChromeHost() -> some View"))
        #expect(mainView.contains("DesktopWorkspaceTabStrip(viewModel: viewModel)"))
        #expect(mainView.contains("DesktopSplitHandle("))
        #expect(strip.contains("struct DesktopWorkspaceTabStrip: View"))
        #expect(strip.contains("viewModel.createBlankChatTab()"))
        #expect(strip.contains("viewModel.closeTab(tab.id)"))
    }

    @Test("vision tab chrome is extracted into a dedicated floating view")
    func visionTabChromeIsExtractedIntoADedicatedFloatingView() throws {
        let mainView = try source("Sources/SloppyClient/Navigation/Main/MainView.swift")
        let floatingView = try source("Sources/SloppyClient/Navigation/Tabs/VisionFloatingTabBarView.swift")

        #expect(mainView.contains("VisionFloatingTabBarView(viewModel: viewModel)"))
        #expect(floatingView.contains("struct VisionFloatingTabBarView: View"))
        #expect(floatingView.contains("viewModel.createBlankChatTab()"))
        #expect(floatingView.contains("viewModel.closeTab(tab.id)"))
        #expect(floatingView.contains(".backportGlassEffect("))
        #expect(floatingView.contains("let onOpenOverview: @MainActor () -> Void"))
        #expect(floatingView.contains("onOpenOverview()"))
    }

    @Test("vision floating tab bar compresses and blurs tabs near the edges")
    func visionFloatingTabBarCompressesAndBlursEdgeTabs() throws {
        let floatingView = try source("Sources/SloppyClient/Navigation/Tabs/VisionFloatingTabBarView.swift")

        #expect(floatingView.contains(".visualEffect { effect, proxy in"))
        #expect(floatingView.contains(".blur(radius:"))
        #expect(floatingView.contains(".scaleEffect(x:"))
        #expect(floatingView.contains("edgeBlurRadius("))
        #expect(floatingView.contains("edgeCompression("))
    }

    @Test("desktop workspace strip uses safari glass gradients instead of flat fill")
    func desktopWorkspaceStripUsesSafariGlassGradientsInsteadOfFlatFill() throws {
        let strip = try source("Sources/SloppyClient/Navigation/Tabs/DesktopWorkspaceTabStrip.swift")

        #expect(strip.contains("safariGlassBarBackground"))
        #expect(strip.contains("safariSelectedTabFill"))
        #expect(strip.contains("LinearGradient("))
        #expect(!strip.contains(".background(theme.colors.surface.opacity(0.82 as CGFloat))"))
    }

    @Test("desktop workspace strip animates and scrolls to newly created tabs")
    func desktopWorkspaceStripAnimatesAndScrollsToNewlyCreatedTabs() throws {
        let strip = try source("Sources/SloppyClient/Navigation/Tabs/DesktopWorkspaceTabStrip.swift")

        #expect(strip.contains("ScrollViewReader { proxy in"))
        #expect(strip.contains("@State private var previousTabIDs: [WorkspaceTab.ID] = []"))
        #expect(strip.contains(".scrollTo(tabID, anchor: .trailing)"))
        #expect(strip.contains(".onChange(of: viewModel.tabs.map(\\.id))"))
        #expect(strip.contains(".transition("))
        #expect(strip.contains(".asymmetric("))
    }

    @Test("desktop workspace strip sizes tabs to fill available width down to a minimum")
    func desktopWorkspaceStripSizesTabsToFillAvailableWidthDownToAMinimum() throws {
        let strip = try source("Sources/SloppyClient/Navigation/Tabs/DesktopWorkspaceTabStrip.swift")

        #expect(strip.contains("GeometryReader { geometry in"))
        #expect(strip.contains("private let minimumTabWidth: CGFloat = 120"))
        #expect(strip.contains("private func tabWidth(for availableWidth: CGFloat) -> CGFloat"))
        #expect(strip.contains("max(minimumTabWidth"))
        #expect(strip.contains(".frame(width: tabWidth"))
    }

    @Test("desktop workspace strip keeps a compact fixed-height chrome")
    func desktopWorkspaceStripKeepsACompactFixedHeightChrome() throws {
        let strip = try source("Sources/SloppyClient/Navigation/Tabs/DesktopWorkspaceTabStrip.swift")

        #expect(strip.contains("private let stripHeight: CGFloat"))
        #expect(strip.contains(".frame(height: stripHeight)"))
        #expect(strip.contains(".frame(maxWidth: .infinity, alignment: .leading)"))
        #expect(strip.contains("ZStack"))
        #expect(strip.contains(".multilineTextAlignment(.center)"))
        #expect(strip.contains("Color.clear"))
        #expect(strip.contains(".frame(width: 18, height: 18)"))
        #expect(strip.contains(".frame(width: 36, alignment: .leading)"))
    }

    @Test("desktop workspace tabs prevent window dragging from consuming clicks")
    func desktopWorkspaceTabsPreventWindowDraggingFromConsumingClicks() throws {
        let strip = try source("Sources/SloppyClient/Navigation/Tabs/DesktopWorkspaceTabStrip.swift")

        #expect(strip.contains("WindowDragGestureShieldHostingView<Content>"))
        #expect(strip.contains("private let hostingView: WindowDragGestureShieldHostingView<Content>"))
        #expect(strip.contains("override var mouseDownCanMoveWindow: Bool { false }"))
    }

    @Test("desktop workspace tabs close on middle mouse click")
    func desktopWorkspaceTabsCloseOnMiddleMouseClick() throws {
        let strip = try source("Sources/SloppyClient/Navigation/Tabs/DesktopWorkspaceTabStrip.swift")

        #expect(strip.contains("MiddleClickCloseArea"))
        #expect(strip.contains(".overlay {\n#if os(macOS)"))
        #expect(strip.contains("onMiddleClick: onClose"))
        #expect(strip.contains("override func hitTest(_ point: NSPoint) -> NSView?"))
        #expect(strip.contains("return super.hitTest(point)"))
        #expect(!strip.contains("override func hitTest(_ point: NSPoint) -> NSView? {\n        self\n    }"))
        #expect(strip.contains("override func otherMouseUp(with event: NSEvent)"))
        #expect(strip.contains("event.buttonNumber == 2"))
    }

    @Test("main view wires cmd t and shared detail host for workspace tabs")
    func mainViewWiresCommandTAndSharedDetailHost() throws {
        let mainView = try source("Sources/SloppyClient/Navigation/Main/MainView.swift")

        #expect(mainView.contains("keyboardShortcut(\"t\", modifiers: [.command])"))
        #expect(mainView.contains("keyboardShortcut(\"w\", modifiers: [.command])"))
        #expect(mainView.contains("viewModel.createBlankChatTab()"))
        #expect(mainView.contains("viewModel.closeActiveTab()"))
        #expect(mainView.contains("private func workspaceContentHost(showsFloatingTabChrome: Bool) -> some View"))
    }

    @Test("main view defers pager geometry writes outside scroll geometry callback")
    func mainViewDefersPagerGeometryWritesOutsideScrollGeometryCallback() throws {
        let mainView = try source("Sources/SloppyClient/Navigation/Main/MainView.swift")

        #expect(mainView.contains("private func updatePagerSize(_ newValue: CGSize)"))
        #expect(mainView.contains("Task { @MainActor in\n            pagerSize = newValue\n        }"))
        #expect(!mainView.contains("action: { _, newValue in\n                pagerSize = newValue\n            }"))
    }

    @Test("main view model defers new task chat navigation requests")
    func mainViewModelDefersNewTaskChatNavigationRequests() throws {
        let mainViewModel = try source("Sources/SloppyClient/Navigation/Main/MainViewModel.swift")

        #expect(mainViewModel.contains("private func applyNavigationRequestOnNextTurn("))
        #expect(mainViewModel.contains("Task { @MainActor in"))
        #expect(mainViewModel.contains("viewModel.applyNavigationRequest(request)"))
        #expect(mainViewModel.contains("if loadInitialData {\n                viewModel.loadInitialData()\n            }"))
        #expect(!mainViewModel.contains("chatState.viewModel.applyNavigationRequest(\n            ChatNavigationRequest("))
    }

    @Test("main view model exposes active-tab close helper")
    func mainViewModelExposesActiveTabCloseHelper() throws {
        let mainView = try source("Sources/SloppyClient/Navigation/Main/MainView.swift")

        #expect(mainView.contains("func closeActiveTab()"))
        #expect(mainView.contains("guard let selectedTabID else"))
        #expect(mainView.contains("closeTab(selectedTabID)"))
    }
}

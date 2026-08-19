import Foundation
import Testing

@Suite("Transparent window source")
struct TransparentWindowSourceTests {
    private func source(_ path: String) throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: packageRoot.appendingPathComponent(path), encoding: .utf8)
    }

    @Test("app scene clears the system window background")
    func appSceneClearsSystemWindowBackground() throws {
        let appSource = try source("Sources/SloppyClient/App/SloppyClientApp.swift")

        #expect(appSource.contains(".containerBackground(.clear, for: .window)"))
    }

    @Test("root shell installs the transparent window bridge")
    func rootShellInstallsTransparentWindowBridge() throws {
        let rootShell = try source("Sources/SloppyClient/Root/RootShellView.swift")

        #expect(rootShell.contains("TransparentWindowConfigurationView { window in"))
        #expect(rootShell.contains("WindowDragHandleStrip(height:"))
        #expect(rootShell.contains("max(0, safeAreaInsets.top)"))
        #expect(rootShell.contains(".allowsHitTesting(false)"))
        #expect(!rootShell.contains("WindowDragHandleStrip(height: 36)"))
    }

    @Test("desktop overlay configures a non-opaque titlebar-transparent window")
    func desktopOverlayConfiguresNonOpaqueTransparentTitlebarWindow() throws {
        let overlay = try source("Sources/SloppyClient/Overlays/SloppyDesktopOverlay.swift")

        #expect(overlay.contains("window.isOpaque = false"))
        #expect(overlay.contains("window.backgroundColor = .clear"))
        #expect(overlay.contains("window.titlebarAppearsTransparent = true"))
        #expect(overlay.contains("window.isMovableByWindowBackground = false"))
    }

    @Test("desktop overlay opts into unified toolbar chrome")
    func desktopOverlayOptsIntoUnifiedToolbarChrome() throws {
        let overlay = try source("Sources/SloppyClient/Overlays/SloppyDesktopOverlay.swift")

        #expect(overlay.contains("window.titlebarSeparatorStyle = .none"))
        #expect(overlay.contains("window.toolbarStyle = .unified"))
    }

    @Test("desktop overlay creates an always-on interactive notch panel")
    func desktopOverlayCreatesAnAlwaysOnInteractiveNotchPanel() throws {
        let overlay = try source("Sources/SloppyClient/Overlays/SloppyDesktopOverlay.swift")
        let rootModel = try source("Sources/SloppyClient/Root/RootShellViewModel.swift")

        #expect(overlay.contains("SloppyNotchPanel"))
        #expect(overlay.contains("SloppyDesktopNotchView"))
        #expect(overlay.contains("panel.level = .statusBar"))
        #expect(overlay.contains(".canJoinAllSpaces"))
        #expect(overlay.contains("Button(\"Allow\")"))
        #expect(overlay.contains("Button(\"Deny\""))
        #expect(overlay.contains(".onHover(perform: handleHoverChange)"))
        #expect(overlay.contains("state.setExpanded(true)"))
        #expect(overlay.contains("state.toolApproval == nil"))
        #expect(overlay.contains("state.setExpanded(false)"))
        #expect(rootModel.contains("desktopOverlay.start(settings: settings)"))
    }

    @Test("desktop overlay stays collapsed while Sloppy Client is active")
    func desktopOverlayStaysCollapsedWhileSloppyClientIsActive() throws {
        let overlay = try source("Sources/SloppyClient/Overlays/SloppyDesktopOverlay.swift")

        #expect(overlay.contains("!NSApp.isActive || !self.state.isExpanded"))
        #expect(overlay.contains("NSApplication.didBecomeActiveNotification"))
        #expect(overlay.contains("self?.state.setExpanded(false)"))
    }

    @Test("desktop overlay shows typed active agent run status")
    func desktopOverlayShowsTypedActiveAgentRunStatus() throws {
        let overlay = try source("Sources/SloppyClient/Overlays/SloppyDesktopOverlay.swift")
        let rootModel = try source("Sources/SloppyClient/Root/RootShellViewModel.swift")

        #expect(overlay.contains("status.stage.isWorking"))
        #expect(overlay.contains("Agents working"))
        #expect(overlay.contains("state.setActiveAgentRuns(activity.activeRuns)"))
        #expect(overlay.contains("apiClient.fetchAgentSessions("))
        #expect(rootModel.contains("desktopOverlay.start(settings: settings, baseURL: url)"))
    }

    @Test("desktop overlay collapses active details after three seconds")
    func desktopOverlayCollapsesActiveDetailsAfterThreeSeconds() throws {
        let overlay = try source("Sources/SloppyClient/Overlays/SloppyDesktopOverlay.swift")

        #expect(overlay.contains(".task(id: state.activityRevealToken)"))
        #expect(overlay.contains("Task.sleep(for: .seconds(3))"))
        #expect(overlay.contains("while isPointerInsidePanel()"))
        #expect(overlay.contains("state.setExpanded(false)"))
        #expect(overlay.contains("activityRevealToken &+= 1"))
    }

    @Test("desktop overlay opens the selected agent session in the main window")
    func desktopOverlayOpensSelectedAgentSessionInMainWindow() throws {
        let overlay = try source("Sources/SloppyClient/Overlays/SloppyDesktopOverlay.swift")
        let rootModel = try source("Sources/SloppyClient/Root/RootShellViewModel.swift")
        let rootView = try source("Sources/SloppyClient/Root/RootShellView.swift")

        #expect(overlay.contains("state.openAgentRun(run)"))
        #expect(overlay.contains("arrow.up.forward.app"))
        #expect(overlay.contains("window?.makeKeyAndOrderFront(nil)"))
        #expect(rootModel.contains(".session(agentId: agentID, sessionId: sessionID)"))
        #expect(rootModel.contains("desktopOverlay.presentMainWindow()"))
        #expect(rootView.contains("openWindow(id: \"main\")"))
    }

    @Test("desktop overlay shows three recent chats and sends an inline prompt")
    func desktopOverlayShowsRecentChatsAndSendsInlinePrompt() throws {
        let overlay = try source("Sources/SloppyClient/Overlays/SloppyDesktopOverlay.swift")

        #expect(overlay.contains(".prefix(3)"))
        #expect(overlay.contains("Label(\"Recent chats\""))
        #expect(overlay.contains("state.setRecentChats(activity.recentChats)"))
        #expect(overlay.contains("state.togglePromptComposer(for: chat)"))
        #expect(overlay.contains("TextField("))
        #expect(overlay.contains("paperplane.fill"))
        #expect(overlay.contains("apiClient.postSessionMessage("))
        #expect(overlay.contains("state.submitPrompt(to: chat)"))
        #expect(overlay.contains("state.openRecentChat(chat)"))
    }

    @Test("desktop overlay creates an agent task in the selected project")
    func desktopOverlayCreatesAgentTaskInSelectedProject() throws {
        let overlay = try source("Sources/SloppyClient/Overlays/SloppyDesktopOverlay.swift")

        #expect(overlay.contains("Picker("))
        #expect(overlay.contains("New task for agent…"))
        #expect(overlay.contains("state.setProjects(projects.map"))
        #expect(overlay.contains("apiClient.createProjectTask("))
        #expect(overlay.contains("status: \"ready\""))
        #expect(overlay.contains("actorId: project.actorID"))
        #expect(overlay.contains("state.submitTask()"))
    }

    @Test("desktop overlay ignores transient hover exits caused by panel resizing")
    func desktopOverlayIgnoresTransientHoverExits() throws {
        let overlay = try source("Sources/SloppyClient/Overlays/SloppyDesktopOverlay.swift")

        #expect(overlay.contains("isPointerInsidePanel"))
        #expect(overlay.contains("Task.sleep(for: .milliseconds(120))"))
        #expect(overlay.contains("guard !isPointerInsidePanel() else { continue }"))
        #expect(overlay.contains("hoverCollapseTask?.cancel()"))
    }

    @Test("desktop overlay keeps the inline prompt open when the pointer leaves")
    func desktopOverlayKeepsInlinePromptOpenWhenPointerLeaves() throws {
        let overlay = try source("Sources/SloppyClient/Overlays/SloppyDesktopOverlay.swift")

        #expect(overlay.contains("state.selectedRecentChatID == nil"))
        #expect(overlay.contains("!state.hasTaskDraft"))
        #expect(overlay.contains("!isTaskComposerFocused"))
    }

    @Test("desktop overlay uses compact panel dimensions")
    func desktopOverlayUsesCompactPanelDimensions() throws {
        let overlay = try source("Sources/SloppyClient/Overlays/SloppyDesktopOverlay.swift")

        #expect(overlay.contains("collapsedSize = CGSize(width: 164, height: 32)"))
        #expect(overlay.contains("expandedSize = CGSize(width: 340, height: 148)"))
        #expect(overlay.contains("wideWidth: CGFloat = 520"))
    }
}

import Foundation
import Observation
import SloppyClientCore
import SloppyClientUI

#if os(macOS)
import AppKit
import QuartzCore
import SwiftUI

@MainActor
final class SloppyDesktopOverlay {
    private let state = SloppyDesktopOverlayState()
    private weak var window: NSWindow?
    private var overlayPanel: SloppyNotchPanel?
    private var screenObserver: NSObjectProtocol?
    private var applicationActivationObserver: NSObjectProtocol?
    private var apiClient = SloppyAPIClient()
    private var closeBehavior: ClientWindowCloseBehavior = .keepProcess
    private var activityRefreshTask: Task<Void, Never>?
    private var panelResizeTask: Task<Void, Never>?
    private var agentRunCache: [String: SloppyDesktopAgentRunCacheEntry] = [:]
    var onOpenAgentRun: (@MainActor (String, String) -> Void)?

    func start(settings: ClientSettings, baseURL: URL? = nil) {
        closeBehavior = settings.windowCloseBehavior
        let resolvedBaseURL = baseURL ?? settings.baseURL
        if apiClient.baseURL != resolvedBaseURL {
            agentRunCache.removeAll()
        }
        apiClient = SloppyAPIClient(baseURL: resolvedBaseURL)
        state.onDecision = { [weak self] approvalID, approved in
            await self?.resolveApproval(id: approvalID, approved: approved)
        }
        state.onOpenAgentRun = { [weak self] run in
            self?.onOpenAgentRun?(run.agentID, run.sessionID)
        }
        state.onOpenRecentChat = { [weak self] chat in
            self?.onOpenAgentRun?(chat.agentID, chat.sessionID)
        }
        state.onSendPrompt = { [weak self] chat, prompt in
            guard let self else { return }
            _ = try await self.apiClient.postSessionMessage(
                agentId: chat.agentID,
                sessionId: chat.sessionID,
                content: prompt
            )
        }
        state.onCreateTask = { [weak self] project, title in
            guard let self else { return }
            _ = try await self.apiClient.createProjectTask(
                projectId: project.id,
                request: APIProjectTaskCreateRequest(
                    title: title,
                    status: "ready",
                    actorId: project.actorID
                )
            )
        }
        startActivityRefresh()
        ensureOverlayPanel()
        if let window {
            configureTransparentWindow(window)
        }
        applyCloseBehavior(settings.windowCloseBehavior)
    }

    func attach(window: NSWindow) {
        guard self.window !== window else { return }
        self.window = window
        configureTransparentWindow(window)
        if let overlayPanel {
            position(panel: overlayPanel, animated: false)
        }
        applyCloseBehavior(closeBehavior)
    }

    func applyCloseBehavior(_ behavior: ClientWindowCloseBehavior) {
        closeBehavior = behavior
    }

    func presentMainWindow() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func updateToolApproval(_ notification: AppNotification) {
        state.apply(notification)
        overlayPanel?.orderFrontRegardless()
    }

    private func ensureOverlayPanel() {
        if let overlayPanel {
            position(panel: overlayPanel, animated: false)
            overlayPanel.orderFrontRegardless()
            return
        }

        let panel = SloppyNotchPanel(
            contentRect: NSRect(origin: .zero, size: SloppyDesktopNotchView.collapsedSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        let hostingView = NSHostingView(
            rootView: SloppyDesktopNotchView(
                state: state,
                isPointerInsidePanel: { [weak panel] in
                    guard let panel else { return false }
                    return panel.frame.contains(NSEvent.mouseLocation)
                }
            )
        )
        // The panel owns its size. SwiftUI's intrinsic-size constraints must not
        // resize/recenter the window when the expanded content is inserted.
        hostingView.sizingOptions = []
        panel.contentView = hostingView
        overlayPanel = panel
        state.onExpansionChanged = { [weak self] in
            guard let self, let panel = self.overlayPanel else { return }
            guard !NSApp.isActive || !self.state.isExpanded else {
                self.state.setExpanded(false)
                return
            }
            self.position(panel: panel, animated: true)
        }
        position(panel: panel, animated: false)
        panel.orderFrontRegardless()

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, let panel = self.overlayPanel else { return }
                self.position(panel: panel, animated: false)
            }
        }

        applicationActivationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: NSApp,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.state.setExpanded(false)
            }
        }
    }

    private func position(panel: NSPanel, animated: Bool) {
        panelResizeTask?.cancel()
        guard let screen = window?.screen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let size = SloppyDesktopNotchView.size(for: state)
        let frame = NSRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
        guard animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            panel.setFrame(frame, display: true)
            return
        }
        let initialFrame = panel.frame
        let expanding = state.isExpanded
        let duration = expanding ? 0.24 : 0.16
        // NSWindow's animator clamps overshoot, so interpolate the frame directly.
        // Starting from the current frame also keeps interrupted transitions continuous.
        panelResizeTask = Task { @MainActor [weak panel] in
            let start = CACurrentMediaTime()
            while !Task.isCancelled {
                guard let panel else { return }
                let time = min((CACurrentMediaTime() - start) / duration, 1)
                guard time < 1 else {
                    panel.setFrame(frame, display: true)
                    return
                }
                let remaining = time - 1
                let progress = expanding
                    ? 1 + 1.9 * remaining * remaining * remaining + 0.9 * remaining * remaining
                    : 1 + remaining * remaining * remaining
                let width = initialFrame.width + (frame.width - initialFrame.width) * progress
                let height = initialFrame.height + (frame.height - initialFrame.height) * progress
                panel.setFrame(NSRect(
                    x: screen.frame.midX - width / 2,
                    y: screen.frame.maxY - height,
                    width: width,
                    height: height
                ), display: false)
                try? await Task.sleep(for: .milliseconds(8))
            }
        }
    }

    private func startActivityRefresh() {
        activityRefreshTask?.cancel()
        activityRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshActiveActivity()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private func refreshActiveActivity() async {
        async let projectsRequest = apiClient.fetchProjects()
        async let agentsRequest = apiClient.fetchAgents()

        let projects = try? await projectsRequest
        let agents = try? await agentsRequest

        if let projects {
            state.setProjects(projects.map {
                SloppyDesktopProject(
                    id: $0.id,
                    name: $0.name,
                    actorID: $0.actors?.first
                )
            })
            let activeTasks = projects.flatMap { project in
                (project.tasks ?? []).compactMap { task -> SloppyDesktopTask? in
                    guard task.normalizedKanbanColumnID == .inProgress
                        || task.normalizedKanbanColumnID == .needsReview else { return nil }
                    return SloppyDesktopTask(
                        id: "\(project.id)/\(task.id)",
                        title: task.title,
                        projectName: project.name,
                        status: task.normalizedKanbanColumnID
                    )
                }
            }
            state.setActiveTasks(activeTasks)
        }
        if let agents {
            let activity = await fetchAgentActivity(for: agents)
            state.setActiveAgentRuns(activity.activeRuns)
            state.setRecentChats(activity.recentChats)
        }
    }

    private func fetchAgentActivity(for agents: [APIAgentRecord]) async -> SloppyDesktopAgentActivity {
        let sessionsByAgent = await withTaskGroup(
            of: (APIAgentRecord, [ChatSessionSummary]).self,
            returning: [(APIAgentRecord, [ChatSessionSummary])].self
        ) { group in
            for agent in agents {
                group.addTask { [apiClient] in
                    let sessions = (try? await apiClient.fetchAgentSessions(
                        agentId: agent.id,
                        limit: 8
                    )) ?? []
                    return (agent, sessions)
                }
            }

            var result: [(APIAgentRecord, [ChatSessionSummary])] = []
            for await item in group {
                result.append(item)
            }
            return result
        }

        let recentChats = sessionsByAgent.flatMap { agent, sessions in
            sessions.map { session in
                SloppyDesktopRecentChat(
                    id: "\(agent.id)/\(session.id)",
                    agentID: agent.id,
                    sessionID: session.id,
                    title: session.title,
                    agentName: agent.displayName,
                    updatedAt: session.updatedAt
                )
            }
        }
        .sorted { $0.updatedAt > $1.updatedAt }
        .prefix(3)

        let cachedRuns = agentRunCache
        let lookups = await withTaskGroup(
            of: SloppyDesktopAgentRunLookup.self,
            returning: [SloppyDesktopAgentRunLookup].self
        ) { group in
            for (agent, sessions) in sessionsByAgent {
                for session in sessions {
                    let cacheID = "\(agent.id)/\(session.id)"
                    group.addTask { [apiClient] in
                        if let cached = cachedRuns[cacheID], cached.updatedAt == session.updatedAt {
                            return SloppyDesktopAgentRunLookup(
                                id: cacheID,
                                updatedAt: session.updatedAt,
                                run: cached.run
                            )
                        }
                        guard let detail = try? await apiClient.fetchAgentSession(
                            agentId: agent.id,
                            sessionId: session.id
                        ),
                        let status = detail.latestRunStatus,
                        status.stage.isWorking else {
                            return SloppyDesktopAgentRunLookup(
                                id: cacheID,
                                updatedAt: session.updatedAt,
                                run: nil
                            )
                        }
                        return SloppyDesktopAgentRunLookup(
                            id: cacheID,
                            updatedAt: session.updatedAt,
                            run: SloppyDesktopAgentRun(
                                id: cacheID,
                                agentID: agent.id,
                                sessionID: session.id,
                                sessionTitle: session.title,
                                agentName: agent.displayName,
                                statusLabel: status.label,
                                statusDetails: status.details,
                                updatedAt: session.updatedAt
                            )
                        )
                    }
                }
            }

            var result: [SloppyDesktopAgentRunLookup] = []
            for await lookup in group {
                result.append(lookup)
            }
            return result
        }

        agentRunCache = Dictionary(uniqueKeysWithValues: lookups.map {
            ($0.id, SloppyDesktopAgentRunCacheEntry(updatedAt: $0.updatedAt, run: $0.run))
        })
        return SloppyDesktopAgentActivity(
            activeRuns: lookups.compactMap(\.run).sorted { $0.updatedAt > $1.updatedAt },
            recentChats: Array(recentChats)
        )
    }

    private func resolveApproval(id: String, approved: Bool) async {
        state.isResolving = true
        defer { state.isResolving = false }
        do {
            try await apiClient.resolveToolApproval(id: id, approved: approved)
            state.toolApproval = nil
            state.isExpanded = !state.activeTasks.isEmpty
            state.onExpansionChanged?()
        } catch {
            state.errorMessage = error.localizedDescription
        }
    }

    private func configureTransparentWindow(_ window: NSWindow) {
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.toolbarStyle = .unified
        window.isMovableByWindowBackground = false
        window.styleMask.insert(.fullSizeContentView)
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
    }
}

private final class SloppyNotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        // A notch sits at the physical screen edge, including the menu-bar area.
        frameRect
    }
}

private struct SloppyDesktopNotchView: View {
    static let collapsedSize = CGSize(width: 164, height: 32)
    static let expandedSize = CGSize(width: 340, height: 148)
    static let wideWidth: CGFloat = 480

    static func size(for state: SloppyDesktopOverlayState) -> CGSize {
        guard state.isExpanded else {
            return state.usesWideCollapsedLayout
                ? CGSize(width: wideWidth, height: collapsedSize.height)
                : collapsedSize
        }
        return expandedPanelSize(for: state)
    }

    private static func expandedPanelSize(for state: SloppyDesktopOverlayState) -> CGSize {
        guard state.usesWideLayout else {
            return expandedSize
        }
        let visibleActivityRows = min(state.activeAgentRuns.count, 3) + min(state.activeTasks.count, 3)
        let visibleRecentChatRows = min(state.recentChats.count, 3)
        let rowHeight = CGFloat(visibleActivityRows + visibleRecentChatRows) * 42
        let chatComposerHeight: CGFloat = state.selectedRecentChatID == nil
            ? 0
            : (state.promptError == nil ? 40 : 58)
        let taskComposerHeight: CGFloat = state.taskCreationError == nil ? 70 : 86
        let approvalHeight: CGFloat = state.toolApproval == nil ? 0 : 132
        let sectionCount = (state.activeAgentRuns.isEmpty ? 0 : 1)
            + (state.activeTasks.isEmpty ? 0 : 1)
            + (state.recentChats.isEmpty ? 0 : 1)
        let sectionSpacing = CGFloat(max(0, sectionCount - 1)) * 10
            + (state.toolApproval != nil && state.activityCount > 0 ? 14 : 0)
        return CGSize(
            width: wideWidth,
            height: min(
                520,
                64 + rowHeight + chatComposerHeight + taskComposerHeight + approvalHeight + sectionSpacing
            )
        )
    }

    let state: SloppyDesktopOverlayState
    let isPointerInsidePanel: @MainActor () -> Bool
    @State private var isHovered = false
    @State private var hoverCollapseTask: Task<Void, Never>?
    @FocusState private var focusedRecentChatID: String?
    @FocusState private var isTaskComposerFocused: Bool

    init(
        state: SloppyDesktopOverlayState,
        isPointerInsidePanel: @escaping @MainActor () -> Bool = { false }
    ) {
        self.state = state
        self.isPointerInsidePanel = isPointerInsidePanel
    }

    var body: some View {
        headerContent
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .top) {
            // The fixed-width details must not impose their width on the header
            // or the collapsed panel. Reveal them below the stationary header.
            revealedContent.padding(.top, Self.collapsedSize.height)
        }
        .foregroundStyle(.white)
        .background {
            UnevenRoundedRectangle(bottomLeadingRadius: 14, bottomTrailingRadius: 14)
                .fill(.black.opacity(isHovered ? 0.96 : 0.92))
                .overlay {
                    UnevenRoundedRectangle(bottomLeadingRadius: 14, bottomTrailingRadius: 14)
                        .stroke(.white.opacity(0.12), lineWidth: 1)
                }
        }
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 14, bottomTrailingRadius: 14))
        .onHover(perform: handleHoverChange)
        .onDisappear {
            hoverCollapseTask?.cancel()
        }
        .task(id: state.activityRevealToken) {
            await autoCollapseActiveContent()
        }
        .onChange(of: state.selectedRecentChatID) { _, chatID in
            Task { @MainActor in
                await Task.yield()
                focusedRecentChatID = chatID
            }
        }
        .onChange(of: state.isExpanded) { _, expanded in
            if !expanded {
                focusedRecentChatID = nil
                isTaskComposerFocused = false
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sloppy desktop notch")
    }

    private var headerContent: some View {
        HStack(spacing: 7) {
            if state.toolApproval == nil {
                SloppyAssets.projectLogo
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
                    .accessibilityHidden(true)
            } else {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
            }
            if let run = state.primaryAgentRun {
                Button {
                    state.openAgentRun(run)
                } label: {
                    Text(compactTitle)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                .help("Open chat with \(run.agentName)")
            } else {
                Button {
                    state.toggleExpanded()
                } label: {
                    Text(compactTitle)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 2)
            if state.activityCount > 0 {
                Label("\(state.activityCount)", systemImage: "bolt.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.cyan)
                    .labelStyle(.titleAndIcon)
            }
            Button {
                state.toggleExpanded()
            } label: {
                Image(systemName: state.isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(state.isExpanded ? "Hide details" : "Show details")
        }
        .padding(.horizontal, 12)
        .frame(height: Self.collapsedSize.height)
    }

    private var revealedContent: some View {
        let size = Self.expandedPanelSize(for: state)
        let opacity: Double = state.isExpanded ? 1 : 0
        return VStack(spacing: 0) {
            Divider().opacity(0.35)
            expandedContent
        }
        // Keep text, rows and native controls at their final layout size.
        // Only the surrounding panel clips/reveals them during resizing.
        .frame(
            width: size.width,
            height: size.height - Self.collapsedSize.height,
            alignment: .top
        )
        .opacity(opacity)
        .animation(
            state.isExpanded ? .easeOut(duration: 0.16).delay(0.03) : .easeOut(duration: 0.08),
            value: state.isExpanded
        )
        .allowsHitTesting(state.isExpanded)
        .disabled(!state.isExpanded)
        .accessibilityHidden(!state.isExpanded)
    }

    private var compactTitle: String {
        if let tool = state.toolApproval?.metadata["tool"] {
            return tool
        }
        if state.activeAgentRuns.count == 1 {
            return "\(state.activeAgentRuns[0].agentName) is working"
        }
        if state.activeAgentRuns.count > 1 {
            return "\(state.activeAgentRuns.count) agents working"
        }
        return state.toolApproval == nil ? "Sloppy" : "Approval required"
    }

    private func handleHoverChange(_ hovering: Bool) {
        hoverCollapseTask?.cancel()
        hoverCollapseTask = nil

        guard hovering else {
            scheduleHoverCollapse()
            return
        }

        isHovered = true
        state.setExpanded(true)
    }

    private func scheduleHoverCollapse() {
        guard state.toolApproval == nil,
              state.selectedRecentChatID == nil,
              !state.hasTaskDraft,
              !isTaskComposerFocused else { return }

        hoverCollapseTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(120))
                guard !Task.isCancelled else { return }
                guard state.toolApproval == nil else { return }
                guard state.selectedRecentChatID == nil else { return }
                guard !state.hasTaskDraft, !isTaskComposerFocused else { return }
                guard !isPointerInsidePanel() else { continue }

                isHovered = false
                state.setExpanded(false)
                return
            }
        }
    }

    private func autoCollapseActiveContent() async {
        guard state.activityRevealToken > 0 else { return }
        try? await Task.sleep(for: .seconds(3))
        guard !Task.isCancelled else { return }

        while isPointerInsidePanel() {
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
        }

        guard state.toolApproval == nil,
              state.activityCount > 0,
              state.selectedRecentChatID == nil,
              !state.hasTaskDraft,
              !isTaskComposerFocused else { return }
        isHovered = false
        state.setExpanded(false)
    }

    @ViewBuilder
    private var expandedContent: some View {
        if state.usesWideLayout {
            VStack(alignment: .leading, spacing: 10) {
                if let approval = state.toolApproval {
                    approvalContent(approval)
                }
                if state.toolApproval != nil && state.activityCount > 0 {
                    Divider().opacity(0.35)
                }
                if !state.activeAgentRuns.isEmpty {
                    activeAgentRunsContent
                }
                if !state.activeAgentRuns.isEmpty && !state.activeTasks.isEmpty {
                    Divider().opacity(0.35)
                }
                if !state.activeTasks.isEmpty {
                    activeTasksContent
                }
                if (!state.activeAgentRuns.isEmpty || !state.activeTasks.isEmpty)
                    && !state.recentChats.isEmpty {
                    Divider().opacity(0.35)
                }
                if !state.recentChats.isEmpty {
                    recentChatsContent
                }
                if state.hasContentBeforeTaskComposer {
                    Divider().opacity(0.35)
                }
                taskComposerContent
            }
            .padding(12)
        } else {
            VStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.green)
                Text("Sloppy is running")
                    .font(.system(size: 12, weight: .semibold))
                Text("Tool approvals will appear here.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(12)
        }
    }

    private func approvalContent(_ approval: AppNotification) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "exclamationmark.shield.fill")
                    .foregroundStyle(.orange)
                Text(approval.title)
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                if state.isResolving {
                    ProgressView()
                        .controlSize(.small)
                }
            }
                Text(approval.message)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if let errorMessage = state.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                }
                HStack {
                    Spacer()
                    Button("Deny", role: .destructive) {
                        state.decide(approved: false)
                    }
                    .buttonStyle(.glass)
                    Button("Allow") {
                        state.decide(approved: true)
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.glassProminent)
                }
                .buttonBorderShape(.capsule)
                .controlSize(.small)
                .disabled(state.isResolving)
        }
    }

    private var activeTasksContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Tasks in progress", systemImage: "bolt.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.cyan)
                Spacer()
                Text("\(state.activeTasks.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ForEach(state.activeTasks.prefix(3)) { task in
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.mini)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(task.title)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                        Text("\(task.projectName) · \(task.statusTitle)")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
            if state.activeTasks.count > 3 {
                Text("+\(state.activeTasks.count - 3) more")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private var activeAgentRunsContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Agents working", systemImage: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.green)
                Spacer()
                Text("\(state.activeAgentRuns.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ForEach(state.activeAgentRuns.prefix(3)) { run in
                Button {
                    state.openAgentRun(run)
                } label: {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.mini)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(run.sessionTitle)
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(1)
                            Text(run.subtitle)
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: "arrow.up.forward.app")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Open chat with \(run.agentName)")
            }
        }
    }

    private var recentChatsContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Recent chats", systemImage: "bubble.left.and.bubble.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.mint)
                Spacer()
                Text("\(state.recentChats.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ForEach(state.recentChats.prefix(3)) { chat in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        Button {
                            state.togglePromptComposer(for: chat)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: state.selectedRecentChatID == chat.id
                                    ? "text.cursor"
                                    : "bubble.left")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.mint)
                                    .frame(width: 14)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(chat.title)
                                        .font(.system(size: 11, weight: .medium))
                                        .lineLimit(1)
                                    Text(chat.agentName)
                                        .font(.system(size: 9))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Write to \(chat.agentName)")

                        Button {
                            state.openRecentChat(chat)
                        } label: {
                            Image(systemName: "arrow.up.forward.app")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                                .frame(width: 22, height: 22)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Open full chat")
                    }

                    if state.selectedRecentChatID == chat.id {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                TextField(
                                    "Message \(chat.agentName)…",
                                    text: Binding(
                                        get: { state.promptText },
                                        set: { state.promptText = $0 }
                                    )
                                )
                                .textFieldStyle(.plain)
                                .font(.system(size: 11))
                                .padding(.horizontal, 9)
                                .frame(height: 28)
                                .background(.white.opacity(0.09), in: Capsule())
                                .focused($focusedRecentChatID, equals: chat.id)
                                .onSubmit {
                                    state.submitPrompt(to: chat)
                                }

                                Button {
                                    state.submitPrompt(to: chat)
                                } label: {
                                    if state.isSendingPrompt {
                                        ProgressView()
                                            .controlSize(.mini)
                                            .frame(width: 26, height: 26)
                                    } else {
                                        Image(systemName: "paperplane.fill")
                                            .font(.system(size: 10, weight: .semibold))
                                            .frame(width: 26, height: 26)
                                    }
                                }
                                .buttonStyle(.glassProminent)
                                .buttonBorderShape(.circle)
                                .disabled(!state.canSendPrompt)
                                .help("Send message")
                            }
                            if let promptError = state.promptError {
                                Text(promptError)
                                    .font(.system(size: 9))
                                    .foregroundStyle(.red)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
        }
    }

    private var taskComposerContent: some View {
        VStack(alignment: .leading, spacing: 5) {
            Menu {
                Picker(
                    "Project",
                    selection: Binding(
                        get: { state.selectedProjectID ?? "" },
                        set: { state.selectProject(id: $0) }
                    )
                ) {
                    if state.projects.isEmpty {
                        Text("No projects").tag("")
                    } else {
                        ForEach(state.projects) { project in
                            Text(project.name).tag(project.id)
                        }
                    }
                }
                .pickerStyle(.inline)
            } label: {
                HStack(spacing: 5) {
                    Text(state.projects.first { $0.id == state.selectedProjectID }?.name ?? "No projects")
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize(horizontal: true, vertical: false)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 19)
            .disabled(state.projects.isEmpty)
            .help("Project for the new task")

            HStack(spacing: 7) {
                TextField(
                    "New task for agent…",
                    text: Binding(
                        get: { state.taskDraft },
                        set: { state.updateTaskDraft($0) }
                    )
                )
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .padding(.horizontal, 9)
                .frame(height: 28)
                .background(.white.opacity(0.09), in: Capsule())
                .focused($isTaskComposerFocused)
                .onSubmit {
                    state.submitTask()
                }

                Button {
                    state.submitTask()
                } label: {
                    if state.isCreatingTask {
                        ProgressView()
                            .controlSize(.mini)
                            .frame(width: 26, height: 26)
                    } else {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .frame(width: 26, height: 26)
                    }
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
                .disabled(!state.canCreateTask)
                .help("Create task")
            }

            if let taskCreationError = state.taskCreationError {
                Text(taskCreationError)
                    .font(.system(size: 9))
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }
        }
    }
}

@MainActor
struct TransparentWindowConfigurationView: NSViewRepresentable {
    let onWindowAvailable: @MainActor (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        configureWindow(from: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        configureWindow(from: nsView)
    }

    private func configureWindow(from view: NSView) {
        DispatchQueue.main.async { [weak view] in
            guard let window = view?.window else { return }
            onWindowAvailable(window)
        }
    }
}

@MainActor
struct WindowDragHandleStrip: NSViewRepresentable {
    let height: CGFloat

    func makeNSView(context: Context) -> WindowDragHandleNSView {
        WindowDragHandleNSView()
    }

    func updateNSView(_ nsView: WindowDragHandleNSView, context: Context) {
        _ = height
    }
}

final class WindowDragHandleNSView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        self
    }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

@Observable
@MainActor
final class SloppyDesktopOverlayState {
    var toolApproval: AppNotification?
    var activeAgentRuns: [SloppyDesktopAgentRun] = []
    var activeTasks: [SloppyDesktopTask] = []
    var recentChats: [SloppyDesktopRecentChat] = []
    var projects: [SloppyDesktopProject] = []
    var isExpanded = false
    var isResolving = false
    var errorMessage: String?
    var activityRevealToken = 0
    var selectedRecentChatID: String?
    var promptText = ""
    var isSendingPrompt = false
    var promptError: String?
    var selectedProjectID: String?
    var taskDraft = ""
    var isCreatingTask = false
    var taskCreationError: String?
    var onExpansionChanged: (@MainActor () -> Void)?
    var onDecision: (@MainActor (String, Bool) async -> Void)?
    var onOpenAgentRun: (@MainActor (SloppyDesktopAgentRun) -> Void)?
    var onOpenRecentChat: (@MainActor (SloppyDesktopRecentChat) -> Void)?
    var onSendPrompt: (@MainActor (SloppyDesktopRecentChat, String) async throws -> Void)?
    var onCreateTask: (@MainActor (SloppyDesktopProject, String) async throws -> Void)?

    var usesWideLayout: Bool {
        true
    }

    var usesWideCollapsedLayout: Bool {
        toolApproval != nil || activityCount > 0
    }

    var activityCount: Int {
        activeAgentRuns.count + activeTasks.count
    }

    var primaryAgentRun: SloppyDesktopAgentRun? {
        guard toolApproval == nil, activeAgentRuns.count == 1 else { return nil }
        return activeAgentRuns[0]
    }

    var canSendPrompt: Bool {
        !promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isSendingPrompt
    }

    var hasTaskDraft: Bool {
        !taskDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canCreateTask: Bool {
        hasTaskDraft
            && selectedProject != nil
            && !isCreatingTask
    }

    var hasContentBeforeTaskComposer: Bool {
        toolApproval != nil || activityCount > 0 || !recentChats.isEmpty
    }

    private var selectedProject: SloppyDesktopProject? {
        guard let selectedProjectID else { return nil }
        return projects.first { $0.id == selectedProjectID }
    }

    func toggleExpanded() {
        setExpanded(!isExpanded)
    }

    func setExpanded(_ expanded: Bool) {
        guard isExpanded != expanded else { return }
        isExpanded = expanded
        onExpansionChanged?()
    }

    func decide(approved: Bool) {
        guard let approvalID = toolApproval?.metadata["approvalId"], !isResolving else { return }
        errorMessage = nil
        Task { @MainActor in
            await onDecision?(approvalID, approved)
        }
    }

    func openAgentRun(_ run: SloppyDesktopAgentRun) {
        setExpanded(false)
        onOpenAgentRun?(run)
    }

    func openRecentChat(_ chat: SloppyDesktopRecentChat) {
        selectedRecentChatID = nil
        setExpanded(false)
        onOpenRecentChat?(chat)
    }

    func togglePromptComposer(for chat: SloppyDesktopRecentChat) {
        selectedRecentChatID = selectedRecentChatID == chat.id ? nil : chat.id
        promptText = ""
        promptError = nil
        setExpanded(true)
        onExpansionChanged?()
    }

    func submitPrompt(to chat: SloppyDesktopRecentChat) {
        let prompt = promptText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty,
              !isSendingPrompt,
              selectedRecentChatID == chat.id,
              let onSendPrompt else { return }

        isSendingPrompt = true
        promptError = nil
        Task { @MainActor in
            do {
                try await onSendPrompt(chat, prompt)
                promptText = ""
                selectedRecentChatID = nil
            } catch {
                promptError = error.localizedDescription
            }
            isSendingPrompt = false
            onExpansionChanged?()
        }
    }

    func selectProject(id: String) {
        selectedProjectID = projects.contains { $0.id == id } ? id : nil
        taskCreationError = nil
    }

    func updateTaskDraft(_ draft: String) {
        taskDraft = draft
        taskCreationError = nil
    }

    func submitTask() {
        let title = taskDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty,
              !isCreatingTask,
              let selectedProject,
              let onCreateTask else { return }

        isCreatingTask = true
        taskCreationError = nil
        Task { @MainActor in
            do {
                try await onCreateTask(selectedProject, title)
                taskDraft = ""
            } catch {
                taskCreationError = error.localizedDescription
            }
            isCreatingTask = false
            onExpansionChanged?()
        }
    }

    func setActiveTasks(_ tasks: [SloppyDesktopTask]) {
        let previouslyUsedWideLayout = usesWideLayout
        let hadActivity = activityCount > 0
        let hadActiveTasks = !activeTasks.isEmpty
        let tasksChanged = activeTasks != tasks
        activeTasks = tasks
        if !hadActivity && activityCount > 0 {
            revealActivityTemporarily()
        }
        if tasksChanged || previouslyUsedWideLayout != usesWideLayout || hadActiveTasks != !tasks.isEmpty {
            onExpansionChanged?()
        }
    }

    func setActiveAgentRuns(_ runs: [SloppyDesktopAgentRun]) {
        let previouslyUsedWideLayout = usesWideLayout
        let hadActivity = activityCount > 0
        let hadActiveAgentRuns = !activeAgentRuns.isEmpty
        let runsChanged = activeAgentRuns != runs
        activeAgentRuns = runs
        if (!hadActivity && activityCount > 0) || (!hadActiveAgentRuns && !runs.isEmpty) {
            revealActivityTemporarily()
        }
        if runsChanged || previouslyUsedWideLayout != usesWideLayout || hadActivity != (activityCount > 0) {
            onExpansionChanged?()
        }
    }

    func setRecentChats(_ chats: [SloppyDesktopRecentChat]) {
        let previouslyUsedWideLayout = usesWideLayout
        let chatsChanged = recentChats != chats
        recentChats = chats
        if let selectedRecentChatID,
           !chats.contains(where: { $0.id == selectedRecentChatID }) {
            self.selectedRecentChatID = nil
            promptText = ""
            promptError = nil
        }
        if chatsChanged || previouslyUsedWideLayout != usesWideLayout {
            onExpansionChanged?()
        }
    }

    func setProjects(_ projects: [SloppyDesktopProject]) {
        let projectsChanged = self.projects != projects
        self.projects = projects
        if selectedProject == nil {
            selectedProjectID = projects.first?.id
        }
        if projectsChanged {
            onExpansionChanged?()
        }
    }

    private func revealActivityTemporarily() {
        isExpanded = true
        activityRevealToken &+= 1
    }

    func apply(_ notification: AppNotification) {
        guard notification.type == .toolApproval else { return }

        let status = notification.metadata["status"] ?? "pending"
        if status == "pending" {
            toolApproval = notification
            errorMessage = nil
            isExpanded = true
            onExpansionChanged?()
            return
        }
        if toolApproval?.metadata["approvalId"] == notification.metadata["approvalId"] {
            toolApproval = nil
            isExpanded = !activeTasks.isEmpty
            onExpansionChanged?()
        }
    }
}

struct SloppyDesktopTask: Identifiable, Equatable {
    let id: String
    let title: String
    let projectName: String
    let status: ProjectKanbanColumnID

    var statusTitle: String {
        switch status {
        case .inProgress: "In progress"
        case .needsReview: "Needs review"
        case .todo: "To do"
        case .done: "Done"
        case .other: "Other"
        }
    }
}

struct SloppyDesktopProject: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let actorID: String?
}

struct SloppyDesktopAgentRun: Identifiable, Equatable, Sendable {
    let id: String
    let agentID: String
    let sessionID: String
    let sessionTitle: String
    let agentName: String
    let statusLabel: String
    let statusDetails: String?
    let updatedAt: Date

    var subtitle: String {
        let detail = statusDetails?.trimmingCharacters(in: .whitespacesAndNewlines)
        let status = detail?.isEmpty == false ? detail! : statusLabel
        return "\(agentName) · \(status)"
    }
}

struct SloppyDesktopRecentChat: Identifiable, Equatable, Sendable {
    let id: String
    let agentID: String
    let sessionID: String
    let title: String
    let agentName: String
    let updatedAt: Date
}

private struct SloppyDesktopAgentActivity: Sendable {
    let activeRuns: [SloppyDesktopAgentRun]
    let recentChats: [SloppyDesktopRecentChat]
}

private struct SloppyDesktopAgentRunCacheEntry: Sendable {
    let updatedAt: Date
    let run: SloppyDesktopAgentRun?
}

private struct SloppyDesktopAgentRunLookup: Sendable {
    let id: String
    let updatedAt: Date
    let run: SloppyDesktopAgentRun?
}

@MainActor
private struct SloppyDesktopOverlayPreviewCase {
    let title: String
    let state: SloppyDesktopOverlayState

    static var all: [SloppyDesktopOverlayPreviewCase] {
        [
            .init(title: "Collapsed", state: makeState()),
            .init(title: "Running", state: makeState(isExpanded: true)),
            .init(
                title: "Agent working",
                state: makeState(
                    isExpanded: true,
                    activeAgentRuns: makeAgentRuns(),
                    recentChats: makeRecentChats()
                )
            ),
            .init(
                title: "Recent chats",
                state: makeState(isExpanded: true, recentChats: makeRecentChats())
            ),
            .init(
                title: "Active tasks",
                state: makeState(isExpanded: true, activeTasks: makeTasks())
            ),
            .init(
                title: "Tool approval",
                state: makeState(
                    isExpanded: true,
                    approval: makeApproval()
                )
            ),
            .init(
                title: "Tasks and approval",
                state: makeState(
                    isExpanded: true,
                    approval: makeApproval(),
                    activeTasks: makeTasks()
                )
            ),
            .init(
                title: "Resolving approval",
                state: makeState(
                    isExpanded: true,
                    isResolving: true,
                    approval: makeApproval()
                )
            ),
            .init(
                title: "Approval error",
                state: makeState(
                    isExpanded: true,
                    errorMessage: "The backend did not respond. Try again.",
                    approval: makeApproval()
                )
            ),
        ]
    }

    private static func makeState(
        isExpanded: Bool = false,
        isResolving: Bool = false,
        errorMessage: String? = nil,
        approval: AppNotification? = nil,
        activeAgentRuns: [SloppyDesktopAgentRun] = [],
        recentChats: [SloppyDesktopRecentChat] = [],
        activeTasks: [SloppyDesktopTask] = []
    ) -> SloppyDesktopOverlayState {
        let state = SloppyDesktopOverlayState()
        state.isExpanded = isExpanded
        state.isResolving = isResolving
        state.errorMessage = errorMessage
        state.toolApproval = approval
        state.activeAgentRuns = activeAgentRuns
        state.recentChats = recentChats
        state.activeTasks = activeTasks
        state.projects = [
            SloppyDesktopProject(
                id: "sloppy-client",
                name: "Sloppy Client",
                actorID: "sloppy"
            ),
            SloppyDesktopProject(
                id: "ada-engine",
                name: "AdaEngine",
                actorID: "sloppy"
            ),
        ]
        state.selectedProjectID = state.projects.first?.id
        return state
    }

    private static func makeAgentRuns() -> [SloppyDesktopAgentRun] {
        [
            SloppyDesktopAgentRun(
                id: "sloppy/preview-session",
                agentID: "sloppy",
                sessionID: "preview-session",
                sessionTitle: "Fix the desktop Notch status",
                agentName: "Sloppy",
                statusLabel: "Working",
                statusDetails: "Inspecting runtime state",
                updatedAt: Date()
            )
        ]
    }

    private static func makeRecentChats() -> [SloppyDesktopRecentChat] {
        [
            SloppyDesktopRecentChat(
                id: "sloppy/recent-1",
                agentID: "sloppy",
                sessionID: "recent-1",
                title: "Polish the desktop Notch",
                agentName: "Sloppy",
                updatedAt: Date()
            ),
            SloppyDesktopRecentChat(
                id: "reviewer/recent-2",
                agentID: "reviewer",
                sessionID: "recent-2",
                title: "Review overlay interactions",
                agentName: "Reviewer",
                updatedAt: Date().addingTimeInterval(-120)
            ),
            SloppyDesktopRecentChat(
                id: "planner/recent-3",
                agentID: "planner",
                sessionID: "recent-3",
                title: "Plan the next client release",
                agentName: "Planner",
                updatedAt: Date().addingTimeInterval(-240)
            ),
        ]
    }

    private static func makeTasks() -> [SloppyDesktopTask] {
        [
            SloppyDesktopTask(
                id: "preview-task-1",
                title: "Implement backend installer",
                projectName: "Sloppy Client",
                status: .inProgress
            ),
            SloppyDesktopTask(
                id: "preview-task-2",
                title: "Review desktop overlay changes",
                projectName: "Sloppy Client",
                status: .needsReview
            ),
        ]
    }

    private static func makeApproval() -> AppNotification {
        AppNotification(
            id: "preview-tool-approval",
            type: .toolApproval,
            title: "Allow file access?",
            message: "The agent wants to read Package.swift to inspect project dependencies.",
            metadata: [
                "approvalId": "preview-approval-id",
                "status": "pending",
                "tool": "read_file",
            ]
        )
    }
}

#Preview("Overlay states") {
    ScrollView {
        VStack(alignment: .leading, spacing: 28) {
            ForEach(SloppyDesktopOverlayPreviewCase.all, id: \.title) { preview in
                VStack(alignment: .leading, spacing: 8) {
                    Text(preview.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    SloppyDesktopNotchView(state: preview.state)
                        .frame(
                            width: SloppyDesktopNotchView.size(for: preview.state).width,
                            height: SloppyDesktopNotchView.size(for: preview.state).height
                        )
                }
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(width: 720, height: 900)
    .background(.gray.opacity(0.12))
}

#endif

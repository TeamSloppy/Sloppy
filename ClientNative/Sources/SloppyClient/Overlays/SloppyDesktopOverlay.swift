import Foundation
import Observation
import SloppyClientCore
import SloppyClientUI

#if os(macOS)
import AppKit
import SwiftUI

@MainActor
final class SloppyDesktopOverlay {
    private let state = SloppyDesktopOverlayState()
    private weak var window: NSWindow?
    private var overlayPanel: SloppyNotchPanel?
    private var screenObserver: NSObjectProtocol?
    private var apiClient = SloppyAPIClient()
    private var closeBehavior: ClientWindowCloseBehavior = .keepProcess
    private var taskRefreshTask: Task<Void, Never>?

    func start(settings: ClientSettings) {
        closeBehavior = settings.windowCloseBehavior
        apiClient = SloppyAPIClient(baseURL: settings.baseURL)
        state.onDecision = { [weak self] approvalID, approved in
            await self?.resolveApproval(id: approvalID, approved: approved)
        }
        startTaskRefresh()
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
        panel.contentView = NSHostingView(
            rootView: SloppyDesktopNotchView(
                state: state,
                isPointerInsidePanel: { [weak panel] in
                    guard let panel else { return false }
                    return panel.frame.contains(NSEvent.mouseLocation)
                }
            )
        )
        overlayPanel = panel
        state.onExpansionChanged = { [weak self] in
            guard let self, let panel = self.overlayPanel else { return }
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
    }

    private func position(panel: NSPanel, animated: Bool) {
        guard let screen = window?.screen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let size = SloppyDesktopNotchView.size(for: state)
        let frame = NSRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
        panel.setFrame(frame, display: true, animate: animated)
    }

    private func startTaskRefresh() {
        taskRefreshTask?.cancel()
        taskRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshActiveTasks()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private func refreshActiveTasks() async {
        guard let projects = try? await apiClient.fetchProjects() else { return }
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
}

private struct SloppyDesktopNotchView: View {
    static let collapsedSize = CGSize(width: 164, height: 32)
    static let expandedSize = CGSize(width: 340, height: 148)
    static let wideWidth: CGFloat = 520

    static func size(for state: SloppyDesktopOverlayState) -> CGSize {
        guard state.usesWideLayout else {
            return state.isExpanded ? expandedSize : collapsedSize
        }
        guard state.isExpanded else {
            return CGSize(width: wideWidth, height: collapsedSize.height)
        }
        let taskHeight = CGFloat(min(state.activeTasks.count, 3)) * 42
        let approvalHeight: CGFloat = state.toolApproval == nil ? 0 : 132
        let sectionSpacing: CGFloat = state.toolApproval != nil && !state.activeTasks.isEmpty ? 14 : 0
        return CGSize(
            width: wideWidth,
            height: min(330, 64 + taskHeight + approvalHeight + sectionSpacing)
        )
    }

    let state: SloppyDesktopOverlayState
    let isPointerInsidePanel: @MainActor () -> Bool
    @State private var isHovered = false
    @State private var hoverCollapseTask: Task<Void, Never>?

    init(
        state: SloppyDesktopOverlayState,
        isPointerInsidePanel: @escaping @MainActor () -> Bool = { false }
    ) {
        self.state = state
        self.isPointerInsidePanel = isPointerInsidePanel
    }

    var body: some View {
        VStack(spacing: 0) {
            Button {
                state.toggleExpanded()
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: state.toolApproval == nil ? "waveform.path.ecg" : "exclamationmark.shield.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(state.toolApproval == nil ? .green : .orange)
                    Text(compactTitle)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 2)
                    if !state.activeTasks.isEmpty {
                        Label("\(state.activeTasks.count)", systemImage: "bolt.fill")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.cyan)
                            .labelStyle(.titleAndIcon)
                    }
                    Image(systemName: state.isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .frame(height: Self.collapsedSize.height)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if state.isExpanded {
                Divider().opacity(0.35)
                expandedContent
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
        .animation(.snappy(duration: 0.22), value: state.isExpanded)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sloppy desktop notch")
    }

    private var compactTitle: String {
        state.toolApproval?.metadata["tool"] ?? (state.toolApproval == nil ? "Sloppy" : "Approval required")
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
        guard state.toolApproval == nil && state.activeTasks.isEmpty else { return }

        hoverCollapseTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(120))
                guard !Task.isCancelled else { return }
                guard state.toolApproval == nil && state.activeTasks.isEmpty else { return }
                guard !isPointerInsidePanel() else { continue }

                isHovered = false
                state.setExpanded(false)
                return
            }
        }
    }

    @ViewBuilder
    private var expandedContent: some View {
        if state.usesWideLayout {
            VStack(alignment: .leading, spacing: 10) {
                if let approval = state.toolApproval {
                    approvalContent(approval)
                }
                if state.toolApproval != nil && !state.activeTasks.isEmpty {
                    Divider().opacity(0.35)
                }
                if !state.activeTasks.isEmpty {
                    activeTasksContent
                }
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
    var activeTasks: [SloppyDesktopTask] = []
    var isExpanded = false
    var isResolving = false
    var errorMessage: String?
    var onExpansionChanged: (@MainActor () -> Void)?
    var onDecision: (@MainActor (String, Bool) async -> Void)?

    var usesWideLayout: Bool {
        toolApproval != nil || !activeTasks.isEmpty
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

    func setActiveTasks(_ tasks: [SloppyDesktopTask]) {
        let previouslyUsedWideLayout = usesWideLayout
        let hadActiveTasks = !activeTasks.isEmpty
        let tasksChanged = activeTasks != tasks
        activeTasks = tasks
        if !hadActiveTasks && !tasks.isEmpty {
            isExpanded = true
        }
        if tasksChanged || previouslyUsedWideLayout != usesWideLayout || hadActiveTasks != !tasks.isEmpty {
            onExpansionChanged?()
        }
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


@MainActor
private struct SloppyDesktopOverlayPreviewCase {
    let title: String
    let state: SloppyDesktopOverlayState

    static var all: [SloppyDesktopOverlayPreviewCase] {
        [
            .init(title: "Collapsed", state: makeState()),
            .init(title: "Running", state: makeState(isExpanded: true)),
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
        activeTasks: [SloppyDesktopTask] = []
    ) -> SloppyDesktopOverlayState {
        let state = SloppyDesktopOverlayState()
        state.isExpanded = isExpanded
        state.isResolving = isResolving
        state.errorMessage = errorMessage
        state.toolApproval = approval
        state.activeTasks = activeTasks
        return state
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

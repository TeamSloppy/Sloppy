#if os(macOS)
import SwiftUI
import SloppyClientCore
import SloppyClientUI
import SloppyFeatureChat

/// Persistent workspace summary, independent of the active screen and tool dock.
@MainActor
struct DesktopWorkspaceInspector: View {
    let apiClient: SloppyAPIClient
    let chat: ChatScreenViewModel?
    let context: WorkspacePanelContext?
    let onOpenTool: @MainActor (WorkspaceSidePanelItem) -> Void
    let onOpenOutput: @MainActor (String) -> Void
    let projectNavigation: ProjectModeCommandContext?
    let observesWorkers: Bool
    let onOpenWorker: (@MainActor (ChatSessionSummary) -> Void)?

    @State private var panel: WorkspacePanelViewModel
    @State private var showsAllOutputs = false
    @Environment(\.theme) private var theme

    init(apiClient: SloppyAPIClient, chat: ChatScreenViewModel? = nil, context: WorkspacePanelContext?,
         projectNavigation: ProjectModeCommandContext? = nil,
         observesWorkers: Bool = false,
         onOpenWorker: (@MainActor (ChatSessionSummary) -> Void)? = nil,
         onOpenTool: @escaping @MainActor (WorkspaceSidePanelItem) -> Void,
         onOpenOutput: @escaping @MainActor (String) -> Void) {
        self.apiClient = apiClient
        self.chat = chat
        self.context = context
        self.onOpenTool = onOpenTool
        self.onOpenOutput = onOpenOutput
        self.projectNavigation = projectNavigation
        self.observesWorkers = observesWorkers
        self.onOpenWorker = onOpenWorker
        _panel = State(initialValue: WorkspacePanelViewModel(apiClient: apiClient))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Menu {
                        ForEach(WorkspaceSidePanelItem.allCases) { item in
                            Button { onOpenTool(item) } label: { Label(item.title, systemImage: item.systemImage) }
                                .disabled(item.requiresProject && context == nil)
                        }
                    } label: { Label("Tools", systemImage: "plus") }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .accessibilityIdentifier("chat.inspector.tools")
                    Spacer()
                    Text("Workspace")
                        .accessibilityAddTraits(.isHeader)
                }
                .font(.caption)
                .foregroundStyle(theme.colors.textMuted)

                if let projectNavigation {
                    ProjectModeNavigationCard(
                        title: context?.projectName ?? "Project",
                        selectedSection: projectNavigation.selectedSection,
                        onSelect: projectNavigation.select
                    )
                }
                if context != nil {
                    environment.desktopEnvironmentCard
                } else {
                    block("Environment") {
                        Label(apiClient.baseURL.host ?? "Server", systemImage: "desktopcomputer")
                            .font(.callout)
                            .textSelection(.enabled)
                    }
                }
                if let usage = chat?.contextUsage {
                    block("Context", trailing: "\(usage.percentage)%") {
                        ProgressView(value: usage.fraction)
                            .tint(theme.colors.textSecondary)
                            .accessibilityLabel("Model context")
                            .accessibilityValue("\(usage.percentage) percent")
                        Text("\(usage.usedTokens.formatted()) of \(usage.limitTokens.formatted()) tokens")
                            .font(.caption)
                            .foregroundStyle(theme.colors.textMuted)
                    }
                }
                if let chat, !chat.parallelAgents.agents.isEmpty {
                    ChatWorkerActivityPanel(workers: chat.parallelAgents.agents) { id in
                        if let onOpenWorker,
                           let worker = chat.parallelAgents.agents.first(where: { $0.summary.id == id }) {
                            onOpenWorker(worker.summary)
                        } else {
                            chat.openLongChatWorker(id)
                        }
                    }
                }
                if !outputs.isEmpty {
                    block("Outputs") {
                        ForEach(Array((showsAllOutputs ? outputs : Array(outputs.prefix(5))).enumerated()), id: \.offset) { _, attachment in
                            outputRow(attachment)
                        }
                        if outputs.count > 5 {
                            Button(showsAllOutputs ? "Show less" : "Show more") { showsAllOutputs.toggle() }
                                .buttonStyle(.plain)
                                .font(.caption)
                        }
                    }
                }
                if context != nil || chat?.workingTreeSourceControl != nil {
                    environment.desktopChangesCard
                }
                if let progress = latestProgress {
                    block(progress.title) {
                        ForEach(progress.items) { item in
                            Label(item.title, systemImage: progressSymbol(item.status))
                                .font(.caption)
                                .foregroundStyle(theme.colors.textSecondary)
                                .accessibilityLabel("\(item.title): \(item.status.rawValue)")
                        }
                    }
                }
            }
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .accessibilityIdentifier("workspace.desktop-inspector")
        .task(id: context) {
            if let context { panel.activate(context: context) }
        }
        .task(id: WorkerObservationID(owner: chat.map(ObjectIdentifier.init), agent: chat?.selectedAgent?.id,
                                     session: chat?.selectedSessionId, isEnabled: observesWorkers)) {
            guard observesWorkers, let chat else { return }
            await chat.parallelAgents.observe(agentID: chat.selectedAgent?.id, sessionID: chat.selectedSessionId)
        }
        .onChange(of: chat.map(ObjectIdentifier.init)) { _, _ in
            showsAllOutputs = false
        }
        .onChange(of: chat?.workingTreeSourceControl, initial: true) { _, sourceControl in
            if let sourceControl { panel.synchronizeSourceControl(sourceControl) }
        }
    }

    private var environment: WorkspaceEnvironmentPanelView {
        WorkspaceEnvironmentPanelView(viewModel: panel, onOpenTerminal: { onOpenTool(.terminal) })
    }

    private struct WorkerObservationID: Hashable {
        let owner: ObjectIdentifier?
        let agent: String?
        let session: String?
        let isEnabled: Bool
    }

    private var outputs: [ChatAttachment] {
        DesktopChatOutputs.attachments(in: chat?.transcript.messages ?? [])
    }

    private var latestProgress: ChatBuildProgress? {
        for message in (chat?.transcript.messages ?? []).reversed() {
            for segment in message.segments.reversed() {
                if let progress = segment.buildProgress { return progress }
            }
        }
        return nil
    }

    private func outputRow(_ attachment: ChatAttachment) -> some View {
        Button {
            if let path = attachment.relativePath { onOpenOutput(path) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: attachment.mimeType.hasPrefix("image/") ? "photo" : "doc")
                Text(attachment.name).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 4)
                Text(ByteCountFormatter.string(fromByteCount: Int64(attachment.sizeBytes), countStyle: .file))
                    .font(.caption2).foregroundStyle(theme.colors.textMuted)
            }
            .font(.callout)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .disabled(attachment.relativePath == nil)
        .help(attachment.name)
    }

    private func block<Content: View>(_ title: String, trailing: String? = nil,
                                      @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title).font(.callout.weight(.medium))
                Spacer(minLength: 0)
                if let trailing { Text(trailing).font(.caption) }
            }
            .foregroundStyle(theme.colors.textSecondary)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.colors.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12).strokeBorder(theme.colors.border, lineWidth: 1)
                .allowsHitTesting(false)
        }
    }

    private func progressSymbol(_ status: ChatBuildProgressStatus) -> String {
        switch status {
        case .done: "checkmark.circle"
        case .inProgress: "circle.dotted"
        case .blocked: "exclamationmark.circle"
        case .pending: "circle"
        case .skipped: "minus.circle"
        }
    }
}

enum DesktopChatOutputs {
    static func attachments(in messages: [ChatMessage]) -> [ChatAttachment] {
        var attachments: [ChatAttachment] = []
        var indices: [String: Int] = [:]
        for message in messages where message.role != .user {
            for segment in message.segments {
                guard let attachment = segment.attachment else { continue }
                if let index = indices[attachment.id] {
                    attachments[index] = attachment
                } else {
                    indices[attachment.id] = attachments.count
                    attachments.append(attachment)
                }
            }
        }
        return attachments
    }
}
#endif

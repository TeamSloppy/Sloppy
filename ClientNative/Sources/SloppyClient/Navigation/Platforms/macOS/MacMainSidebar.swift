#if os(macOS)
import Foundation
import SloppyClientCore
import SloppyClientUI
import SwiftUI

@MainActor
struct PlatformMainSidebar: View {
    let viewModel: MainViewModel
    let isOverlay: Bool
    var composerBackdropHeight: CGFloat? = nil
    var approvalRequiredSessionIDs: Set<String> = []
    var showsApprovalRequiredChatsOnly = false

    @Environment(\.theme) private var theme
    @State private var isSettingsHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("sloppy.")
                .font(.system(size: 29, weight: .heavy))
                .tracking(-1.2)
                .foregroundStyle(theme.colors.textPrimary)
                .padding(.horizontal, theme.spacing.m)
                .padding(.top, theme.spacing.s)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("sidebar.wordmark")

            ScrollView {
                MacSidebarPrimaryActions(viewModel: viewModel)

                if !viewModel.settings.hiddenSidebarItems.contains("agents") {
                    SidebarAgentsSection(
                        agents: viewModel.chatViewModel.agents,
                        selectedAgentID: viewModel.sidebarSelectedAgentID,
                        isLoading: !viewModel.chatViewModel.didLoadInitialData,
                        errorMessage: viewModel.sidebarAgentChatError,
                        onSelect: viewModel.selectSidebarAgent,
                        onInfo: viewModel.showSidebarAgentInfo
                    )
                }

                SidebarRecentsList(
                    viewModel: viewModel,
                    approvalRequiredSessionIDs: approvalRequiredSessionIDs,
                    showsApprovalRequiredOnly: showsApprovalRequiredChatsOnly
                )
            }
            .frame(maxHeight: .infinity)
            .modifier(SidebarScrollFade())
            .refreshable { await viewModel.refreshContent() }
        }
        .background(theme.colors.surfaceGlass)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: theme.spacing.s) {
                    Menu {
                        Button {
                            viewModel.selectInstance(.all)
                        } label: {
                            instanceMenuLabel(
                                title: "All",
                                systemImage: "square.stack.3d.up",
                                isSelected: viewModel.settings.instanceSelection == .all
                            )
                        }

                        Divider()

                        ForEach(viewModel.settings.discoveredInstances) { instance in
                            Button {
                                viewModel.selectInstance(.instance(instance.id))
                            } label: {
                                instanceMenuLabel(
                                    title: instance.displayName,
                                    systemImage: instance.isLocal ? "desktopcomputer" : "network",
                                    isSelected: viewModel.settings.instanceSelection == .instance(instance.id)
                                )
                            }
                        }

                        Divider()

                        Button("Connect via Relay…") {
                            viewModel.onOpenWorkspace()
                        }
                        .accessibilityIdentifier("sidebar.connectRelay")

                        Button("Manage Instances…") {
                            viewModel.onOpenSettings(.general)
                        }
                    } label: {
                        HStack(spacing: theme.spacing.s) {
                            Image(systemName: selectedInstanceSystemImage)
                                .font(.system(size: theme.typography.body, weight: .semibold))
                                .foregroundColor(theme.colors.textPrimary)
                                .frame(width: 32, height: 32)
                                .background(theme.colors.surfaceRaised, in: Circle())

                            VStack(alignment: .leading, spacing: 2) {
                                Text(viewModel.selectedInstanceTitle)
                                    .font(.system(size: theme.typography.body, weight: .medium))
                                    .foregroundColor(theme.colors.textPrimary)
                                    .lineLimit(1)

                                Text(selectedInstanceSubtitle)
                                    .font(.system(size: theme.typography.micro))
                                    .foregroundColor(theme.colors.textMuted)
                                    .lineLimit(1)
                            }

                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: theme.typography.micro, weight: .semibold))
                                .foregroundColor(theme.colors.textMuted)
                        }
                        .contentShape(Rectangle())
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: theme.spacing.s)

                    SidebarConnectionStatus(monitor: viewModel.connectionMonitor)

                    SloppyUpdateReminderView()

                    SidebarCustomizationMenu(settings: viewModel.settings)

                    Button {
                        viewModel.onOpenSettings(.account)
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: theme.typography.heading))
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(SidebarHoverButtonStyle(isHovered: isSettingsHovered))
                    .onHover { isSettingsHovered = $0 }
                    .help("Open settings")
                    .accessibilityLabel("Open settings")
                }
                .buttonStyle(.borderless)
                .padding(.horizontal, theme.spacing.m)
                .frame(maxWidth: .infinity, minHeight: 64)
            }
            .background {
                SidebarFooterBackground()
            }
        }
    }

    private var selectedInstanceSystemImage: String {
        guard let instance = viewModel.selectedInstance else {
            return "square.stack.3d.up"
        }
        return instance.isLocal ? "desktopcomputer" : "network"
    }

    private var selectedInstanceSubtitle: String {
        guard let instance = viewModel.selectedInstance else {
            let count = viewModel.settings.discoveredInstances.count
            return "\(count) \(count == 1 ? "instance" : "instances")"
        }
        if instance.isLocal { return "Local" }
        return instance.status == .online ? "Relay · Online" : "Relay · Offline"
    }

    private func instanceMenuLabel(title: String, systemImage: String, isSelected: Bool) -> some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: isSelected ? "checkmark" : systemImage)
        }
    }
}

@MainActor
private struct MacSidebarPrimaryActions: View {
    let viewModel: MainViewModel

    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !viewModel.settings.hiddenSidebarItems.contains("newChat") {
                SidebarNavigationRow(
                    icon: .new,
                    title: "New chat",
                    isSelected: false,
                    navigationValue: .chats,
                    action: viewModel.selectNewChat
                )
            }

            if !viewModel.settings.hiddenSidebarItems.contains("attention") {
                TimelineView(.periodic(from: .now, by: 30)) { timeline in
                    SidebarNavigationRow(
                        icon: .attention,
                        title: "Attention",
                        badgeCount: viewModel.attentionInbox.unreadCount(at: timeline.date),
                        isSelected: viewModel.selectedAppSection == .attention,
                        navigationValue: .attention,
                        action: viewModel.selectAttention
                    )
                    .accessibilityIdentifier("sidebar.attention")
                }
            }

            if !viewModel.settings.hiddenSidebarItems.contains("sites") {
                SidebarNavigationRow(
                    icon: .language,
                    title: "Sites",
                    isSelected: viewModel.selectedAppSection == .sites,
                    navigationValue: .sites,
                    action: viewModel.selectSites
                )
            }

            if !viewModel.settings.hiddenSidebarItems.contains("pullRequests") {
                SidebarNavigationRow(
                    icon: .pullRequest,
                    title: "Pull Requests",
                    isSelected: viewModel.selectedAppSection == .pullRequests,
                    navigationValue: .pullRequests,
                    action: viewModel.selectPullRequests
                )
            }

            if !viewModel.settings.hiddenSidebarItems.contains("scheduled") {
                SidebarNavigationRow(
                    icon: .timer,
                    title: "Scheduled",
                    isSelected: viewModel.selectedAppSection == .scheduled,
                    navigationValue: .scheduled,
                    action: viewModel.selectScheduled
                )
            }

            if !viewModel.settings.hiddenSidebarItems.contains("workspace") {
                SidebarNavigationRow(
                    icon: .workspace,
                    title: "Workspace",
                    isSelected: viewModel.selectedAppSection == .workspace,
                    action: viewModel.selectWorkspace
                )
            }

            if !viewModel.settings.hiddenSidebarItems.contains("artifacts") {
                SidebarNavigationRow(
                    icon: .description,
                    title: "Artifacts",
                    isSelected: viewModel.selectedAppSection == .artifacts,
                    navigationValue: .artifacts,
                    action: viewModel.selectArtifacts
                )
            }
        }
        .padding(.horizontal, theme.spacing.xs)
    }
}

@MainActor
private struct SidebarConnectionStatus: View {
    let monitor: ConnectionMonitor
    @State private var showsDetails = false
    @State private var detailsPinned = false

    private var status: (title: String, symbol: String, color: Color) {
        switch monitor.state {
        case .connected: ("Connected", "circle.fill", .green)
        case .reconnecting: ("Connecting", "circle.dotted", .orange)
        case .disconnected: ("Offline", "circle.slash", .red)
        }
    }

    var body: some View {
        Button {
            detailsPinned = true
            showsDetails = true
        } label: {
            ViewThatFits(in: .horizontal) {
                Label {
                    Text(status.title).foregroundStyle(.secondary)
                } icon: {
                    statusIcon
                }
                .fixedSize()
                statusIcon
            }
            .font(.caption)
            .frame(minWidth: 22, minHeight: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Server connection: \(status.title)")
        .accessibilityIdentifier("sidebar.connection")
        .onHover { hovering in
            if !detailsPinned { showsDetails = hovering }
        }
        .onChange(of: showsDetails) { _, shown in
            if !shown { detailsPinned = false }
        }
        .popover(isPresented: $showsDetails, arrowEdge: .bottom) {
            details
        }
    }

    private var statusIcon: some View {
        Image(systemName: status.symbol)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(status.color)
    }

    private var details: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let traffic = monitor.trafficSnapshot()
            let url = monitor.endpoint.coordinatorBaseURL
            VStack(alignment: .leading, spacing: 8) {
                Label {
                    Text(status.title).font(.headline)
                } icon: {
                    statusIcon
                }
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                    metric("Server", (url.host ?? "Unknown") + (url.port.map { ":\($0)" } ?? ""))
                    metric("Transport", transportTitle)
                    metric("Open event streams", traffic.openEventStreams.formatted())
                    metric("Active API requests", traffic.requestsInFlight.formatted())
                    metric("Sent payload", traffic.sentBytes.formatted(.byteCount(style: .file)))
                    metric("Received payload", traffic.receivedBytes.formatted(.byteCount(style: .file)))
                    if let duration = monitor.lastSuccessfulCheckDuration {
                        let milliseconds = duration / .milliseconds(1)
                        metric("Health check latency", "\(milliseconds.formatted(.number.precision(.fractionLength(0)))) ms")
                    }
                    if let date = monitor.lastCheckedAt {
                        metric("Last checked", date.formatted(date: .omitted, time: .standard))
                    }
                }
                if let error = monitor.lastFailureMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let requestID = monitor.lastFailedRequestID {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Last failed check ID")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(requestID.uuidString.lowercased())
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .accessibilityIdentifier("sidebar.connection.failed-request-id")
                    }
                }
            }
            .frame(width: 270, alignment: .leading)
            .padding(14)
        }
    }

    private var transportTitle: String {
        switch monitor.endpoint {
        case .direct: "Direct"
        case .relay: "Mesh relay"
        case .managed: "Managed relay"
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary)
            Text(value).monospacedDigit().lineLimit(1).truncationMode(.middle)
        }
        .font(.caption)
    }
}

@MainActor
private struct SidebarCustomizationMenu: View {
    let settings: ClientSettings

    @Environment(\.theme) private var theme

    var body: some View {
        Menu {
            Toggle("New chat", isOn: visibility(for: "newChat"))
            Toggle("Attention", isOn: visibility(for: "attention"))
            Toggle("Sites", isOn: visibility(for: "sites"))
            Toggle("Pull Requests", isOn: visibility(for: "pullRequests"))
            Toggle("Scheduled", isOn: visibility(for: "scheduled"))
            Toggle("Agents", isOn: visibility(for: "agents"))
            Toggle("Workspace", isOn: visibility(for: "workspace"))
            Toggle("Artifacts", isOn: visibility(for: "artifacts"))
            Divider()
            Button("Restore Default Sidebar") { settings.hiddenSidebarItems = [] }
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: theme.typography.heading))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Customize sidebar")
        .accessibilityLabel("Customize sidebar")
    }

    private func visibility(for item: String) -> Binding<Bool> {
        Binding(
            get: { !settings.hiddenSidebarItems.contains(item) },
            set: { isVisible in
                if isVisible {
                    settings.hiddenSidebarItems.remove(item)
                } else {
                    settings.hiddenSidebarItems.insert(item)
                }
            }
        )
    }
}

#Preview("macOS Sidebar") {
    PlatformMainSidebar(viewModel: .preview(), isOverlay: false)
        .frame(width: 348, height: 700)
}
#endif

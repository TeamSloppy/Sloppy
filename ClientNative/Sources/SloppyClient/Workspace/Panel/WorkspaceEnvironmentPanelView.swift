import SwiftUI
import SloppyClientCore
import SloppyClientUI

@MainActor
struct WorkspaceEnvironmentPanelView: View {
    let viewModel: WorkspacePanelViewModel
    let onOpenTerminal: (@MainActor () -> Void)?

    @State private var areChangesExpanded = true
    @Environment(\.theme) private var theme

    private var sourceControl: ProjectWorkingTreeSourceControlResponse? {
        viewModel.sourceControl
    }

    private var fileChanges: [ProjectSourceControlFileChange] {
        sourceControl?.fileChanges ?? []
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.spacing.m) {
                environmentCard
                projectCard
            }
            .padding(theme.spacing.m)
        }
        .accessibilityIdentifier("workspace.environment-panel")
    }

    private var environmentCard: some View {
        panelCard {
            VStack(alignment: .leading, spacing: 0) {
                changesSection

                Divider()
                    .padding(.vertical, theme.spacing.s)

                environmentRow(
                    title: environmentTitle,
                    detail: endpointLabel,
                    systemImage: "laptopcomputer",
                    trailingSystemImage: "chevron.down"
                )

                environmentRow(
                    title: sourceControl?.providerId.capitalized ?? "Source control",
                    detail: sourceControl?.isRepository == true ? "Repository detected" : "Repository unavailable",
                    systemImage: "point.3.connected.trianglepath.dotted"
                )

                environmentRow(
                    title: sourceControl?.branch ?? "Unknown branch",
                    detail: "Current branch",
                    systemImage: "arrow.triangle.branch",
                    trailingSystemImage: "chevron.down"
                )

                Button {
                    onOpenTerminal?()
                } label: {
                    environmentRow(
                        title: "Commit or push",
                        detail: onOpenTerminal == nil ? "Terminal unavailable" : "Open project terminal",
                        systemImage: "point.topleft.down.to.point.bottomright.curvepath"
                    )
                }
                .buttonStyle(.plain)
                .disabled(onOpenTerminal == nil)

                environmentRow(
                    title: "Pull request status unavailable",
                    detail: "No remote pull-request provider",
                    systemImage: "arrow.triangle.pull",
                    isEnabled: false
                )

                environmentRow(
                    title: "Compare branch",
                    detail: "Remote comparison unavailable",
                    systemImage: "arrow.left.arrow.right",
                    trailingSystemImage: "arrow.up.right",
                    isEnabled: false
                )
            }
        }
    }

    private var changesSection: some View {
        VStack(alignment: .leading, spacing: theme.spacing.s) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    areChangesExpanded.toggle()
                }
            } label: {
                HStack(spacing: theme.spacing.s) {
                    Image(systemName: "doc.badge.plus")
                        .foregroundColor(theme.colors.textSecondary)
                        .frame(width: 20)

                    Text("Changes")
                        .font(.system(size: theme.typography.body, weight: .medium))
                        .foregroundColor(theme.colors.textPrimary)

                    Spacer(minLength: theme.spacing.s)

                    if let sourceControl {
                        changeCounts(
                            added: sourceControl.linesAdded,
                            deleted: sourceControl.linesDeleted
                        )
                    } else if viewModel.isLoadingEnvironment {
                        ProgressView()
                            .controlSize(.small)
                    }

                    Image(systemName: areChangesExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: theme.typography.micro, weight: .semibold))
                        .foregroundColor(theme.colors.textMuted)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if areChangesExpanded {
                if let error = viewModel.environmentLoadError {
                    Text(error)
                        .font(.system(size: theme.typography.caption))
                        .foregroundColor(theme.colors.statusBlocked)
                        .padding(.leading, 28)
                } else if sourceControl == nil {
                    Text("Source-control information unavailable.")
                        .font(.system(size: theme.typography.caption))
                        .foregroundColor(theme.colors.textMuted)
                        .padding(.leading, 28)
                } else if fileChanges.isEmpty {
                    Text(sourceControl?.hasChanges == true ? "Changed files are unavailable." : "Working tree is clean.")
                        .font(.system(size: theme.typography.caption))
                        .foregroundColor(theme.colors.textMuted)
                        .padding(.leading, 28)
                } else {
                    VStack(alignment: .leading, spacing: theme.spacing.s) {
                        ForEach(fileChanges) { change in
                            HStack(spacing: theme.spacing.s) {
                                Text(change.path)
                                    .font(.system(size: theme.typography.micro, design: .monospaced))
                                    .foregroundColor(theme.colors.textSecondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)

                                Spacer(minLength: theme.spacing.xs)

                                changeCounts(added: change.linesAdded, deleted: change.linesDeleted)
                            }
                        }
                    }
                    .padding(.leading, 28)
                }
            }
        }
    }

    private var projectCard: some View {
        panelCard {
            VStack(alignment: .leading, spacing: theme.spacing.m) {
                HStack {
                    Text("Project")
                        .font(.system(size: theme.typography.body, weight: .semibold))
                        .foregroundColor(theme.colors.textPrimary)

                    Spacer(minLength: 0)

                    Button {
                        Task { await viewModel.refreshEnvironment() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(theme.colors.textSecondary)
                    .help("Refresh environment")
                }

                environmentRow(
                    title: viewModel.project?.name ?? viewModel.context?.projectName ?? "Project",
                    detail: viewModel.project?.projectRootPath ?? "Workspace path unavailable",
                    systemImage: "folder"
                )
            }
        }
    }

    private func panelCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(theme.spacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.colors.surfaceRaised.opacity(0.78 as CGFloat))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(theme.colors.border, lineWidth: theme.borders.thin)
            }
    }

    private func environmentRow(
        title: String,
        detail: String,
        systemImage: String,
        trailingSystemImage: String? = nil,
        isEnabled: Bool = true
    ) -> some View {
        HStack(spacing: theme.spacing.s) {
            Image(systemName: systemImage)
                .font(.system(size: theme.typography.body))
                .foregroundColor(isEnabled ? theme.colors.textSecondary : theme.colors.textMuted)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: theme.typography.body))
                    .foregroundColor(isEnabled ? theme.colors.textPrimary : theme.colors.textMuted)
                    .lineLimit(1)

                Text(detail)
                    .font(.system(size: theme.typography.micro))
                    .foregroundColor(theme.colors.textMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: theme.spacing.s)

            if let trailingSystemImage {
                Image(systemName: trailingSystemImage)
                    .font(.system(size: theme.typography.micro, weight: .semibold))
                    .foregroundColor(theme.colors.textMuted)
            }
        }
        .padding(.vertical, theme.spacing.s)
        .contentShape(Rectangle())
    }

    private func changeCounts(added: Int, deleted: Int) -> some View {
        HStack(spacing: theme.spacing.xs) {
            Text("+\(added)")
                .foregroundColor(theme.colors.statusDone)
            Text("-\(deleted)")
                .foregroundColor(theme.colors.statusBlocked)
        }
        .font(.system(size: theme.typography.caption, weight: .medium, design: .monospaced))
        .fixedSize()
    }

    private var environmentTitle: String {
        ServerAddress.isLoopbackHost(viewModel.apiClient.baseURL.host) ? "Local" : "Remote"
    }

    private var endpointLabel: String {
        let baseURL = viewModel.apiClient.baseURL
        guard let host = baseURL.host else { return baseURL.absoluteString }
        if let port = baseURL.port {
            return "\(host):\(port)"
        }
        return host
    }
}

#Preview {
    WorkspaceEnvironmentPanelView(
        viewModel: WorkspacePanelViewModel(
            apiClient: SloppyAPIClient(baseURL: URL(string: "http://localhost:25101")!)
        ),
        onOpenTerminal: {}
    )
    .frame(width: 380, height: 720)
}

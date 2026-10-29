import SwiftUI
import SloppyClientCore
import SloppyClientUI

@MainActor
struct WorkspaceEnvironmentPanelView: View {
    let viewModel: WorkspacePanelViewModel
    let onOpenTerminal: (@MainActor () -> Void)?

    @Environment(\.theme) private var theme
    @Environment(\.openURL) private var openURL

    private var sourceControl: ProjectWorkingTreeSourceControlResponse? {
        viewModel.sourceControl
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.spacing.m) {
#if os(macOS)
                desktopEnvironmentCard
                desktopChangesCard
#else
                environmentCard
                projectCard
#endif
            }
            .padding(theme.spacing.m)
        }
        .mobileRefreshable { await viewModel.refreshEnvironment() }
        .accessibilityIdentifier("workspace.environment-panel")
    }

    var desktopEnvironmentCard: some View {
        panelCard {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Environment").font(.callout.weight(.medium))
                    Spacer()
#if !os(iOS)
                    Button { Task { await viewModel.refreshEnvironment() } } label: {
                        Image(systemName: "arrow.clockwise").font(.caption)
                    }
                    .buttonStyle(.plain)
                    .help("Refresh environment")
                    .accessibilityLabel("Refresh environment")
#endif
                }
                .foregroundStyle(theme.colors.textSecondary)
                environmentRow(title: environmentTitle, detail: endpointLabel, systemImage: "desktopcomputer")
                environmentRow(
                    title: viewModel.project?.name ?? viewModel.context?.projectName ?? "Project",
                    detail: viewModel.project?.projectRootPath ?? "Workspace path unavailable",
                    systemImage: "folder"
                )
                environmentRow(
                    title: sourceControl?.branch ?? "Unknown branch",
                    detail: sourceControlProviderTitle,
                    systemImage: "arrow.triangle.branch"
                )
                Button { onOpenTerminal?() } label: {
                    Label("Open project terminal", systemImage: "terminal")
                        .font(.caption)
                        .foregroundStyle(theme.colors.textSecondary)
                }
                .buttonStyle(.plain)
                .disabled(onOpenTerminal == nil)
            }
        }
        .accessibilityIdentifier("workspace.inspector.environment")
    }

    var desktopChangesCard: some View {
        panelCard {
            VStack(alignment: .leading, spacing: theme.spacing.s) {
                changesSection
                codeReviewRows
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("workspace.inspector.changes")
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
                    title: sourceControlProviderTitle,
                    detail: sourceControlDetail,
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

                codeReviewRows
            }
        }
    }

    @ViewBuilder
    private var codeReviewRows: some View {
        if let review = viewModel.codeReview, let url = URL(string: review.url) {
            Button { openURL(url) } label: {
                environmentRow(
                    title: reviewTitle(review),
                    detail: review.title,
                    systemImage: "arrow.triangle.pull",
                    trailingSystemImage: "arrow.up.right"
                )
            }
            .buttonStyle(.plain)

            Button { openURL(url) } label: {
                environmentRow(
                    title: reviewBranchTitle(review),
                    detail: "Open review comparison",
                    systemImage: "arrow.left.arrow.right",
                    trailingSystemImage: "arrow.up.right"
                )
            }
            .buttonStyle(.plain)
        } else {
            environmentRow(
                title: viewModel.codeReviewLoadError == nil ? "No open review" : "Review unavailable",
                detail: viewModel.codeReviewLoadError ?? noReviewDetail,
                systemImage: "arrow.triangle.pull",
                isEnabled: false
            )
        }
    }

    private var changesSection: some View {
        VStack(alignment: .leading, spacing: theme.spacing.s) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    viewModel.areChangesExpanded.toggle()
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

                    if sourceControl != nil || !viewModel.directoryChanges.isEmpty {
                        changeCounts(
                            added: viewModel.changesLinesAdded,
                            deleted: viewModel.changesLinesDeleted
                        )
                    } else if viewModel.isLoadingEnvironment {
                        ProgressView()
                            .controlSize(.small)
                    }

                    Image(systemName: viewModel.areChangesExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: theme.typography.micro, weight: .semibold))
                        .foregroundColor(theme.colors.textMuted)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("workspace.changes.toggle")
            .accessibilityValue(viewModel.areChangesExpanded ? "Expanded" : "Collapsed")

            if viewModel.areChangesExpanded {
                if !viewModel.directoryChanges.isEmpty {
                    ForEach(viewModel.directoryChanges) { directory in
                        VStack(alignment: .leading, spacing: theme.spacing.s) {
                            Text(directory.path)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(theme.colors.textSecondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .help(directory.path)
                            changedFiles(directory.sourceControl)
                        }
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("workspace.changes.directory.\(directory.path)")
                    }
                } else {
                    changedFiles(sourceControl)
                }
            }
        }
    }

    @ViewBuilder
    private func changedFiles(_ sourceControl: ProjectWorkingTreeSourceControlResponse?) -> some View {
        if let message = sourceControl?.message ?? (sourceControl == nil ? viewModel.environmentLoadError : nil) {
            Text(message)
                .font(.system(size: theme.typography.caption))
                .foregroundStyle(theme.colors.statusBlocked)
                .padding(.leading, 28)
        } else if let sourceControl {
            let fileChanges = sourceControl.fileChanges
            if fileChanges.isEmpty {
                Text(sourceControl.hasChanges ? "Changed files are unavailable." : "Working tree is clean.")
                    .font(.system(size: theme.typography.caption))
                    .foregroundStyle(theme.colors.textMuted)
                    .padding(.leading, 28)
            } else {
                VStack(alignment: .leading, spacing: theme.spacing.s) {
                    ForEach(fileChanges) { change in
                        HStack(spacing: theme.spacing.s) {
                            Text(change.path)
                                .font(.system(size: theme.typography.micro, design: .monospaced))
                                .foregroundStyle(theme.colors.textSecondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .help(change.path)
                            Spacer(minLength: theme.spacing.xs)
                            changeCounts(added: change.linesAdded, deleted: change.linesDeleted)
                        }
                    }
                }
                .padding(.leading, 28)
            }
        } else {
            Text("Source-control information unavailable.")
                .font(.system(size: theme.typography.caption))
                .foregroundStyle(theme.colors.textMuted)
                .padding(.leading, 28)
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

#if !os(iOS)
                    Button {
                        Task { await viewModel.refreshEnvironment() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(theme.colors.textSecondary)
                    .help("Refresh environment")
#endif
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
            .background(panelBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(theme.colors.border, lineWidth: theme.borders.thin)
                    .allowsHitTesting(false)
            }
    }

    private var panelBackground: Color {
#if os(macOS)
        theme.colors.background
#else
        theme.colors.surfaceRaised.opacity(0.78 as CGFloat)
#endif
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

    private var sourceControlProviderTitle: String {
        switch sourceControl?.providerId {
        case "arcadia-source-control": "Arcadia"
        case "git-cli": "Git"
        case .some(let providerID): providerID.replacingOccurrences(of: "-", with: " ").capitalized
        case nil: "Source control"
        }
    }

    private var sourceControlDetail: String {
        guard let sourceControl else { return "Source-control information unavailable" }
        if sourceControl.isRepository { return "Repository detected" }
        return sourceControl.message ?? "Repository unavailable"
    }

    private var noReviewDetail: String {
        guard let branch = sourceControl?.branch, !branch.isEmpty else {
            return "Current branch is unavailable"
        }
        return "No review found for \(branch)"
    }

    private func reviewTitle(_ review: CodeReviewItem) -> String {
        let number = review.number.map { " #\($0)" } ?? ""
        return "\(review.providerName) review\(number)"
    }

    private func reviewBranchTitle(_ review: CodeReviewItem) -> String {
        let source = review.sourceBranch ?? sourceControl?.branch ?? "branch"
        return "\(source) → \(review.targetBranch ?? "trunk")"
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

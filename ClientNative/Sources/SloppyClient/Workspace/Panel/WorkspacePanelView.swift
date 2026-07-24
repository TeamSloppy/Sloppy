import SwiftUI
import SloppyClientUI

@MainActor
struct WorkspacePanelView: View {
    let viewModel: WorkspacePanelViewModel
    let context: WorkspacePanelContext

    @Environment(\.theme) private var theme

    var body: some View {
        let c = theme.colors
        let sp = theme.spacing
        let ty = theme.typography

        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: sp.s) {
                Image(systemName: viewModel.mode == .files ? "folder" : "safari")
                    .font(.system(size: ty.body, weight: .semibold))
                    .foregroundStyle(c.textPrimary)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 1) {
                    Text(viewModel.mode == .files ? "Files" : "Browser")
                        .font(.system(size: ty.body, weight: .semibold))
                        .foregroundColor(c.textPrimary)
                    Text(context.projectName)
                        .font(.system(size: ty.micro))
                        .foregroundColor(c.textMuted)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                if viewModel.mode == .files {
                    filesToolbarQuickActions
                    Button(action: { Task { await viewModel.refresh() } }) {
                        Icons.symbol(.refresh, size: ty.body)
                            .foregroundColor(c.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .help("Refresh files")
                }
            }
            .padding(sp.m)

            Divider()

            switch viewModel.mode {
            case .files:
                filesPane
            case .webBrowser:
                VStack(spacing: 0) {
                    webToolbar
                    Divider()
                    WorkspaceWebView(viewModel: viewModel.webViewModel)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: context) {
            viewModel.activate(context: context)
        }
        .background {
            Button("") {
                viewModel.toggleToolsMenu()
            }
            .keyboardShortcut("t", modifiers: [.command])
            .opacity(0.001)
            .allowsHitTesting(false)
        }
    }

    private var filesPane: some View {
        GeometryReader { proxy in
            if proxy.size.width >= 600 {
                HStack(spacing: 0) {
                    treePane
                        .frame(minWidth: 220, maxWidth: 320, maxHeight: .infinity)

                    Divider()

                    previewPane
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                VStack(spacing: 0) {
                    treePane
                        .frame(
                            height: min(
                                max(proxy.size.height * 0.42, 180),
                                360
                            )
                        )

                    Divider()

                    previewPane
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    private var treePane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.spacing.xs) {
                if viewModel.isLoadingRoot {
                    Text("Loading project files…")
                        .font(.system(size: theme.typography.caption))
                        .foregroundColor(theme.colors.textMuted)
                        .padding(theme.spacing.m)
                } else if let rootLoadError = viewModel.rootLoadError {
                    Text(rootLoadError)
                        .font(.system(size: theme.typography.caption))
                        .foregroundColor(theme.colors.statusBlocked)
                        .padding(theme.spacing.m)
                } else if viewModel.rootEntries.isEmpty {
                    Text("No files found.")
                        .font(.system(size: theme.typography.caption))
                        .foregroundColor(theme.colors.textMuted)
                        .padding(theme.spacing.m)
                } else {
                    ForEach(viewModel.rootEntries) { node in
                        WorkspacePanelNodeView(
                            viewModel: viewModel,
                            node: node,
                            depth: 0
                        )
                    }
                }
            }
            .padding(.vertical, theme.spacing.s)
        }
    }

    private var previewPane: some View {
        VStack(alignment: .leading, spacing: theme.spacing.s) {
            if let selectedFilePath = viewModel.selectedFilePath {
                Text(selectedFilePath)
                    .font(.system(size: theme.typography.caption))
                    .foregroundColor(theme.colors.textSecondary)
                    .lineLimit(1)
                    .padding(.horizontal, theme.spacing.m)
                    .padding(.top, theme.spacing.m)

                if let fileLoadError = viewModel.fileLoadError {
                    Text(fileLoadError)
                        .font(.system(size: theme.typography.caption))
                        .foregroundColor(theme.colors.statusBlocked)
                        .padding(.horizontal, theme.spacing.m)
                } else if let content = viewModel.selectedFileContent?.content {
                    ScrollView {
                        Text(content)
                            .textSelection(.enabled)
                            .font(.system(size: theme.typography.caption, design: .monospaced))
                            .foregroundColor(theme.colors.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .padding(theme.spacing.m)
                    }
                } else {
                    Text("Loading file…")
                        .font(.system(size: theme.typography.caption))
                        .foregroundColor(theme.colors.textMuted)
                        .padding(.horizontal, theme.spacing.m)
                }
            } else {
                VStack(alignment: .center, spacing: theme.spacing.m) {
                    Spacer(minLength: 0)
                    Icons.symbol(.description, size: theme.typography.title)
                        .foregroundColor(theme.colors.textMuted)
                    Text("Select a file to preview its contents")
                        .font(.system(size: theme.typography.caption))
                        .foregroundColor(theme.colors.textMuted)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var webToolbar: some View {
        let c = theme.colors
        let sp = theme.spacing
        let ty = theme.typography

        return HStack(spacing: sp.s) {
            Button(action: { viewModel.webViewModel.goBack() }) {
                Icons.symbol(.arrowForward, size: ty.caption)
                    .rotationEffect(.degrees(180))
                    .foregroundColor(viewModel.webViewModel.canGoBack ? c.textSecondary : c.textMuted)
            }
            .buttonStyle(.plain)

            Button(action: { viewModel.webViewModel.goForward() }) {
                Icons.symbol(.arrowForward, size: ty.caption)
                    .foregroundColor(viewModel.webViewModel.canGoForward ? c.textSecondary : c.textMuted)
            }
            .buttonStyle(.plain)

            Button(action: { viewModel.webViewModel.reload() }) {
                Icons.symbol(.refresh, size: ty.caption)
                    .foregroundColor(c.textSecondary)
            }
            .buttonStyle(.plain)

            TextField(
                "Open URL",
                text: Binding(
                    get: { viewModel.webViewModel.addressText },
                    set: { viewModel.webViewModel.addressText = $0 }
                )
            )
            .textFieldStyle(.roundedBorder)

            Button("Open") {
                viewModel.webViewModel.openAddress()
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, sp.m)
        .padding(.vertical, sp.s)
    }

    @ViewBuilder
    private var filesToolbarQuickActions: some View {
        if viewModel.mode == .files {
            let selection = viewModel.selectionContext()

            Button {
                viewModel.perform(.openInZed)
            } label: {
                Image(systemName: "arrow.up.forward.app")
            }
            .buttonStyle(.plain)
            .disabled(!selection.canOpenInEditor)
            .help("Open in Zed")

            Button {
                viewModel.perform(.revealInFinder)
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.plain)
            .disabled(!selection.canRevealInFinder)
            .help("Reveal in Finder")

            Menu {
                Button("Open in Zed") {
                    viewModel.perform(.openInZed)
                }
                .disabled(!selection.canOpenInEditor)

                Button("Reveal in Finder") {
                    viewModel.perform(.revealInFinder)
                }
                .disabled(!selection.canRevealInFinder)
            } label: {
                Image(systemName: "ellipsis")
            }
            .buttonStyle(.plain)
            .help("More file actions")
        }
    }
}

@MainActor
private struct WorkspacePanelNodeView: View {
    let viewModel: WorkspacePanelViewModel
    let node: WorkspacePanelViewModel.Node
    let depth: Int

    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: handleTap) {
                HStack(spacing: theme.spacing.s) {
                    Icons.symbol(icon, size: theme.typography.body)
                        .foregroundColor(node.kind == .directory ? theme.colors.textSecondary : theme.colors.textMuted)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(node.name)
                            .font(.system(size: theme.typography.caption))
                            .foregroundColor(theme.colors.textPrimary)
                            .lineLimit(1)
                        if depth == 0, node.path.hasPrefix("/") {
                            Text(node.path)
                                .font(.system(size: theme.typography.micro))
                                .foregroundColor(theme.colors.textMuted)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                    if node.isLoadingChildren {
                        ProgressView()
                            .scaleEffect(0.6)
                    }
                }
                .padding(.leading, CGFloat(depth) * 16 + theme.spacing.m)
                .padding(.trailing, theme.spacing.m)
                .padding(.vertical, theme.spacing.s)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(rowBackground)
            }
            .buttonStyle(.plain)
            .draggable(dragString)

            if node.isExpanded, let children = node.children {
                ForEach(children) { child in
                    WorkspacePanelNodeView(viewModel: viewModel, node: child, depth: depth + 1)
                }
            }
        }
    }

    private var rowBackground: Color {
        viewModel.selectedFilePath == node.path
            ? theme.colors.surfaceGlow.opacity(0.35 as CGFloat)
            : .clear
    }

    private var icon: MaterialSymbol {
        switch node.kind {
        case .directory:
            return node.isExpanded ? .folderOpen : .folder
        case .file:
            return .description
        }
    }

    private var dragString: String {
        viewModel.dragPayload(for: node)?.encodedValue ?? node.path
    }

    private func handleTap() {
        switch node.kind {
        case .directory:
            Task { await viewModel.toggleDirectory(node.path) }
        case .file:
            Task { await viewModel.selectFile(node.path) }
        }
    }
}

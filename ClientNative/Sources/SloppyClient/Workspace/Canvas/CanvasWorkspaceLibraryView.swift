import SloppyClientCore
import SwiftUI

@MainActor
struct CanvasWorkspaceLibraryView: View {
    let viewModel: CanvasWorkspaceViewModel

    @State private var searchText = ""
    @State private var isCreateSheetPresented = false

    private var filteredWorkspaces: [CanvasWorkspaceSummary] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return viewModel.workspaces
        }
        return viewModel.workspaces.filter { workspace in
            workspace.title.localizedStandardContains(query)
                || workspace.description.localizedStandardContains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            libraryHeader
            Divider()

            if let error = viewModel.libraryError {
                libraryErrorBanner(error)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
            }

            libraryContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle(viewModel.libraryTitle)
#if os(iOS)
        .navigationBarTitleDisplayMode(.large)
#endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isCreateSheetPresented = true
                } label: {
                    Label("New Workspace", systemImage: "plus")
                        .labelStyle(.iconOnly)
                }
                .accessibilityLabel("New Workspace")
                .accessibilityIdentifier("canvas-workspace-create")
            }
        }
        .accessibilityIdentifier("canvas-workspace-library")
        .sheet(isPresented: $isCreateSheetPresented) {
            CanvasWorkspaceCreateSheet(viewModel: viewModel)
        }
    }

    private var libraryHeader: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Text(viewModel.librarySubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if viewModel.isResolving, !viewModel.workspaces.isEmpty {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Refreshing workspaces")
                }
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("Search workspaces", text: $searchText)
                    .textFieldStyle(.plain)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear workspace search")
                }

                Divider()
                    .frame(height: 16)

                Text("\(filteredWorkspaces.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)

                Button {
                    Task {
                        await viewModel.refreshLibrary()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isResolving)
                .help("Refresh Workspaces")
                .accessibilityLabel("Refresh workspaces")
            }
            .padding(.horizontal, 11)
            .frame(maxWidth: 440, minHeight: 32)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
    }

    @ViewBuilder
    private var libraryContent: some View {
        if viewModel.isResolving, viewModel.workspaces.isEmpty {
            VStack(spacing: 10) {
                ProgressView()
                Text("Loading Workspaces…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if filteredWorkspaces.isEmpty {
            ContentUnavailableView {
                Label(
                    searchText.isEmpty ? "No Workspaces" : "No Results",
                    systemImage: searchText.isEmpty ? "square.grid.2x2" : "magnifyingglass"
                )
            } description: {
                Text(
                    searchText.isEmpty
                        ? "Create a canvas, then open it in the agent-powered web editor."
                        : "No workspace matches “\(searchText)”."
                )
            } actions: {
                if searchText.isEmpty {
                    Button("Create Workspace") {
                        isCreateSheetPresented = true
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Clear Search") {
                        searchText = ""
                    }
                }
            }
        } else {
            List(filteredWorkspaces) { workspace in
                CanvasWorkspaceLibraryRow(
                    workspace: workspace,
                    isSuggested: workspace.id == viewModel.suggestedWorkspaceID
                ) {
                    viewModel.openWorkspace(workspace)
                }
                .accessibilityIdentifier("canvas-workspace-\(workspace.id)")
            }
            .listStyle(.plain)
        }
    }

    private func libraryErrorBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("Couldn’t load workspaces")
                .font(.callout.weight(.medium))
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            Button("Retry") {
                Task {
                    await viewModel.refreshLibrary()
                }
            }
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

@MainActor
private struct CanvasWorkspaceLibraryRow: View {
    let workspace: CanvasWorkspaceSummary
    let isSuggested: Bool
    let action: @MainActor () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 38, height: 38)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 7) {
                        Text(workspace.title)
                            .font(.body.weight(.medium))
                            .lineLimit(1)

                        if isSuggested {
                            Text("Linked")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(Color.accentColor)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.12), in: Capsule())
                        }
                    }

                    Text(workspace.description.isEmpty ? "Canvas workspace" : workspace.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 16)

                VStack(alignment: .trailing, spacing: 3) {
                    Text("Revision \(workspace.revision)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text(workspace.updatedAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open \(workspace.title)")
        .accessibilityHint("Opens the workspace in the web editor")
    }
}

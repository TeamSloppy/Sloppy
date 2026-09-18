import Foundation
import SwiftUI
import SloppyClientCore
import SloppyClientUI

private struct AgentFileBrowserEntry: Identifiable {
    let entry: ProjectFileEntry
    let path: String
    let depth: Int

    var id: String { path }
}

struct AgentFilesView: View {
    let agent: APIAgentRecord
    let apiClient: SloppyAPIClient

    @Environment(\.theme) private var theme
    @Environment(\.userInterfaceIdiom) private var idiom
    @State private var rootEntries: [ProjectFileEntry] = []
    @State private var childrenByPath: [String: [ProjectFileEntry]] = [:]
    @State private var expandedPaths: Set<String> = []
    @State private var loadingPaths: Set<String> = []
    @State private var selectedPath: String?
    @State private var selectedContent: ProjectFileContentResponse?
    @State private var isLoadingRoot = true
    @State private var isLoadingContent = false
    @State private var errorMessage: String?

    private var visibleEntries: [AgentFileBrowserEntry] {
        flatten(rootEntries, parentPath: "", depth: 0)
    }

    var body: some View {
        Group {
            if idiom == .phone {
                VStack(spacing: 0) {
                    fileTree
                    if selectedPath != nil {
                        Divider().overlay(theme.colors.border)
                        fileViewer.frame(minHeight: 300)
                    }
                }
            } else {
                HStack(spacing: 0) {
                    fileTree.frame(minWidth: 240, idealWidth: 300, maxWidth: 360)
                    Divider().overlay(theme.colors.border)
                    fileViewer
                }
            }
        }
        .task(id: agent.id) { await loadRoot() }
    }

    private var fileTree: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: theme.spacing.s) {
                Image(systemName: "folder.fill").foregroundStyle(theme.colors.accentCyan)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Agent files").font(.headline).foregroundStyle(theme.colors.textPrimary)
                    Text(agent.id).font(.caption.monospaced()).foregroundStyle(theme.colors.textMuted)
                }
                Spacer()
                if isLoadingRoot { ProgressView().controlSize(.small) }
            }
            .padding(theme.spacing.m)

            Divider().overlay(theme.colors.border)

            if let errorMessage, rootEntries.isEmpty {
                ContentUnavailableView("Files unavailable", systemImage: "folder.badge.questionmark", description: Text(errorMessage))
                    .frame(maxWidth: .infinity, minHeight: 250)
            } else if rootEntries.isEmpty && !isLoadingRoot {
                ContentUnavailableView("No visible files", systemImage: "folder", description: Text("This agent directory has no user-visible files."))
                    .frame(maxWidth: .infinity, minHeight: 250)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(visibleEntries) { item in
                            fileRow(item)
                        }
                    }
                    .padding(.vertical, theme.spacing.s)
                }
            }
        }
        .background(theme.colors.surface.opacity(0.55))
    }

    private func fileRow(_ item: AgentFileBrowserEntry) -> some View {
        let isDirectory = item.entry.type == .directory
        let isExpanded = expandedPaths.contains(item.path)
        let isSelected = selectedPath == item.path

        return Button {
            if isDirectory {
                Task { await toggleDirectory(item.path) }
            } else {
                Task { await selectFile(item.path) }
            }
        } label: {
            HStack(spacing: 8) {
                Color.clear.frame(width: CGFloat(item.depth) * 14)
                if isDirectory {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(theme.colors.textMuted)
                        .frame(width: 10)
                } else {
                    Color.clear.frame(width: 10)
                }
                Image(systemName: isDirectory ? (isExpanded ? "folder.fill" : "folder") : fileIcon(item.entry.name))
                    .foregroundStyle(isDirectory ? theme.colors.accentCyan : theme.colors.textSecondary)
                    .frame(width: 18)
                Text(item.entry.name)
                    .font(.subheadline)
                    .foregroundStyle(theme.colors.textPrimary)
                    .lineLimit(1)
                Spacer()
                if loadingPaths.contains(item.path) {
                    ProgressView().controlSize(.mini)
                } else if let size = item.entry.size, !isDirectory {
                    Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                        .font(.caption2)
                        .foregroundStyle(theme.colors.textMuted)
                }
            }
            .padding(.horizontal, theme.spacing.m)
            .padding(.vertical, 8)
            .background(isSelected ? theme.colors.accent.opacity(0.14) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
        .accessibilityIdentifier("agent-files.\(item.path)")
    }

    private var fileViewer: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let selectedPath {
                HStack(spacing: theme.spacing.s) {
                    Image(systemName: "doc.text").foregroundStyle(theme.colors.accentCyan)
                    Text(selectedPath)
                        .font(.caption.monospaced())
                        .foregroundStyle(theme.colors.textSecondary)
                        .lineLimit(1)
                    Spacer()
                    Text("READ ONLY")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(theme.colors.textMuted)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(theme.colors.surfaceRaised, in: Capsule())
                    Button {
                        if let content = selectedContent?.content { UIClipboard.setString(content) }
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .disabled(selectedContent == nil)
                    .accessibilityLabel("Copy file content")
                }
                .padding(theme.spacing.m)

                Divider().overlay(theme.colors.border)

                if isLoadingContent {
                    ProgressView("Loading file…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let content = selectedContent {
                    ScrollView([.horizontal, .vertical]) {
                        Text(content.content.isEmpty ? "This file is empty." : content.content)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(content.content.isEmpty ? theme.colors.textMuted : theme.colors.textPrimary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .padding(theme.spacing.m)
                    }
                } else {
                    ContentUnavailableView("Unable to open file", systemImage: "doc.badge.ellipsis", description: Text(errorMessage ?? "The file may be binary or too large."))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                ContentUnavailableView("Select a file", systemImage: "doc.text.magnifyingglass", description: Text("Browse the agent directory and choose a text file to preview."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(theme.colors.background)
    }

    private func loadRoot() async {
        isLoadingRoot = true
        errorMessage = nil
        defer { isLoadingRoot = false }
        do {
            rootEntries = try await apiClient.fetchAgentFiles(agentId: agent.id)
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func toggleDirectory(_ path: String) async {
        if expandedPaths.contains(path) {
            expandedPaths.remove(path)
            return
        }
        expandedPaths.insert(path)
        guard childrenByPath[path] == nil else { return }
        loadingPaths.insert(path)
        defer { loadingPaths.remove(path) }
        do {
            childrenByPath[path] = try await apiClient.fetchAgentFiles(agentId: agent.id, path: path)
        } catch {
            expandedPaths.remove(path)
            errorMessage = error.localizedDescription
        }
    }

    private func selectFile(_ path: String) async {
        selectedPath = path
        selectedContent = nil
        isLoadingContent = true
        errorMessage = nil
        defer { isLoadingContent = false }
        do {
            selectedContent = try await apiClient.fetchAgentFileContent(agentId: agent.id, path: path)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func flatten(_ entries: [ProjectFileEntry], parentPath: String, depth: Int) -> [AgentFileBrowserEntry] {
        var result: [AgentFileBrowserEntry] = []
        for entry in entries {
            let explicitPath = entry.path?.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let path: String
            if let explicitPath, !explicitPath.isEmpty {
                path = explicitPath
            } else {
                path = parentPath.isEmpty ? entry.name : "\(parentPath)/\(entry.name)"
            }
            result.append(AgentFileBrowserEntry(entry: entry, path: path, depth: depth))
            if entry.type == .directory, expandedPaths.contains(path), let children = childrenByPath[path] {
                result.append(contentsOf: flatten(children, parentPath: path, depth: depth + 1))
            }
        }
        return result
    }

    private func fileIcon(_ name: String) -> String {
        switch URL(fileURLWithPath: name).pathExtension.lowercased() {
        case "md", "markdown": "doc.richtext"
        case "json", "yaml", "yml", "toml": "curlybraces"
        case "swift", "js", "ts", "tsx", "jsx", "py": "chevron.left.forwardslash.chevron.right"
        default: "doc"
        }
    }
}

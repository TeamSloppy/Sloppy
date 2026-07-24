import Foundation
import SwiftUI
import SloppyClientCore

#if canImport(AppKit)
import AppKit
#endif

@MainActor
struct ProjectEditorSheet: View {
    enum Source: String, CaseIterable, Identifiable {
        case empty
        case clone
        case directory
        case workspace

        var id: String { rawValue }

        var title: String {
            switch self {
            case .empty: "Empty Project"
            case .clone: "Clone Repository"
            case .directory: "Open Directory"
            case .workspace: "Workspace"
            }
        }

        var icon: String {
            switch self {
            case .empty: "doc.badge.plus"
            case .clone: "arrow.down.circle"
            case .directory: "folder"
            case .workspace: "square.stack.3d.up"
            }
        }
    }

    let baseURL: URL
    let project: APIProjectRecord?
    let onSaved: @MainActor (APIProjectRecord) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var source: Source
    @State private var name: String
    @State private var projectDescription: String
    @State private var repoURL = ""
    @State private var directoryPaths: [String]
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(
        baseURL: URL,
        project: APIProjectRecord? = nil,
        onSaved: @escaping @MainActor (APIProjectRecord) -> Void
    ) {
        self.baseURL = baseURL
        self.project = project
        self.onSaved = onSaved
        _name = State(initialValue: project?.name ?? "")
        _projectDescription = State(initialValue: project?.description ?? "")
        let paths = project?.directoryPaths.isEmpty == false
            ? project?.directoryPaths ?? []
            : project?.projectRootPath.map { [$0] } ?? []
        _directoryPaths = State(initialValue: paths)
        _source = State(initialValue: project?.kind == .workspace ? .workspace : (paths.isEmpty ? .empty : .directory))
    }

    private var canPickLocalDirectories: Bool {
        #if os(macOS)
        ServerAddress.isLoopbackHost(baseURL.host)
        #else
        false
        #endif
    }

    private var validationMessage: String? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Project name is required."
        }
        switch source {
        case .clone:
            if project != nil { return "Repository cloning is only available when creating a project." }
            if repoURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "Repository URL is required."
            }
        case .directory:
            if !canPickLocalDirectories { return "Local directories are available only with a loopback Core on macOS." }
            if directoryPaths.count != 1 { return "Select one directory." }
        case .workspace:
            if !canPickLocalDirectories { return "Workspaces are available only with a loopback Core on macOS." }
            if directoryPaths.count < 2 { return "A workspace requires at least two directories." }
        case .empty:
            break
        }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Project") {
                    TextField("Name", text: $name)
                    TextField("Description", text: $projectDescription, axis: .vertical)
                        .lineLimit(2...5)
                }

                Section(project == nil ? "Source" : "Project type") {
                    sourceCards
                }

                if source == .clone {
                    Section("Repository") {
                        TextField("https://github.com/owner/repository.git", text: $repoURL)
                            .textContentType(.URL)
                    }
                }

                if source == .directory || source == .workspace {
                    directoriesSection
                }

                if let message = errorMessage ?? validationMessage {
                    Section {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(project == nil ? "New Project" : "Edit Project")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(project == nil ? "Create" : "Save") {
                        save()
                    }
                    .disabled(validationMessage != nil || isSaving)
                }
            }
        }
        .frame(minWidth: 560, minHeight: 520)
        .interactiveDismissDisabled(isSaving)
    }

    private var sourceCards: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
            ForEach(Source.allCases) { item in
                let unavailable = (item == .directory || item == .workspace) && !canPickLocalDirectories
                    || (project != nil && (item == .clone || item == .empty) && source != item)
                Button {
                    source = item
                    if item == .empty { directoryPaths = [] }
                    if item == .directory, directoryPaths.count > 1 {
                        directoryPaths = Array(directoryPaths.prefix(1))
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: item.icon)
                            .font(.title2)
                        Text(item.title)
                            .font(.headline)
                        if unavailable {
                            Text(item == .clone ? "Create only" : "Local macOS Core only")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
                    .padding(12)
                    .background(
                        source == item ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 12)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(source == item ? Color.accentColor : .clear, lineWidth: 1.5)
                    }
                }
                .buttonStyle(.plain)
                .disabled(unavailable)
            }
        }
    }

    private var directoriesSection: some View {
        Section {
            if directoryPaths.isEmpty {
                Text("No directories selected")
                    .foregroundStyle(.secondary)
            }

            ForEach(Array(directoryPaths.enumerated()), id: \.element) { index, path in
                HStack(spacing: 10) {
                    Image(systemName: index == 0 ? "1.circle.fill" : "folder")
                        .foregroundStyle(index == 0 ? Color.accentColor : Color.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(URL(fileURLWithPath: path).lastPathComponent)
                            .lineLimit(1)
                        Text(index == 0 ? "Primary · \(path)" : path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button { move(index, by: -1) } label: { Image(systemName: "arrow.up") }
                        .disabled(index == 0)
                    Button { move(index, by: 1) } label: { Image(systemName: "arrow.down") }
                        .disabled(index == directoryPaths.count - 1)
                    Button(role: .destructive) { directoryPaths.remove(at: index) } label: {
                        Image(systemName: "minus.circle")
                    }
                }
            }

            Button {
                pickDirectories(allowsMultiple: source == .workspace)
            } label: {
                Label(directoryPaths.isEmpty ? "Choose Directories" : "Add Directory", systemImage: "plus")
            }
            .disabled(!canPickLocalDirectories || (source == .directory && !directoryPaths.isEmpty))
        } header: {
            Text("Directories")
        } footer: {
            Text("The first directory is Primary and provides terminal and source-control cwd. All directories are available to the agent.")
        }
    }

    private func move(_ index: Int, by offset: Int) {
        let destination = index + offset
        guard directoryPaths.indices.contains(index), directoryPaths.indices.contains(destination) else { return }
        directoryPaths.swapAt(index, destination)
    }

    private func pickDirectories(allowsMultiple: Bool) {
        #if os(macOS)
        guard canPickLocalDirectories else { return }
        let selected = LocalProjectDirectoryPicker.selectDirectories(allowsMultiple: allowsMultiple)
        for path in selected where !directoryPaths.contains(path) {
            directoryPaths.append(path)
        }
        if !allowsMultiple, let first = directoryPaths.first {
            directoryPaths = [first]
        }
        #endif
    }

    private func save() {
        guard validationMessage == nil else { return }
        isSaving = true
        errorMessage = nil
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = projectDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let kind: APIProjectKind = source == .workspace ? .workspace : .project
        let paths = source == .directory || source == .workspace ? directoryPaths : []
        let repoPath = source == .directory ? paths.first : nil
        let client = SloppyAPIClient(baseURL: baseURL)

        Task {
            do {
                let saved: APIProjectRecord
                if let project {
                    saved = try await client.updateProject(
                        id: project.id,
                        request: APIProjectUpdateRequest(
                            name: trimmedName,
                            description: trimmedDescription,
                            kind: kind,
                            directoryPaths: paths
                        )
                    )
                } else {
                    saved = try await client.createProject(
                        APIProjectCreateRequest(
                            name: trimmedName,
                            description: trimmedDescription,
                            repoUrl: source == .clone ? repoURL.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
                            repoPath: repoPath,
                            kind: kind,
                            directoryPaths: source == .workspace ? paths : []
                        )
                    )
                }
                onSaved(saved)
                dismiss()
            } catch let error as APIError {
                errorMessage = error.localizedProjectEditorDescription
                isSaving = false
            } catch {
                errorMessage = error.localizedDescription
                isSaving = false
            }
        }
    }
}

private extension APIError {
    var localizedProjectEditorDescription: String {
        switch self {
        case .invalidResponse:
            "Core returned an invalid response."
        case let .httpError(statusCode, body):
            body?.isEmpty == false ? body! : "Core returned HTTP \(statusCode)."
        case let .decodingFailed(message):
            message
        }
    }
}

#if os(macOS)
@MainActor
private enum LocalProjectDirectoryPicker {
    static func selectDirectories(allowsMultiple: Bool) -> [String] {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = allowsMultiple
        panel.canCreateDirectories = true
        panel.prompt = allowsMultiple ? "Add" : "Choose"
        guard panel.runModal() == .OK else { return [] }
        return panel.urls.map { $0.standardizedFileURL.path }
    }
}
#endif

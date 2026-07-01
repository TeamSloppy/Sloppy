import Foundation
import Observation
import SloppyClientCore

struct WorkspacePanelContext: Equatable, Sendable {
    var projectId: String
    var projectName: String
}

enum WorkspacePanelMode: Equatable {
    case files
    case reviews
    case webBrowser
}

enum WorkspacePanelAction: Equatable {
    case openInZed
    case revealInFinder
    case showToolsMenu
}

struct WorkspacePanelSelectionContext: Equatable {
    var selectedPath: String?
    var canOpenInEditor: Bool
    var canRevealInFinder: Bool
}

@Observable
@MainActor
final class WorkspacePanelViewModel {
    struct Node: Identifiable, Equatable {
        enum Kind: Equatable {
            case file
            case directory
        }

        var id: String { path }
        var name: String
        var path: String
        var kind: Kind
        var size: Int?
        var isExpanded = false
        var isLoadingChildren = false
        var children: [Node]? = nil
    }

    let apiClient: SloppyAPIClient
    var mode: WorkspacePanelMode = .files
    var webViewModel: WorkspaceWebViewModel
    var isToolsMenuPresented = false
    private(set) var context: WorkspacePanelContext?
    private(set) var rootEntries: [Node] = []
    private(set) var selectedFilePath: String?
    private(set) var selectedFileContent: ProjectFileContentResponse?
    private(set) var isLoadingRoot = false
    private(set) var rootLoadError: String?
    private(set) var fileLoadError: String?
    private(set) var actionStatus: String?

    init(apiClient: SloppyAPIClient) {
        self.apiClient = apiClient
        self.webViewModel = WorkspaceWebViewModel()
    }

    func activate(context: WorkspacePanelContext) {
        guard self.context != context else { return }
        self.context = context
        Task { await refresh() }
    }

    func refresh() async {
        guard let context else { return }

        isLoadingRoot = true
        rootLoadError = nil
        selectedFilePath = nil
        selectedFileContent = nil
        fileLoadError = nil

        do {
            let entries = try await apiClient.fetchProjectFiles(projectId: context.projectId, path: "")
            rootEntries = entries.map { Self.node(from: $0, parentPath: nil) }
        } catch {
            rootEntries = []
            rootLoadError = "Could not load project files."
        }

        isLoadingRoot = false
    }

    func toggleDirectory(_ path: String) async {
        guard let context else { return }
        guard Self.toggleExpanded(path, in: &rootEntries) else { return }
        guard Self.needsChildLoad(path, in: rootEntries) else { return }

        Self.setLoading(true, for: path, in: &rootEntries)
        do {
            let entries = try await apiClient.fetchProjectFiles(projectId: context.projectId, path: path)
            Self.setChildren(
                entries.map { Self.node(from: $0, parentPath: path) },
                for: path,
                in: &rootEntries
            )
        } catch {
            Self.setChildren([], for: path, in: &rootEntries)
        }
        Self.setLoading(false, for: path, in: &rootEntries)
    }

    func selectFile(_ path: String) async {
        guard let context else { return }

        selectedFilePath = path
        selectedFileContent = nil
        fileLoadError = nil

        do {
            selectedFileContent = try await apiClient.fetchProjectFileContent(projectId: context.projectId, path: path)
        } catch {
            fileLoadError = "Unable to load file. It may be binary or too large."
        }
    }

    func dragPayload(for node: Node) -> WorkspacePanelDragPayload? {
        guard let context else { return nil }
        return WorkspacePanelDragPayload(
            projectId: context.projectId,
            path: node.path,
            type: node.kind == .directory ? "directory" : "file"
        )
    }

    func switchMode(_ mode: WorkspacePanelMode) {
        self.mode = mode
    }

    func toggleToolsMenu() {
        isToolsMenuPresented.toggle()
    }

    func selectionContext() -> WorkspacePanelSelectionContext {
        WorkspacePanelSelectionContext(
            selectedPath: selectedFilePath,
            canOpenInEditor: selectedFilePath != nil,
            canRevealInFinder: selectedFilePath != nil
        )
    }

    func perform(_ action: WorkspacePanelAction) {
        switch action {
        case .openInZed:
            guard let path = selectedFilePath else { return }
            actionStatus = "Open in Zed: \(path)"
        case .revealInFinder:
            guard let path = selectedFilePath else { return }
            actionStatus = "Reveal in Finder: \(path)"
        case .showToolsMenu:
            toggleToolsMenu()
        }
    }

    private static func node(from entry: ProjectFileEntry, parentPath: String?) -> Node {
        let path = parentPath.map { "\($0)/\(entry.name)" } ?? entry.name
        return Node(
            name: entry.name,
            path: path,
            kind: entry.type == .directory ? .directory : .file,
            size: entry.size
        )
    }

    private static func toggleExpanded(_ path: String, in nodes: inout [Node]) -> Bool {
        for index in nodes.indices {
            if nodes[index].path == path {
                guard nodes[index].kind == .directory else { return false }
                nodes[index].isExpanded.toggle()
                return true
            }
            if nodes[index].children != nil,
               toggleExpanded(path, in: &nodes[index].children!) {
                return true
            }
        }
        return false
    }

    private static func needsChildLoad(_ path: String, in nodes: [Node]) -> Bool {
        for node in nodes {
            if node.path == path {
                return node.kind == .directory && node.isExpanded && node.children == nil
            }
            if let children = node.children,
               needsChildLoad(path, in: children) {
                return true
            }
        }
        return false
    }

    private static func setLoading(_ isLoading: Bool, for path: String, in nodes: inout [Node]) {
        for index in nodes.indices {
            if nodes[index].path == path {
                nodes[index].isLoadingChildren = isLoading
                return
            }
            if nodes[index].children != nil {
                setLoading(isLoading, for: path, in: &nodes[index].children!)
            }
        }
    }

    private static func setChildren(_ children: [Node], for path: String, in nodes: inout [Node]) {
        for index in nodes.indices {
            if nodes[index].path == path {
                nodes[index].children = children
                return
            }
            if nodes[index].children != nil {
                setChildren(children, for: path, in: &nodes[index].children!)
            }
        }
    }
}

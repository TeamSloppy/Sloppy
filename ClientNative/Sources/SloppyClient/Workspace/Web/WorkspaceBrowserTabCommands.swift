import Foundation
import SloppyClientCore

extension WorkspaceBrowserSession {
    func executeTabs(_ input: WorkspaceBrowserCommand.Input) throws -> WorkspaceBrowserPage {
        guard let workspace, workspace.isBrowsing else { throw WorkspaceBrowserRuntimeError.unavailable }
        switch input.operation {
        case "list": break
        case "open":
            // Validate before creating a tab; a malformed command must not mutate the workspace.
            let url = try input.url.map { raw in
                guard let resolved = WorkspaceBrowserAddress.resolve(raw) else { throw WorkspaceBrowserRuntimeError.invalidURL }
                return resolved
            }
            let id = workspace.createBlankTab()
            if let url, url.absoluteString != "about:blank" { workspace.navigate(url, inTab: id) }
        case "select", "close":
            guard let raw = input.tabId, let id = UUID(uuidString: raw),
                  workspace.tabs.contains(where: { $0.id == id }) else {
                throw WorkspaceBrowserRuntimeError.invalidArguments
            }
            if input.operation == "select" { workspace.select(id) }
            else { workspace.close(id) }
        default: throw WorkspaceBrowserRuntimeError.invalidArguments
        }
        if let selected = workspace.selectedPage { viewModel = selected }
        else if input.operation == "close" { viewModel = WorkspaceWebViewModel(history: workspace.history) }
        return workspaceSnapshot(workspace)
    }

    func workspaceSnapshot(_ workspace: BrowserWorkspaceState) -> WorkspaceBrowserPage {
        var result = WorkspaceBrowserPage(pageId: workspace.selectedPage?.browserRuntime?.pageID ?? "",
            url: workspace.selectedTab?.url?.absoluteString ?? "about:blank",
            title: workspace.selectedTab?.title ?? "Browse", visibleText: "", running: true)
        result.workspace = .init(tabs: workspace.tabs.prefix(500).map { tab in
            .init(id: tab.id.uuidString, title: String(tab.title.prefix(512)),
                  url: tab.url?.absoluteString, selected: workspace.selectedID == tab.id, groupId: tab.groupID?.uuidString)
        })
        result.workspace?.groups = workspace.groups.prefix(100).map { .init(id: $0.id.uuidString, title: $0.title) }
        return result
    }
}

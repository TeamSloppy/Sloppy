import Foundation

extension WorkspaceService {
    public func registerBrowser(_ binding: WorkspaceBrowserBinding) async throws {
        let _: ConfigJSONValue = try await http.post("/v1/workspace-browser/register", body: binding)
    }
    public func pollBrowser(_ binding: WorkspaceBrowserBinding) async throws -> WorkspaceBrowserCommands {
        try await http.post("/v1/workspace-browser/poll", body: binding)
    }
    public func completeBrowser(_ completion: WorkspaceBrowserCompletion) async throws {
        let _: ConfigJSONValue = try await http.post("/v1/workspace-browser/complete", body: completion)
    }
    public func disconnectBrowser(_ binding: WorkspaceBrowserBinding) async throws {
        let _: ConfigJSONValue = try await http.post("/v1/workspace-browser/disconnect", body: binding)
    }
}
